$ErrorActionPreference = 'Stop'
function Get-Steps($items) {
    foreach ($item in @($items)) {
        if ($item -is [string]) { $item; continue }
        if ($item.itemListElement) { Get-Steps $item.itemListElement }
        elseif ($item.text) { $item.text }
    }
}
$sources = Get-Content (Join-Path $PSScriptRoot 'recipes.json') -Raw | ConvertFrom-Json -Depth 100
$ready = @(foreach ($source in $sources) {
    foreach ($recipe in $source.recipes) {
        $ingredients = @($recipe.recipeIngredient)
        $steps = @(Get-Steps $recipe.recipeInstructions)
        if (!$ingredients.Count -or !$steps.Count) { continue }
        [ordered]@{
            title=[System.Net.WebUtility]::HtmlDecode($recipe.name)
            source_url=$source.source_url
            bookmark_url=$source.bookmark_url
            collected_at_utc=$source.collected_at_utc
            author=$recipe.author
            yield=$recipe.recipeYield
            prep_time=$recipe.prepTime
            cook_time=$recipe.cookTime
            total_time=$recipe.totalTime
            ingredients_original=$ingredients
            instructions_original=$steps
            instructions_structured=$recipe.recipeInstructions
            category=$recipe.recipeCategory
            cuisine=$recipe.recipeCuisine
            nutrition_source=$recipe.nutrition
            image_source=$recipe.image
            review_status='source_extracted_unreviewed'
        }
    }
})
$ready | ConvertTo-Json -Depth 100 | Set-Content -Encoding utf8 (Join-Path $PSScriptRoot 'import-ready.json')
$ready | ForEach-Object { Write-Output "$($_.title): $($_.ingredients_original.Count) ingredients, $($_.instructions_original.Count) steps" }
