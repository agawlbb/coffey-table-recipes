<?php
declare(strict_types=1);
require_once __DIR__.'/HostedImport.php';

/** Add reviewed cooking actions without changing steps or existing actions. */
final class HostedActions
{
    public static function sql(array $recipes, int $household=2, int $user=6): string
    {
        if($household<1 || $user<1)throw new InvalidArgumentException('Invalid destination');
        $lit=[HostedImport::class,'literal'];
        $sql=['SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci','SET SESSION group_concat_max_len=1048576','START TRANSACTION',"SET @allowed=EXISTS(SELECT 1 FROM household_memberships m JOIN users u ON u.id=m.user_id WHERE m.household_id=$household AND m.user_id=$user AND m.role IN ('owner','admin') AND u.disabled=0)"];
        foreach($recipes as $recipe){
            $id=(int)$recipe['id'];$revision=(int)$recipe['revision'];$steps=$recipe['steps'];
            if($id<1 || $revision<1 || !$steps)throw new InvalidArgumentException('Invalid recipe snapshot');
            $digest=$lit(hash('sha256',implode(chr(31),$steps)));
            $sql[]="SELECT id FROM recipes WHERE id=$id AND household_id=$household FOR UPDATE";
            $sql[]="SET @apply=@allowed AND EXISTS(SELECT 1 FROM recipes WHERE id=$id AND household_id=$household AND revision=$revision) AND (SELECT COUNT(*) FROM recipe_steps WHERE recipe_id=$id AND household_id=$household)=".count($steps)." AND (SELECT SHA2(GROUP_CONCAT(instruction ORDER BY position SEPARATOR 0x1f),256) FROM recipe_steps WHERE recipe_id=$id AND household_id=$household)=$digest AND NOT EXISTS(SELECT 1 FROM recipe_step_actions WHERE recipe_id=$id AND household_id=$household)";
            $count=0;
            foreach($recipe['actions'] as $position=>$actions){
                $position=(int)$position;
                if($position<1 || !isset($steps[$position-1]))throw new InvalidArgumentException('Unknown step position');
                foreach($actions as $index=>$action){
                    $type=$action['action_type'];
                    if(!in_array($type,['timer','rest','appliance_temperature','internal_temperature','reminder'],true))throw new InvalidArgumentException('Unknown action type');
                    if(in_array($type,['timer','rest'],true) && (!is_int($action['duration_seconds']??null) || $action['duration_seconds']<1))throw new InvalidArgumentException('Invalid duration');
                    if(in_array($type,['appliance_temperature','internal_temperature'],true) && (!is_numeric($action['temperature_value']??null) || !in_array($action['temperature_unit']??null,['F','C'],true)))throw new InvalidArgumentException('Invalid temperature');
                    $columns=['action_type','label','duration_seconds','temperature_value','temperature_unit','appliance'];
                    $values=[];foreach($columns as $column)$values[]=$lit($action[$column]??null);
                    $sql[]='INSERT INTO recipe_step_actions(household_id,recipe_id,step_id,position,'.implode(',',$columns).') SELECT '.$household.','.$id.',s.id,'.($index+1).','.implode(',',$values).' FROM recipe_steps s WHERE s.household_id='.$household.' AND s.recipe_id='.$id.' AND s.position='.$position.' AND BINARY s.instruction=BINARY '.$lit($steps[$position-1]).' AND @apply';
                    $count++;
                }
            }
            if(!$count)throw new InvalidArgumentException('No actions planned');
            $sql[]="UPDATE recipes SET revision=revision+1,updated_by_user_id=$user WHERE id=$id AND household_id=$household AND @apply";
            $sql[]="SELECT $id AS recipe_id,@apply AS actions_applied,$count AS planned_actions";
        }
        $sql[]='COMMIT';
        return implode(";\n",$sql).";\n";
    }
}
