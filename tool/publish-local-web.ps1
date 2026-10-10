$ErrorActionPreference = 'Stop'
Push-Location (Split-Path $PSScriptRoot -Parent)
try {
    $firebaseConfig = 'config/firebase.local.json'
    if (Test-Path -LiteralPath $firebaseConfig) {
        flutter build web --base-href=/CoffeyTableRecipes/app/ --dart-define-from-file=$firebaseConfig
    } else {
        flutter build web --base-href=/CoffeyTableRecipes/app/
    }
    if ($LASTEXITCODE -ne 0) { throw 'Flutter web build failed.' }
    # Use content-specific font URLs, including for browsers with cached subsets.
    $manifestPath = Join-Path (Get-Location) 'build\web\assets\FontManifest.json'
    $fontManifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    foreach ($family in $fontManifest) {
        foreach ($font in $family.fonts) {
            $fontPath = Join-Path (Get-Location) ('build\web\assets\' + $font.asset)
            $fontHash = (Get-FileHash -LiteralPath $fontPath).Hash.Substring(0, 12).ToLowerInvariant()
            $extension = [IO.Path]::GetExtension($font.asset)
            $versionedAsset = $font.asset.Substring(0, $font.asset.Length - $extension.Length) + '-' + $fontHash + $extension
            Copy-Item -LiteralPath $fontPath -Destination (Join-Path (Get-Location) ('build\web\assets\' + $versionedAsset)) -Force
            $font.asset = $versionedAsset
        }
    }
    ConvertTo-Json -InputObject @($fontManifest) -Depth 10 -Compress | Set-Content -LiteralPath $manifestPath -Encoding utf8
    $destination = 'C:\xampp\htdocs\CoffeyTableRecipes\app'
    New-Item -ItemType Directory -Path $destination -Force | Out-Null
    Copy-Item -Path 'build\web\*' -Destination $destination -Recurse -Force
    # Local rebuilds change icon-font subsets at the same asset URLs.
    # Revalidate assets so Chrome cannot mix new code with an old icon font.
    @'
<IfModule mod_headers.c>
    Header set Cache-Control "no-store, max-age=0"
</IfModule>
'@ | Set-Content -LiteralPath (Join-Path $destination '.htaccess') -Encoding ascii
    Write-Output 'Open http://localhost/CoffeyTableRecipes/'
} finally {
    Pop-Location
}
