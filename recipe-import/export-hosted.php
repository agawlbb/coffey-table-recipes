<?php
declare(strict_types=1);
if (PHP_SAPI!=='cli') exit;
require_once 'C:/xampp/htdocs/CoffeyTableRecipes/src/RecipeImportTools.php';
require_once __DIR__.'/HostedImport.php';
$options=getopt('', ['input:','output:','household:','user:','browser-image-manifest:']);
foreach (['input','output','household','user'] as $required) if (!isset($options[$required])) throw new RuntimeException("Missing --$required");
$recipes=json_decode(ltrim(file_get_contents($options['input']),"\xEF\xBB\xBF"),true,100,JSON_THROW_ON_ERROR);
$bookmarks=json_decode(ltrim(file_get_contents(__DIR__.'/bookmarks.json'),"\xEF\xBB\xBF"),true,100,JSON_THROW_ON_ERROR);
$browserPhotos=[];
if (isset($options['browser-image-manifest'])) {
    $manifest=$options['browser-image-manifest'];
    $assetDirectory=realpath(dirname($manifest));
    $assets=json_decode(file_get_contents($manifest),true,100,JSON_THROW_ON_ERROR);
    foreach ($assets['assets']??[] as $asset) {
        if (($asset['kind']??'')!=='image') continue;
        $path=realpath($asset['path']);
        if (!$path || !str_starts_with(strtolower($path),strtolower($assetDirectory.DIRECTORY_SEPARATOR)) || filesize($path)>8*1024*1024) throw new RuntimeException('Invalid browser image artifact');
        $dimensions=getimagesize($path);
        if (!$dimensions || !in_array($dimensions['mime'],['image/jpeg','image/png','image/webp','image/gif'],true) || $dimensions['mime']!==$asset['contentType']) throw new RuntimeException('Invalid browser image bytes');
        $browserPhotos[$asset['url']]=['source_url'=>$asset['url'],'mime_type'=>$dimensions['mime'],'width_pixels'=>$dimensions[0],'height_pixels'=>$dimensions[1],'verified_at_utc'=>gmdate('c'),'verification_method'=>'rendered_source_asset_bytes'];
    }
}
foreach ($recipes as &$recipe) {
    $recipe['collected_at_utc']??=gmdate('c');
    foreach ($bookmarks as $bookmark) if (str_contains(strtolower($bookmark['title']),strtolower(explode(':',$recipe['title'])[0])) || (str_contains($recipe['source_url'],'apracticalwedding') && str_contains($bookmark['bookmark_url'],'apracticalwedding'))) $recipe['bookmark_url']=$bookmark['bookmark_url'];
    $recipe['verified_photos']=[];
    $recipe['photo_failures']=[];
    foreach (RecipeImportTools::images($recipe['image_source']??[], $recipe['source_url']) as $image) {
        try {$recipe['verified_photos'][]=($browserPhotos[$image['source_url']]??RecipeImportTools::verifyImage($image['source_url']))+['caption'=>$image['caption']];}
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
