<?php
declare(strict_types=1);
if (PHP_SAPI !== 'cli') exit;
require 'C:/xampp/htdocs/CoffeyTableRecipes/src/bootstrap.php';
require_once 'C:/xampp/htdocs/CoffeyTableRecipes/src/RecipeImportTools.php';
if (in_array('--cleanup-existing', $argv, true)) {
    require 'C:/xampp/htdocs/CoffeyTableRecipes/bin/cleanup-recipe-import.php';
    exit;
}
$pdo = database(configuration());
$destinations = $pdo->query("SELECT h.id,h.name,m.user_id,u.display_name,m.role FROM households h JOIN household_memberships m ON m.household_id=h.id JOIN users u ON u.id=m.user_id WHERE u.disabled=0 AND m.role IN ('owner','admin')")->fetchAll(PDO::FETCH_ASSOC);
if (count($destinations)!==1 || (int)$destinations[0]['id']!==2 || (int)$destinations[0]['user_id']!==6) throw new RuntimeException('Destination changed: resolve household before importing.');
$input = file_get_contents(__DIR__.'/import-ready.json');
$data = json_decode(ltrim($input, "\xEF\xBB\xBF"), true, 100, JSON_THROW_ON_ERROR);
$commit = in_array('--reviewed-commit', $argv, true);
if ($commit && in_array('--dry-run', $argv, true)) throw new RuntimeException('Choose one import mode');
function insertRow(PDO $pdo, string $table, array $row): int {
    $columns = array_keys($row);
    $sql='INSERT INTO '.$table.' (`'.implode('`,`',$columns).'`) VALUES ('.implode(',',array_fill(0,count($columns),'?')).')';
    $pdo->prepare($sql)->execute(array_values($row));
    return (int)$pdo->lastInsertId();
}
function minutes(?string $duration): ?int {
    if (!$duration || !preg_match('/^PT(?:(\d+)H)?(?:(\d+)M)?$/',$duration,$m)) return null;
    return ((int)($m[1]??0))*60+(int)($m[2]??0);
}
function ingredient(string $text): array {
    $clean=trim(html_entity_decode(strip_tags($text),ENT_QUOTES|ENT_HTML5,'UTF-8'));
    $row=['original_text'=>$text,'ingredient_name'=>$clean,'scale_quantity'=>0];
    if (preg_match('/^(\d+\s+\d+\/\d+|\d+\/\d+|\d+(?:\.\d+)?)(?:\s+|$)(.*)$/u',$clean,$m)) {
        $row['quantity_text']=$m[1]; $row['ingredient_name']=trim($m[2]); $row['scale_quantity']=1;
        if (preg_match('/^(?:(\d+)\s+)?(\d+)\/(\d+)$/',$m[1],$f)) {
            if ((int)$f[3]===0) throw new RuntimeException('Invalid fraction');
            $row['quantity_numerator']=(int)($f[1]??0)*(int)$f[3]+(int)$f[2]; $row['quantity_denominator']=(int)$f[3];
        } else { $row['quantity_decimal']=$m[1]; }
        if (preg_match('/^(cups?|tablespoons?|teaspoons?|ounces?|pounds?|grams?|g|kg|ml|l)\b\s*(.*)$/iu',$row['ingredient_name'],$u)) {
            $row['original_unit']=$u[1]; $row['ingredient_name']=trim($u[2]);
            $units=['g'=>'g','gram'=>'g','grams'=>'g','kg'=>'kg','ml'=>'ml','l'=>'l'];
            $row['unit_code']=$units[strtolower($u[1])]??null;
        }
        // Parenthetical equivalents remain preserved in original_text.
        $row['ingredient_name']=trim(preg_replace('/^\([^)]*\)\s*/u','',$row['ingredient_name']));
    }
    if (!$row['ingredient_name'] || mb_strlen($row['ingredient_name'])>300) throw new RuntimeException('Ingredient needs manual review');
    return $row;
}
$report=[];
foreach ($data as $recipe) {
    if (!trim($recipe['title']) || !$recipe['ingredients_original'] || !$recipe['instructions_original']) throw new RuntimeException('Incomplete recipe');
    $key=hash('sha256',$recipe['source_url']);
    $existing=$pdo->prepare('SELECT id FROM recipes WHERE household_id=? AND import_key=?'); $existing->execute([2,$key]);
    if ($id=$existing->fetchColumn()) { $report[]=['title'=>$recipe['title'],'status'=>'skipped_existing','id'=>(int)$id]; continue; }
    $verifiedPhotos=[]; $photoFailures=[];
    foreach (RecipeImportTools::images($recipe['image_source']??null,$recipe['source_url']) as $candidate) {
        try { $verifiedPhotos[]=array_merge(RecipeImportTools::verifyImage($candidate['source_url']), ['caption'=>$candidate['caption']]); }
        catch (Throwable $error) { $photoFailures[]=['source_url'=>$candidate['source_url'],'error'=>$error->getMessage()]; }
    }
    $pdo->beginTransaction();
    try {
        $author=$recipe['author'];
        $authorName=is_string($author)?$author:($author['name']??null);
        if (!$authorName && is_array($author) && isset($author[0])) $authorName=implode(', ',array_filter(array_column($author,'name')));
        $id=insertRow($pdo,'recipes',[
            'household_id'=>2,'title'=>$recipe['title'],'original_language'=>'en','measurement_system'=>'unspecified',
            'source_type'=>'bookmark_jsonld','source_url'=>$recipe['source_url'],'source_title'=>$recipe['title'],'source_author'=>$authorName,
            'source_reference'=>$recipe['bookmark_url'],'source_text'=>json_encode($recipe,JSON_UNESCAPED_UNICODE|JSON_THROW_ON_ERROR),
            'import_key'=>$key,'yield_text'=>RecipeImportTools::yieldValue($recipe['yield'],$recipe['instructions_original'],$recipe['source_url']),
            'prep_minutes'=>minutes($recipe['prep_time']),'cook_minutes'=>minutes($recipe['cook_time']),'total_minutes'=>minutes($recipe['total_time']),
            'created_by_user_id'=>6,'updated_by_user_id'=>6,
            'notes'=>null
        ]);
        foreach($recipe['ingredients_original'] as $position=>$line) insertRow($pdo,'recipe_ingredients',['household_id'=>2,'recipe_id'=>$id,'position'=>$position+1]+ingredient($line));
        foreach($recipe['instructions_original'] as $position=>$step) insertRow($pdo,'recipe_steps',['household_id'=>2,'recipe_id'=>$id,'position'=>$position+1,'instruction'=>$step]);
        foreach(['category'=>'category','cuisine'=>'cuisine'] as $field=>$kind) foreach(array_unique((array)$recipe[$field]) as $label) {
            if(!is_string($label)||!trim($label)||mb_strlen($label)>120)continue;
            if($kind==='category' && RecipeImportTools::excludedCategory($recipe['source_url'],$label))continue;
            insertRow($pdo,'recipe_tags',['household_id'=>2,'recipe_id'=>$id,'kind'=>$kind,'label'=>$label]);
        }
        foreach(RecipeImportTools::pendingPhotos([], $verifiedPhotos, $authorName?:parse_url($recipe['source_url'],PHP_URL_HOST)) as $photo) insertRow($pdo,'recipe_photos',['household_id'=>2,'recipe_id'=>$id]+$photo);
        if ($commit) $pdo->commit(); else $pdo->rollBack();
        $report[]=['title'=>$recipe['title'],'status'=>$commit?'imported':'validated_rolled_back','ingredients'=>count($recipe['ingredients_original']),'steps'=>count($recipe['instructions_original']),'verified_photos'=>count($verifiedPhotos),'photo_failures'=>$photoFailures];
    } catch(Throwable $e) { if($pdo->inTransaction())$pdo->rollBack(); throw $e; }
}
echo json_encode($report,JSON_PRETTY_PRINT|JSON_UNESCAPED_UNICODE|JSON_THROW_ON_ERROR).PHP_EOL;
