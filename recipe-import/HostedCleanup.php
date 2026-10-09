<?php
declare(strict_types=1);
require_once __DIR__.'/HostedImport.php';

/** Optimistic, data-only cleanup: retains existing IDs and untouched raw source. */
final class HostedCleanup
{
    public static function sql(array $before, array $parts, array $photos = []): string
    {
        $lit=[HostedImport::class,'literal'];
        $groups=[];
        foreach($before as $row)$groups[(int)$row[0]][]=$row;
        $sql=["SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci",'START TRANSACTION',"SET @member = EXISTS(SELECT 1 FROM household_memberships m JOIN users u ON u.id=m.user_id WHERE m.household_id=2 AND m.user_id=6 AND u.disabled=0 AND m.role IN ('owner','admin'))"];
        foreach($groups as $id=>$rows){
            $checks=[];$position=0;
            foreach($rows as $row){
                $step=(int)$row[4];
                if(!isset($parts[$step]) || !$parts[$step])throw new RuntimeException("Missing step $step");
                $checks[]='EXISTS(SELECT 1 FROM recipe_steps WHERE id='.$step.' AND recipe_id='.$id.' AND position='.(int)$row[5].' AND BINARY instruction=BINARY '.$lit($row[6]).')';
                foreach($parts[$step] as $text)if(trim($text)==='')throw new RuntimeException('Empty instruction');
            }
            $sql[]="SET @edit = @member AND EXISTS(SELECT 1 FROM recipes WHERE id=$id AND household_id=2 AND revision=".(int)$rows[0][3].") AND (SELECT COUNT(*) FROM recipe_steps WHERE recipe_id=$id)=".count($rows)." AND NOT EXISTS(SELECT 1 FROM recipe_step_actions WHERE recipe_id=$id) AND ".implode(' AND ',$checks);
            // Park positions to avoid collisions while preserving all existing step IDs.
            $sql[]="UPDATE recipe_steps SET position=position+10000 WHERE recipe_id=$id AND @edit";
            foreach($rows as $row){
                $step=(int)$row[4];
                foreach($parts[$step] as $index=>$text){
                    $position++;
                    $value=$lit($text);
                    if($index===0)$sql[]="UPDATE recipe_steps SET position=$position,instruction=$value WHERE id=$step AND recipe_id=$id AND @edit";
                    else $sql[]="INSERT INTO recipe_steps(household_id,recipe_id,position,instruction) SELECT 2,$id,$position,$value WHERE @edit";
                }
            }
            $sql[]="UPDATE recipes SET revision=revision+1,updated_by_user_id=6 WHERE id=$id AND @edit";
            $sql[]="SELECT $id AS recipe_id,@edit AS cleanup_applied,$position AS planned_steps";
        }
        foreach($photos as $id=>$photo){
            $url=$lit($photo['source_url']);
            $sql[]="SET @photo = @member AND EXISTS(SELECT 1 FROM recipes WHERE id=".(int)$id." AND household_id=2) AND NOT EXISTS(SELECT 1 FROM recipe_photos WHERE recipe_id=".(int)$id." AND BINARY source_url=BINARY $url)";
            $sql[]="SET @position = (SELECT COALESCE(MAX(position),0)+1 FROM recipe_photos WHERE recipe_id=".(int)$id.")";
            $sql[]="UPDATE recipe_photos SET is_cover=0 WHERE recipe_id=".(int)$id." AND @photo";
            $sql[]='INSERT INTO recipe_photos(household_id,recipe_id,position,source_url,mime_type,width_pixels,height_pixels,caption,attribution,is_cover) SELECT 2,'.(int)$id.',@position,'.$url.','.$lit('image/jpeg').','.(int)$photo['width_pixels'].','.(int)$photo['height_pixels'].','.$lit('AI-generated illustrative image; appearance may differ from the finished recipe.').','.$lit('AI-generated with OpenAI').',1 WHERE @photo';
            $sql[]="UPDATE recipes SET revision=revision+1,updated_by_user_id=6 WHERE id=".(int)$id." AND @photo";
        }
        $sql[]='COMMIT';
        return implode(";\n",$sql).";\n";
    }
}
