<?php
declare(strict_types=1);
require 'C:/xampp/htdocs/CoffeyTableRecipes/src/bootstrap.php';
require __DIR__.'/HostedCleanup.php';
$config=configuration();
if($config['environment']!=='development')throw new RuntimeException('Disposable development database only');
$db=$config['database'];
$admin=new PDO(sprintf('mysql:host=%s;port=%d;charset=utf8mb4',$db['host'],$db['port']),$db['user'],$db['password'],[PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION]);
$name='coffey_cleanup_test_'.bin2hex(random_bytes(5));
$admin->exec("CREATE DATABASE `$name` CHARACTER SET utf8mb4");
$checks=0;
$check=function(bool $ok,string $label)use(&$checks){if(!$ok)throw new RuntimeException($label);$checks++;};
try{
    $config['database']['name']=$name;$pdo=database($config);
    foreach(glob('C:/xampp/htdocs/CoffeyTableRecipes/database/migrations/*.sql') as $file)foreach(explode(';',file_get_contents($file)) as $q)if(trim($q)!=='')$pdo->exec($q);
    $pdo->exec("INSERT INTO households(id,name) VALUES(2,'Fixture'); INSERT INTO users(id,firebase_uid) VALUES(6,'fixture'); INSERT INTO household_memberships(household_id,user_id,role) VALUES(2,6,'owner')");
    // Optional private snapshots exercise the complete live batch; default fixtures are portable.
    $before=isset($argv[1])?json_decode(file_get_contents($argv[1]),true,512,JSON_THROW_ON_ERROR):[
        ['15','Fixture muffins','15 muffins','2','100','1','Mix dry ingredients.'],
        ['15','Fixture muffins','15 muffins','2','101','2','Fill cups; bake. Yield: 15 muffins.'],
        ['20','Fixture crab','4 servings','1','116','1','Cook; transfer; bake.'],
    ];
    $parts=isset($argv[2])?json_decode(file_get_contents($argv[2]),true,512,JSON_THROW_ON_ERROR):[
        100=>['Mix dry ingredients.'],101=>['Fill cups.','Bake.'],116=>['Cook.','Transfer.','Bake.'],
    ];
    $expectedSteps=0;foreach($before as $r)$expectedSteps+=count($parts[(int)$r[4]]);
    $ids=[];
    foreach($before as $r){$id=(int)$r[0];$ids[$id]=true;
        $pdo->exec('INSERT IGNORE INTO recipes(id,household_id,title,revision,source_text,yield_text) VALUES('.$id.',2,'.HostedImport::literal($r[1]).','.(int)$r[3].",'Original source',".HostedImport::literal($r[2]==='NULL'?null:$r[2]).')');
        $pdo->exec('INSERT INTO recipe_steps(id,household_id,recipe_id,position,instruction) VALUES('.(int)$r[4].',2,'.$id.','.(int)$r[5].','.HostedImport::literal($r[6]).')');
    }
    $run=function($sql)use($pdo){foreach(explode(';',$sql) as $q)if(trim($q)!==''){$stmt=$pdo->query($q);$stmt->closeCursor();}};
    $sql=HostedCleanup::sql($before,$parts,[20=>['source_url'=>'https://example.com/crab.jpg','width_pixels'=>1254,'height_pixels'=>1254]]);
    $run($sql);
    $check((int)$pdo->query('SELECT COUNT(*) FROM recipe_steps')->fetchColumn()===$expectedSteps,'All curated steps apply');
    foreach($before as $r)$check($pdo->query('SELECT instruction FROM recipe_steps WHERE id='.(int)$r[4])->fetchColumn()===$parts[(int)$r[4]][0],'Existing IDs preserved');
    $check((int)$pdo->query("SELECT COUNT(*) FROM recipes WHERE source_text='Original source'")->fetchColumn()===count($ids),'Raw source preserved');
    $check((int)$pdo->query('SELECT COUNT(*) FROM recipe_steps WHERE position>=10000')->fetchColumn()===0,'Positions restored');
    $check((int)$pdo->query('SELECT SUM(is_cover) FROM recipe_photos')->fetchColumn()===1,'Illustrative cover added');
    $run($sql);
    $check((int)$pdo->query('SELECT COUNT(*) FROM recipe_steps')->fetchColumn()===$expectedSteps && (int)$pdo->query('SELECT COUNT(*) FROM recipe_photos')->fetchColumn()===1,'Rerun is idempotent');
    // A fresh recipe with a conflicting user edit must skip the entire recipe.
    $pdo->exec("INSERT INTO recipes(id,household_id,title,revision) VALUES(99,2,'Conflict',1); INSERT INTO recipe_steps(id,household_id,recipe_id,position,instruction) VALUES(999,2,99,1,'User edit')");
    $run(HostedCleanup::sql([['99','Conflict','NULL','1','999','1','Original']],[999=>['Split','Next']]));
    $check($pdo->query('SELECT instruction FROM recipe_steps WHERE id=999')->fetchColumn()==='User edit','Conflicting user edit preserved');
    $pdo->exec("INSERT INTO recipe_step_actions(household_id,recipe_id,step_id,position,action_type,duration_seconds) VALUES(2,99,999,1,'timer',60)");
    $run(HostedCleanup::sql([['99','Conflict','NULL','1','999','1','User edit']],[999=>['Split','Next']]));
    $check($pdo->query('SELECT instruction FROM recipe_steps WHERE id=999')->fetchColumn()==='User edit' && (int)$pdo->query('SELECT COUNT(*) FROM recipe_step_actions')->fetchColumn()===1,'Recipes with attached actions are preserved for manual mapping');
    $pdo->exec('UPDATE users SET disabled=1 WHERE id=6');
    $run(HostedCleanup::sql([['99','Conflict','NULL','1','999','1','User edit']],[999=>['Unauthorized']]));
    $check($pdo->query('SELECT instruction FROM recipe_steps WHERE id=999')->fetchColumn()==='User edit','Disabled user cannot modify recipe');
}finally{$admin->exec("DROP DATABASE `$name`");}
echo "$checks cleanup checks passed.\n";
