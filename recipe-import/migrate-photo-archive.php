<?php
declare(strict_types=1);
require_once __DIR__.'/HostedImport.php';
if (PHP_SAPI !== 'cli' || $argc !== 4) throw new RuntimeException('Usage: php migrate-photo-archive.php hosted-before.json manifest.json output-directory');
$before=json_decode(file_get_contents($argv[1]),true,100,JSON_THROW_ON_ERROR);
$manifest=json_decode(file_get_contents($argv[2]),true,100,JSON_THROW_ON_ERROR);
$map=[];
foreach($manifest as $asset) foreach($asset['original_urls'] as $url) $map[$url]=$asset;
$head=["SET NAMES utf8mb4;","SET @photo_allowed=(SELECT COUNT(*) FROM household_memberships m JOIN users u ON u.id=m.user_id WHERE m.household_id=2 AND m.user_id=6 AND m.role IN ('owner','admin') AND u.disabled=0);",'START TRANSACTION;'];
$forward=$rollback=$head; $count=0;
foreach($before as $p) {
    if(str_starts_with($p['source_url'],'https://coffeybean.com/CoffeyTableRecipes/')) continue;
    $a=$map[$p['source_url']]??throw new RuntimeException('Missing archived photo '.$p['id']);
    if((int)$p['household_id']!==2) throw new RuntimeException('Unexpected household');
    $new=['source_url'=>$a['hosted_url'],'storage_key'=>$a['storage_key'],'mime_type'=>$a['mime_type'],'width_pixels'=>$a['width_pixels'],'height_pixels'=>$a['height_pixels']];
    foreach([false,true] as $undo) {
        $values=$undo?array_intersect_key($p,$new):$new;
        $expected=$undo?$new:array_intersect_key($p,$new);
        $guard=['@photo_allowed=1','household_id=2','id='.(int)$p['id'],'recipe_id='.(int)$p['recipe_id']];
        foreach($expected+array_intersect_key($p,array_flip(['position','caption','attribution','is_cover'])) as $k=>$v) $guard[]=is_string($v)?"BINARY `$k` <=> BINARY ".HostedImport::literal($v):"`$k` <=> ".HostedImport::literal($v);
        $set=[]; foreach($values as $k=>$v) $set[]="`$k`=".HostedImport::literal($v);
        $sql='UPDATE recipe_photos SET '.implode(',',$set).' WHERE '.implode(' AND ',$guard).';';
        if($undo) $rollback[]=$sql; else $forward[]=$sql;
    }
    $count++;
}
foreach(['migrate.sql'=>&$forward,'rollback.sql'=>&$rollback] as $name=>&$lines) {
    $lines[]='COMMIT;';
    $lines[]="SELECT @photo_allowed AS authorized_destination,COUNT(*) AS photos,SUM(source_url NOT LIKE 'https://coffeybean.com/CoffeyTableRecipes/%') AS external_photos FROM recipe_photos WHERE household_id=2;";
    file_put_contents($argv[3].'/'.$name,implode("\n",$lines)."\n");
}
echo "Prepared $count guarded photo updates and rollback; no database changes made.\n";
