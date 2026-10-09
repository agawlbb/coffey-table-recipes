<?php
declare(strict_types=1);
require 'C:/xampp/htdocs/CoffeyTableRecipes/src/bootstrap.php';
require 'C:/xampp/htdocs/CoffeyTableRecipes/src/RecipeImportTools.php';
require __DIR__.'/HostedImport.php';
$checks=0;
function checkHosted(bool $ok,string $message): void {global $checks; if(!$ok)throw new RuntimeException($message);$checks++;}
checkHosted(HostedImport::ingredient('.5 oz lime juice')['quantity_decimal']==='0.5','Leading decimal');
$fraction=HostedImport::ingredient('1 ¼ cups mozzarella');
checkHosted($fraction['quantity_numerator']===5 && $fraction['quantity_denominator']===4,'Exact Unicode mixed fraction');
checkHosted(HostedImport::ingredient('remaining ¼ cup mozzarella')['quantity_numerator']===1,'Additional fractional quantity');
checkHosted(HostedImport::ingredient('1/2 c. milk')['ingredient_name']==='milk','Abbreviated unit');
checkHosted(HostedImport::ingredient('ground beef')['scale_quantity']===0,'Missing quantity remains unknown');
checkHosted(HostedImport::minutes('PT0M')===null && HostedImport::minutes('PT1H5M')===65,'Placeholder duration');
$config=configuration();
if ($config['environment']!=='development')throw new RuntimeException('Disposable local test only');
$db=$config['database'];
$admin=new PDO(sprintf('mysql:host=%s;port=%d;charset=utf8mb4',$db['host'],$db['port']),$db['user'],$db['password'],[PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION]);
$name='coffey_hosted_import_test_'.bin2hex(random_bytes(5));
$admin->exec("CREATE DATABASE `$name` CHARACTER SET utf8mb4");
try {
    $config['database']['name']=$name;$pdo=database($config);
    foreach(glob('C:/xampp/htdocs/CoffeyTableRecipes/database/migrations/*.sql') as $file)foreach(explode(';',file_get_contents($file)) as $statement)if(trim($statement)!=='')$pdo->exec($statement);
    $pdo->exec("INSERT INTO households(id,name) VALUES(2,'Fixture'),(3,'Other household'); INSERT INTO users(id,firebase_uid) VALUES(6,'fixture'); INSERT INTO household_memberships(household_id,user_id,role) VALUES(2,6,'owner')");
    $recipe=['title'=>"Chef's cake 🍰; DROP TABLE recipes;",'source_url'=>'https://example.com/cake','ingredients_original'=>['1 ¼ cups flour'], 'instructions_original'=>["Bake; let cool. It's done."], 'verified_photos'=>[['source_url'=>'https://coffeybean.com/CoffeyTableRecipes/media/recipe-photos/'.str_repeat('a',64).'.jpg','storage_key'=>'media/recipe-photos/'.str_repeat('a',64).'.jpg','mime_type'=>'image/jpeg','width_pixels'=>120,'height_pixels'=>80]]];
    $recipe['author']=[['name'=>'Fixture author']];
    $hotlinked=$recipe;
    $hotlinked['verified_photos'][0]['source_url']='https://example.com/photo.jpg';
    try {HostedImport::sql([$hotlinked],2,6);throw new RuntimeException('Hotlink accepted');}
    catch(RuntimeException $error){checkHosted(str_contains($error->getMessage(),'downloaded and archived'),'External images cannot be imported as hotlinks');}
    $run=function(string $sql)use($pdo){foreach(explode(';',$sql) as $statement)if(trim($statement)!==''){$query=$pdo->query($statement);$query->closeCursor();}};
    $run(HostedImport::sql([$recipe],3,6));
    checkHosted((int)$pdo->query('SELECT COUNT(*) FROM recipes')->fetchColumn()===0,'Unauthorized destination has no writes');
    $run(HostedImport::sql([$recipe],2,6));
    checkHosted($pdo->query('SELECT title FROM recipes')->fetchColumn()===$recipe['title'],'Unicode/apostrophes/SQL punctuation preserved without execution');
    checkHosted($pdo->query('SELECT instruction FROM recipe_steps')->fetchColumn()===$recipe['instructions_original'][0],'Instruction preservation');
    checkHosted((int)$pdo->query('SELECT quantity_numerator FROM recipe_ingredients')->fetchColumn()===5,'Exact fraction stored');
    checkHosted((int)$pdo->query('SELECT SUM(is_cover) FROM recipe_photos')->fetchColumn()===1,'Validated source cover');
    checkHosted($pdo->query('SELECT attribution FROM recipe_photos')->fetchColumn()==='Fixture author','Structured source author retained as attribution');
    checkHosted($pdo->query('SELECT storage_key FROM recipe_photos')->fetchColumn()===$recipe['verified_photos'][0]['storage_key'],'Archived storage key retained');
    $pdo->exec("UPDATE recipes SET title='User edit'");
    $run(HostedImport::sql([$recipe],2,6));
    checkHosted((int)$pdo->query('SELECT COUNT(*) FROM recipes')->fetchColumn()===1 && $pdo->query('SELECT title FROM recipes')->fetchColumn()==='User edit','Idempotency preserves user edits');
    checkHosted((int)$pdo->query('SELECT COUNT(*) FROM recipe_ingredients')->fetchColumn()===1 && (int)$pdo->query('SELECT COUNT(*) FROM recipe_photos')->fetchColumn()===1,'No duplicate children');
    if (isset($argv[1])) {
        $run(file_get_contents($argv[1]));
        checkHosted((int)$pdo->query('SELECT COUNT(*) FROM recipes')->fetchColumn()===6,'Prepared five-recipe export executes');
        $before=$pdo->query('SELECT COUNT(*) FROM recipe_ingredients')->fetchColumn();
        $run(file_get_contents($argv[1]));
        checkHosted($before===$pdo->query('SELECT COUNT(*) FROM recipe_ingredients')->fetchColumn(),'Prepared export rerun does not duplicate');
    }
} finally {$admin->exec("DROP DATABASE `$name`");}
echo "$checks hosted import checks passed.\n";
