<?php
declare(strict_types=1);

/** Data-only SQL export. No connection, credentials, migrations or existing-row updates. */
final class HostedImport
{
    public static function literal(mixed $value): string
    {
        if ($value === null) return 'NULL';
        if (is_int($value)) return (string)$value;
        $value = (string)$value;
        return $value === '' ? "''" : 'CONVERT(0x'.bin2hex($value).' USING utf8mb4) COLLATE utf8mb4_unicode_ci';
    }

    public static function ingredient(string $original): array
    {
        $text = trim(html_entity_decode(strip_tags($original), ENT_QUOTES|ENT_HTML5, 'UTF-8'));
        $row = ['original_text'=>$original, 'ingredient_name'=>$text, 'scale_quantity'=>0];
        $fractions = ['¼'=>'1/4','½'=>'1/2','¾'=>'3/4','⅓'=>'1/3','⅔'=>'2/3','⅛'=>'1/8','⅜'=>'3/8','⅝'=>'5/8','⅞'=>'7/8'];
        $parse = preg_replace('/(\d)([¼½¾⅓⅔⅛⅜⅝⅞])/u', '$1 $2', $text);
        $parse = strtr($parse, $fractions);
        // "remaining" is source wording for an additional measured ingredient.
        $parse = preg_replace('/^remaining\s+/i', '', $parse);
        if (preg_match('/^(\d+\s+\d+\/\d+|\d+\/\d+|(?:\d+(?:\.\d+)?|\.\d+))(?:\s+|$)(.*)$/u', $parse, $m)) {
            $row['quantity_text']=$m[1];
            $row['ingredient_name']=trim($m[2]);
            $row['scale_quantity']=1;
            if (preg_match('/^(?:(\d+)\s+)?(\d+)\/(\d+)$/', $m[1], $f)) {
                if ((int)$f[3]===0) throw new RuntimeException('Zero denominator');
                $row['quantity_numerator']=(int)($f[1]??0)*(int)$f[3]+(int)$f[2];
                $row['quantity_denominator']=(int)$f[3];
            } else $row['quantity_decimal']=str_starts_with($m[1],'.')?'0'.$m[1]:$m[1];
            if (preg_match('/^(cups?|c\.|tablespoons?|tbsp\.|teaspoons?|tsp\.|ounces?|oz\.?|pounds?|lb\.?|grams?|g|kg|ml|l)\s+(.*)$/iu', $row['ingredient_name'], $u)) {
                $row['original_unit']=$u[1];
                $row['ingredient_name']=trim($u[2]);
                $row['unit_code']=match(strtolower($u[1])){'g','gram','grams'=>'g','kg'=>'kg','ml'=>'ml','l'=>'l',default=>null};
            }
            $row['ingredient_name']=trim(preg_replace('/^\([^)]*\)\s*/u', '', $row['ingredient_name']));
        }
        if ($row['ingredient_name']==='' || mb_strlen($row['ingredient_name'])>300) throw new RuntimeException('Invalid ingredient name');
        return $row;
    }

    public static function minutes(?string $value): ?int
    {
        if (!$value || !preg_match('/^PT(?:(\d+)H)?(?:(\d+)M)?$/', $value, $m)) return null;
        $minutes=(int)($m[1]??0)*60+(int)($m[2]??0);
        return $minutes>0?$minutes:null;
    }

    private static function insert(string $table, array $row): string
    {
        // Table/column identifiers are exclusively internal constants.
        $columns='`'.implode('`,`', array_keys($row)).'`';
        $values=array_map([self::class,'literal'], array_values($row));
        if (array_key_exists('recipe_id',$row)) $values[array_search('recipe_id',array_keys($row),true)]='@recipe_import_id';
        return "INSERT INTO `$table` ($columns) SELECT ".implode(',', $values).' WHERE @recipe_import_new=1;';
    }

    public static function sql(array $recipes, int $household, int $user): string
    {
        if ($household<1 || $user<1 || !$recipes) throw new RuntimeException('Explicit destination and recipes required');
        $out=["SET NAMES utf8mb4;", "SET @recipe_import_allowed=(SELECT COUNT(*) FROM households h JOIN household_memberships m ON m.household_id=h.id JOIN users u ON u.id=m.user_id WHERE h.id=$household AND m.user_id=$user AND m.role IN ('owner','admin') AND u.disabled=0);", 'START TRANSACTION;'];
        foreach ($recipes as $recipe) {
            $author=$recipe['author']??null;
            if(is_array($author)) {
                $authors=isset($author['name'])?[$author]:$author;
                $author=implode(', ',array_filter(array_map(static fn($a)=>is_string($a)?$a:(is_array($a)?($a['name']??''):''),$authors)));
            }
            if (empty($recipe['title']) || empty($recipe['ingredients_original']) || empty($recipe['instructions_original']) || !filter_var($recipe['source_url']??'',FILTER_VALIDATE_URL)) throw new RuntimeException('Incomplete recipe');
            $key=self::literal(hash('sha256',$recipe['source_url']));
            $out[]="SET @recipe_import_new=(@recipe_import_allowed=1 AND NOT EXISTS(SELECT 1 FROM recipes WHERE household_id=$household AND (import_key=$key OR source_url=".self::literal($recipe['source_url']).")));";
            $out[]=self::insert('recipes',[
                'household_id'=>$household,'title'=>$recipe['title'],'original_language'=>'en','measurement_system'=>'unspecified',
                'source_type'=>'bookmark_'.($recipe['extraction_type']??'jsonld'),'source_url'=>$recipe['source_url'],'source_title'=>$recipe['title'],'source_author'=>$author,
                'source_reference'=>$recipe['bookmark_url']??$recipe['source_url'],'source_text'=>json_encode($recipe,JSON_UNESCAPED_UNICODE|JSON_THROW_ON_ERROR),
                'import_key'=>hash('sha256',$recipe['source_url']),'yield_text'=>RecipeImportTools::yieldValue($recipe['yield']??null,$recipe['instructions_original'],$recipe['source_url']),
                'prep_minutes'=>self::minutes($recipe['prep_time']??null),'cook_minutes'=>self::minutes($recipe['cook_time']??null),'total_minutes'=>self::minutes($recipe['total_time']??null),
                'notes'=>$recipe['notes']??null,'created_by_user_id'=>$user,'updated_by_user_id'=>$user
            ]);
            $out[]="SET @recipe_import_id=(SELECT id FROM recipes WHERE household_id=$household AND import_key=$key);";
            foreach ($recipe['ingredients_original'] as $i=>$line) $out[]=self::insert('recipe_ingredients',['household_id'=>$household,'recipe_id'=>0,'position'=>$i+1]+self::ingredient($line));
            foreach ($recipe['instructions_original'] as $i=>$line) $out[]=self::insert('recipe_steps',['household_id'=>$household,'recipe_id'=>0,'position'=>$i+1,'instruction'=>trim($line)]);
            foreach (['category','cuisine'] as $kind) foreach (array_unique((array)($recipe[$kind]??[])) as $label) {
                if (!is_string($label) || !trim($label) || mb_strlen($label)>120) continue;
                if ($kind==='category' && RecipeImportTools::excludedCategory($recipe['source_url'],$label)) continue;
                $out[]=self::insert('recipe_tags',['household_id'=>$household,'recipe_id'=>0,'kind'=>$kind,'label'=>$label]);
            }
            $archived=$recipe['verified_photos']??[];
            foreach($archived as $asset) {
                $key=$asset['storage_key']??'';
                if(!preg_match('~^media/recipe-photos/[a-f0-9]{64}\.(jpg|png|webp|gif)$~D',$key) || $asset['source_url']!=='https://coffeybean.com/CoffeyTableRecipes/'.$key) throw new RuntimeException('Photo must be downloaded and archived before hosted import');
            }
            foreach (RecipeImportTools::pendingPhotos([], $archived, $author?:parse_url($recipe['source_url'],PHP_URL_HOST)) as $photo) {
                foreach($archived as $asset) if($asset['source_url']===$photo['source_url']) $photo['storage_key']=$asset['storage_key'];
                $out[]=self::insert('recipe_photos',['household_id'=>$household,'recipe_id'=>0]+$photo);
            }
        }
        $out[]='COMMIT;';
        $out[]="SELECT @recipe_import_allowed AS authorized_destination;";
        $keys=implode(',',array_map(fn($r)=>self::literal(hash('sha256',$r['source_url'])),$recipes));
        $out[]="SELECT r.id,r.title,(SELECT COUNT(*) FROM recipe_ingredients i WHERE i.recipe_id=r.id) AS ingredients,(SELECT COUNT(*) FROM recipe_steps s WHERE s.recipe_id=r.id) AS steps,(SELECT COUNT(*) FROM recipe_photos p WHERE p.recipe_id=r.id) AS photos FROM recipes r WHERE r.household_id=$household AND r.import_key IN ($keys) ORDER BY r.id;";
        return implode("\n",$out)."\n";
    }
}
