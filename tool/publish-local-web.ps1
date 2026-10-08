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
    $destination = 'C:\xampp\htdocs\CoffeyTableRecipes\app'
    New-Item -ItemType Directory -Path $destination -Force | Out-Null
    Copy-Item -Path 'build\web\*' -Destination $destination -Recurse -Force
    Write-Output 'Open http://localhost/CoffeyTableRecipes/'
} finally {
    Pop-Location
}
