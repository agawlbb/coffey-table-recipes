param([switch]$SkipBuild)
$ErrorActionPreference = 'Stop'
Push-Location (Split-Path $PSScriptRoot -Parent)
try {
    $match = [regex]::Match((Get-Content pubspec.yaml -Raw), '(?m)^version: (\d+\.\d+\.\d+)\+(\d+)\s*$')
    if (-not $match.Success) { throw 'Expected version major.minor.patch+build in pubspec.yaml.' }
    $version = $match.Groups[1].Value
    $buildNumber = [int]$match.Groups[2].Value
    if (-not $SkipBuild) {
        flutter analyze
        if ($LASTEXITCODE -ne 0) { throw 'Analysis failed.' }
        flutter test
        if ($LASTEXITCODE -ne 0) { throw 'Tests failed.' }
        flutter build web --base-href=/CoffeyTableRecipes/app/ --dart-define-from-file=config/firebase.local.json
        if ($LASTEXITCODE -ne 0) { throw 'Web build failed.' }
        flutter build apk --release --dart-define-from-file=config/firebase.local.json
        if ($LASTEXITCODE -ne 0) { throw 'APK build failed.' }
    }
    $commit = git rev-parse HEAD
    @{ version = $version; build = $buildNumber; commit = $commit; channel = 'demonstration' } |
        ConvertTo-Json | Set-Content build/web/version.json -Encoding utf8
    New-Item -ItemType Directory -Force build/demo-package/app | Out-Null
    Copy-Item build/web/* build/demo-package/app -Recurse -Force
    Compress-Archive -Path build/demo-package/app -DestinationPath "build/CoffeyTableRecipes-$version-web.zip" -Force
    Write-Output "Web archive: build/CoffeyTableRecipes-$version-web.zip"
    Write-Output 'APK: build/app/outputs/flutter-apk/app-release.apk (debug identity)'
} finally { Pop-Location }
