<?php
declare(strict_types=1);
require 'C:/xampp/htdocs/CoffeyTableRecipes/src/bootstrap.php';
require __DIR__.'/PhotoArchive.php';
$checks=0;
function archiveCheck(bool $ok,string $message):void {global $checks;if(!$ok)throw new RuntimeException($message);$checks++;}
foreach(['http://127.0.0.1/test.jpg','http://[::1]/test.jpg','http://192.168.1.1/test.jpg'] as $url) {
    try {PhotoArchive::download($url,__DIR__.'/generated');throw new RuntimeException('Private address accepted');}
    catch(RuntimeException $e){archiveCheck(str_contains($e->getMessage(),'Non-public'),'Private destinations rejected before request');}
}
$config=configuration();
if($config['environment']!=='development')throw new RuntimeException('Disposable local test only');
$db=$config['database'];
$admin=new PDO(sprintf('mysql:host=%s;port=%d;charset=utf8mb4',$db['host'],$db['port']),$db['user'],$db['password'],[PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION]);
$name='coffey_photo_archive_test_'.bin2hex(random_bytes(5));
$admin->exec("CREATE DATABASE `$name` CHARACTER SET utf8mb4");
try {
    $config['database']['name']=$name;$pdo=database($config);
    foreach(glob('C:/xampp/htdocs/CoffeyTableRecipes/database/migrations/*.sql') as $file)foreach(explode(';',file_get_contents($file)) as $sql)if(trim($sql)!=='')$pdo->exec($sql);
    $pdo->exec("INSERT INTO households(id,name) VALUES(2,'Fixture');INSERT INTO users(id,firebase_uid) VALUES(6,'fixture');INSERT INTO household_memberships(household_id,user_id,role) VALUES(2,6,'owner');");
    $root=__DIR__.'/generated/photo-test-'.bin2hex(random_bytes(4));
    mkdir($root,0700,true);
    $key='media/recipe-photos/'.str_repeat('a',64).'.jpg';
    $host='https://coffeybean.com/CoffeyTableRecipes/';
    $before=[];
    for($i=1;$i<=3;$i++) $before[]=['id'=>$i,'household_id'=>2,'recipe_id'=>9,'position'=>$i,'source_url'=>$i===3?$host.'media/recipe-illustrations/example.jpg':'https://example.com/photo'.$i.'.jpg','storage_key'=>$i===3?'media/recipe-illustrations/example.jpg':null,'mime_type'=>'image/jpeg','width_pixels'=>100,'height_pixels'=>100,'caption'=>"Chef's photo",'attribution'=>'Fixture','is_cover'=>$i===1?1:0,'title'=>'Fixture','revision'=>1];
    $assets=[['original_urls'=>['https://example.com/photo1.jpg','https://example.com/photo2.jpg'],'hosted_url'=>$host.$key,'storage_key'=>$key,'mime_type'=>'image/jpeg','width_pixels'=>800,'height_pixels'=>600]];
    file_put_contents($root.'/hosted-before.json',json_encode($before));file_put_contents($root.'/manifest.json',json_encode($assets));
    $command=escapeshellarg(PHP_BINARY).' '.escapeshellarg(__DIR__.'/migrate-photo-archive.php').' '.escapeshellarg($root.'/hosted-before.json').' '.escapeshellarg($root.'/manifest.json').' '.escapeshellarg($root);
    exec($command,$output,$status);archiveCheck($status===0,'Migration planner executes');
    $ids=[];
    foreach($before as $p){
        if(!isset($ids[$p['recipe_id']])){$pdo->prepare('INSERT INTO recipes(id,household_id,title,created_by_user_id,updated_by_user_id) VALUES(?,2,?,6,6)')->execute([$p['recipe_id'],$p['title']]);$ids[$p['recipe_id']]=1;}
        unset($p['title'],$p['revision']);
        $cols=array_keys($p);$pdo->prepare('INSERT INTO recipe_photos (`'.implode('`,`',$cols).'`) VALUES('.implode(',',array_fill(0,count($cols),'?')).')')->execute(array_values($p));
    }
    $original=$pdo->query('SELECT * FROM recipe_photos ORDER BY id')->fetchAll(PDO::FETCH_ASSOC);
    $run=function(string $file)use($pdo){foreach(explode(';',file_get_contents($file)) as $sql)if(trim($sql)!==''){$q=$pdo->query($sql);$q->closeCursor();}};
    $pdo->exec("UPDATE household_memberships SET role='viewer'");$run($root.'/migrate.sql');
    archiveCheck($original===$pdo->query('SELECT * FROM recipe_photos ORDER BY id')->fetchAll(PDO::FETCH_ASSOC),'Unauthorized migration changes nothing');
    $pdo->exec("UPDATE household_memberships SET role='owner'");
    $pdo->exec("UPDATE recipe_photos SET caption='Concurrent edit' WHERE id=1");$run($root.'/migrate.sql');
    archiveCheck(!str_contains($pdo->query('SELECT source_url FROM recipe_photos WHERE id=1')->fetchColumn(),'coffeybean.com'),'Concurrent edits are preserved');
    $pdo->prepare('UPDATE recipe_photos SET caption=? WHERE id=1')->execute([$before[0]['caption']]);$run($root.'/migrate.sql');
    $after=$pdo->query('SELECT * FROM recipe_photos ORDER BY id')->fetchAll(PDO::FETCH_ASSOC);
    archiveCheck(count($after)===3 && (int)$pdo->query("SELECT COUNT(*) FROM recipe_photos WHERE source_url NOT LIKE 'https://coffeybean.com/CoffeyTableRecipes/%'")->fetchColumn()===0,'Every record uses own server');
    foreach($after as $i=>$p)foreach(['id','recipe_id','position','caption','attribution','is_cover'] as $key)archiveCheck($p[$key]===$original[$i][$key],'Photo identity and metadata preserved');
    $run($root.'/migrate.sql');archiveCheck($after===$pdo->query('SELECT * FROM recipe_photos ORDER BY id')->fetchAll(PDO::FETCH_ASSOC),'Rerun is idempotent');
    $run($root.'/rollback.sql');archiveCheck($original===$pdo->query('SELECT * FROM recipe_photos ORDER BY id')->fetchAll(PDO::FETCH_ASSOC),'Rollback restores photo records');
} finally {if(isset($root)) {foreach(['hosted-before.json','manifest.json','migrate.sql','rollback.sql'] as $file) if(is_file($root.'/'.$file))unlink($root.'/'.$file);rmdir($root);} $admin->exec("DROP DATABASE `$name`");}
echo "$checks photo archive checks passed.\n";
