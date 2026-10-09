<?php
declare(strict_types=1);
if (PHP_SAPI!=='cli') exit;
require_once 'C:/xampp/htdocs/CoffeyTableRecipes/src/RecipeImportTools.php';
require_once __DIR__.'/HostedImport.php';
$options=getopt('', ['input:','output:','household:','user:','photo-archive-manifest:']);
foreach (['input','output','household','user'] as $required) if (!isset($options[$required])) throw new RuntimeException("Missing --$required");
$recipes=json_decode(ltrim(file_get_contents($options['input']),"\xEF\xBB\xBF"),true,100,JSON_THROW_ON_ERROR);
$bookmarks=json_decode(ltrim(file_get_contents(__DIR__.'/bookmarks.json'),"\xEF\xBB\xBF"),true,100,JSON_THROW_ON_ERROR);
if(!isset($options['photo-archive-manifest'])) throw new RuntimeException('Download photos first; --photo-archive-manifest is required');
$archive=[];
foreach(json_decode(file_get_contents($options['photo-archive-manifest']),true,100,JSON_THROW_ON_ERROR) as $asset) {
    if(!preg_match('~^media/recipe-photos/[a-f0-9]{64}\.(jpg|png|webp|gif)$~D',$asset['storage_key']??'')) throw new RuntimeException('Invalid archive key');
    $path=dirname($options['photo-archive-manifest']).'/'.$asset['storage_key'];
    if(!is_file($path) || filesize($path)>8*1024*1024 || hash_file('sha256',$path)!==$asset['sha256'] || pathinfo($path,PATHINFO_FILENAME)!==$asset['sha256']) throw new RuntimeException('Archived image bytes missing or changed');
    $info=getimagesize($path);
    if(!$info || $info['mime']!==$asset['mime_type'] || $info[0]!==$asset['width_pixels'] || $info[1]!==$asset['height_pixels']) throw new RuntimeException('Archived image metadata does not match bytes');
    foreach($asset['original_urls'] as $url) $archive[$url]=$asset;
}
foreach ($recipes as &$recipe) {
    $recipe['collected_at_utc']??=gmdate('c');
    foreach ($bookmarks as $bookmark) if (str_contains(strtolower($bookmark['title']),strtolower(explode(':',$recipe['title'])[0])) || (str_contains($recipe['source_url'],'apracticalwedding') && str_contains($bookmark['bookmark_url'],'apracticalwedding'))) $recipe['bookmark_url']=$bookmark['bookmark_url'];
    $recipe['verified_photos']=[];
    $recipe['photo_failures']=[];
    foreach (RecipeImportTools::images($recipe['image_source']??[], $recipe['source_url']) as $image) {
        try {
            $asset=$archive[$image['source_url']]??throw new RuntimeException('No downloaded archive for source image');
            $asset['publisher_url']=$image['source_url'];
            $asset['source_url']=$asset['hosted_url'];
            $recipe['verified_photos'][]=$asset+['caption'=>$image['caption']];
        }
        catch (Throwable $error) {$recipe['photo_failures'][]=['url'=>$image['source_url'],'error'=>$error->getMessage()];}
    }
    echo json_encode(['title'=>$recipe['title'],'photos'=>count($recipe['verified_photos']),'photo_failures'=>$recipe['photo_failures']],JSON_UNESCAPED_SLASHES)."\n";
}
unset($recipe);
$output=$options['output'];
if (!is_dir(dirname($output))) mkdir(dirname($output),0700,true);
file_put_contents($output,HostedImport::sql($recipes,(int)$options['household'],(int)$options['user']));
file_put_contents(dirname($output).'/verified-recipes.json',json_encode($recipes,JSON_PRETTY_PRINT|JSON_UNESCAPED_UNICODE|JSON_THROW_ON_ERROR));
echo 'Exported '.count($recipes)." recipes; database has not been changed.\n";
