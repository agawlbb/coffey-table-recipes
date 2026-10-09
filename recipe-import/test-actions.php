<?php
declare(strict_types=1);
require 'C:/xampp/htdocs/CoffeyTableRecipes/src/bootstrap.php';
require __DIR__.'/HostedActions.php';
$config=configuration();
if($config['environment']!=='development')throw new RuntimeException('Disposable development database only');
$db=$config['database'];
$admin=new PDO(sprintf('mysql:host=%s;port=%d;charset=utf8mb4',$db['host'],$db['port']),$db['user'],$db['password'],[PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION]);
$name='coffey_actions_test_'.bin2hex(random_bytes(5));
$admin->exec("CREATE DATABASE `$name` CHARACTER SET utf8mb4");
$checks=0;$check=function($ok,$label)use(&$checks){if(!$ok)throw new RuntimeException($label);$checks++;};
$timer=['action_type'=>'timer','label'=>'Check after 15 minutes; range 15–20 minutes.','duration_seconds'=>900];
$temperature=['action_type'=>'appliance_temperature','label'=>'Oven target','temperature_value'=>350,'temperature_unit'=>'F','appliance'=>'oven'];
$fixture=['id'=>15,'revision'=>3,'steps'=>['Fill cups.','Bake at 350°F for 15–20 minutes.'],'actions'=>[2=>[$temperature,$timer]]];
$recipes=isset($argv[1])?json_decode(file_get_contents($argv[1]),true,512,JSON_THROW_ON_ERROR):[$fixture];
try{
    $config['database']['name']=$name;$pdo=database($config);
    foreach(glob('C:/xampp/htdocs/CoffeyTableRecipes/database/migrations/*.sql') as $file)foreach(explode(';',file_get_contents($file)) as $q)if(trim($q)!=='')$pdo->exec($q);
    $pdo->exec("INSERT INTO households(id,name) VALUES(2,'Fixture'); INSERT INTO users(id,firebase_uid) VALUES(6,'fixture'); INSERT INTO household_memberships(household_id,user_id,role) VALUES(2,6,'owner')");
    $seed=function($recipe)use($pdo){
        $id=(int)$recipe['id'];$revision=(int)$recipe['revision'];
        $pdo->exec("INSERT INTO recipes(id,household_id,title,revision,source_text,yield_text) VALUES($id,2,'Fixture',$revision,'Preserved original','Original yield')");
        foreach($recipe['steps'] as $index=>$text)$pdo->exec('INSERT INTO recipe_steps(household_id,recipe_id,position,instruction) VALUES(2,'.$id.','.($index+1).','.HostedImport::literal($text).')');
        $pdo->exec("INSERT INTO recipe_photos(household_id,recipe_id,position,source_url,is_cover) VALUES(2,$id,1,'https://example.com/cover.jpg',1)");
    };
    $run=function($sql)use($pdo){foreach(explode(';',$sql) as $q)if(trim($q)!==''){$stmt=$pdo->query($q);$stmt->closeCursor();}};
    foreach($recipes as $recipe)$seed($recipe);
    $sql=HostedActions::sql($recipes);$run($sql);$expected=0;
    foreach($recipes as $recipe){
        $id=(int)$recipe['id'];
        foreach($recipe['actions'] as $position=>$actions){
            $stored=$pdo->query("SELECT a.*,s.position AS step_position FROM recipe_step_actions a JOIN recipe_steps s ON s.id=a.step_id WHERE a.recipe_id=$id AND s.position=".(int)$position.' ORDER BY a.position')->fetchAll(PDO::FETCH_ASSOC);
            $check(count($stored)===count($actions),'Action count matches each reviewed step');
            foreach($actions as $index=>$action){$expected++;$row=$stored[$index];
                foreach(['action_type','label','duration_seconds','temperature_value','temperature_unit','appliance'] as $field)$check(($row[$field]===null && !isset($action[$field])) || (isset($action[$field]) && (string)$row[$field]===(string)$action[$field]) || ($field==='temperature_value' && isset($action[$field]) && (float)$row[$field]===(float)$action[$field]),'Exact action field '.$field);
            }
        }
        $check((int)$pdo->query("SELECT revision FROM recipes WHERE id=$id")->fetchColumn()===$recipe['revision']+1,'Revision incremented');
    }
    $check((int)$pdo->query("SELECT COUNT(*) FROM recipes WHERE source_text='Preserved original' AND yield_text='Original yield'")->fetchColumn()===count($recipes),'Source and yield untouched');
    $check((int)$pdo->query('SELECT SUM(is_cover) FROM recipe_photos')->fetchColumn()===count($recipes),'Cover photos untouched');
    $run($sql);$check((int)$pdo->query('SELECT COUNT(*) FROM recipe_step_actions')->fetchColumn()===$expected,'Rerun does not duplicate');
    $conflict=$fixture;$conflict['id']=99;$seed($conflict);
    $pdo->exec("UPDATE recipe_steps SET instruction='User edit' WHERE recipe_id=99 AND position=1");
    $run(HostedActions::sql([$conflict]));
    $check((int)$pdo->query('SELECT COUNT(*) FROM recipe_step_actions WHERE recipe_id=99')->fetchColumn()===0,'Edited recipe skipped');
    $protected=$fixture;$protected['id']=98;$seed($protected);
    $pdo->exec("INSERT INTO recipe_step_actions(household_id,recipe_id,step_id,position,action_type,duration_seconds,label) SELECT 2,98,id,1,'timer',60,'User timer' FROM recipe_steps WHERE recipe_id=98 AND position=1");
    $run(HostedActions::sql([$protected]));
    $check((int)$pdo->query('SELECT COUNT(*) FROM recipe_step_actions WHERE recipe_id=98')->fetchColumn()===1,'Existing user actions preserved');
    $unauthorized=$fixture;$unauthorized['id']=97;$seed($unauthorized);$pdo->exec('UPDATE users SET disabled=1 WHERE id=6');
    $run(HostedActions::sql([$unauthorized]));
    $check((int)$pdo->query('SELECT COUNT(*) FROM recipe_step_actions WHERE recipe_id=97')->fetchColumn()===0,'Disabled user denied');
    foreach([
        ['action_type'=>'timer','duration_seconds'=>0],
        ['action_type'=>'appliance_temperature','temperature_value'=>350,'temperature_unit'=>'unknown'],
    ] as $invalid){$bad=$fixture;$bad['actions']=[2=>[$invalid]];$thrown=false;try{HostedActions::sql([$bad]);}catch(InvalidArgumentException $e){$thrown=true;}$check($thrown,'Malformed action rejected');}
}finally{$admin->exec("DROP DATABASE `$name`");}
echo "$checks cooking action checks passed.\n";
