<?php
declare(strict_types=1);
require_once __DIR__.'/PhotoArchive.php';
if ($argc!==3) throw new RuntimeException('Usage: archive-photos.php candidates.json output-directory');
$candidates=json_decode(file_get_contents($argv[1]),true,512,JSON_THROW_ON_ERROR);
$root=$argv[2];
$media=$root.'/media/recipe-photos';
if (!is_dir($media) && !mkdir($media,0775,true)) throw new RuntimeException('Could not create archive directory');
$manifest=[];$failures=[];
foreach ($candidates as $alternatives) {
    $saved=null;$errors=[];
    foreach ($alternatives as $url) {
        try { $saved=PhotoArchive::download($url,$media); break; }
        catch (Throwable $e) { $errors[]=['url'=>$url,'error'=>$e->getMessage()]; }
    }
    if ($saved) {
        $saved['original_urls']=$alternatives;
        $saved['storage_key']='media/recipe-photos/'.$saved['filename'];
        $saved['hosted_url']='https://coffeybean.com/CoffeyTableRecipes/'.$saved['storage_key'];
        $manifest[]=$saved;
        echo 'Saved '.$saved['filename'].' ('.$saved['bytes'].' bytes)'.PHP_EOL;
    } else $failures[]=$errors;
}
file_put_contents($root.'/manifest.json',json_encode($manifest,JSON_PRETTY_PRINT|JSON_UNESCAPED_SLASHES));
file_put_contents($root.'/failures.json',json_encode($failures,JSON_PRETTY_PRINT|JSON_UNESCAPED_SLASHES));
echo count($manifest).' image groups downloaded; '.count($failures).' failed.'.PHP_EOL;
