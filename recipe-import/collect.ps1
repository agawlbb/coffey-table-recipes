$ErrorActionPreference = 'Stop'
$bookmarks = Get-Content (Join-Path $PSScriptRoot 'bookmarks.json') -Raw | ConvertFrom-Json
function Find-Recipe($obj) {
    if ($null -eq $obj) { return }
    if ($obj -is [array]) { foreach ($item in $obj) { Find-Recipe $item }; return }
    if ($obj.'@type' -contains 'Recipe') { return $obj }
    if ($obj.'@graph') { Find-Recipe $obj.'@graph' }
}
$results = @()
foreach ($bookmark in $bookmarks) {
    $url = $bookmark.bookmark_url -replace '^http:', 'https:'
    if ($url -match 'geniuskitchen') { $url = 'https://www.food.com/recipe/homemade-hamburger-buns-bread-machine-80413' }
    if ($url -match 'cafedelites') { $url = 'https://cafedelites.com/hot-fudge-chocolate-pudding-cake/' }
    $entry = [ordered]@{ bookmark_title=$bookmark.title; bookmark_url=$bookmark.bookmark_url; requested_url=$url; collected_at_utc=[DateTime]::UtcNow.ToString('o'); status='pending'; recipes=@() }
    try {
        $page = Invoke-WebRequest -Uri $url -TimeoutSec 25 -UserAgent 'Mozilla/5.0'
        $entry['source_url'] = $page.BaseResponse.RequestMessage.RequestUri.AbsoluteUri
        $recipes = @(foreach ($match in [regex]::Matches($page.Content, '(?is)<script[^>]*type=["'']application/ld\+json["''][^>]*>(.*?)</script>')) {
            try { Find-Recipe ($match.Groups[1].Value | ConvertFrom-Json -Depth 100) } catch { }
        })
        $entry.recipes = $recipes
        $entry.status = if ($recipes.Count) { 'collected' } else { 'needs_manual_extraction' }
    } catch { $entry.status='fetch_failed'; $entry['error']=$_.Exception.Message }
    $results += [pscustomobject]$entry
    $results | ConvertTo-Json -Depth 100 | Set-Content -Encoding utf8 (Join-Path $PSScriptRoot 'recipes.json')
    Write-Output "$($entry.status): $($bookmark.title)"
}
