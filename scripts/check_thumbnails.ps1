#!/usr/bin/env pwsh
# check_thumbnails.ps1 -- find metadata entries missing a thumbnail and re-fetch them
# Usage: pwsh scripts/check_thumbnails.ps1

param()

$ErrorActionPreference = 'Stop'

$ProjectDir    = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$MetadataDir   = Join-Path $ProjectDir 'metadata'
$ThumbnailsDir = Join-Path $ProjectDir 'thumbnails'
$CookiesFile   = if ($env:COOKIES_FILE) { $env:COOKIES_FILE }
                 else { Join-Path $ProjectDir 'cookies' 'cookies.txt' }

$missing = [System.Collections.Generic.List[string]]::new()
foreach ($f in Get-ChildItem $MetadataDir -Filter '*.info.json' -ErrorAction SilentlyContinue) {
    $id = $f.BaseName -replace '\.info$', ''
    if ($id -like '*favorites*') { continue }
    if (-not (Test-Path (Join-Path $ThumbnailsDir "$id.jpg"))) {
        $null = $missing.Add($id)
    }
}

if ($missing.Count -eq 0) {
    Write-Host "[+] All thumbnails present"
    exit 0
}

Write-Host "[*] $($missing.Count) missing thumbnail(s) -- re-fetching..."

foreach ($id in $missing) {
    $metaPath = Join-Path $MetadataDir "$id.info.json"
    $url = python3 -c "import json,sys; print(json.load(open(sys.argv[1])).get('webpage_url',''))" $metaPath 2>$null
    if (-not $url) {
        Write-Host "    [!] No URL for $id -- skipping"
        continue
    }
    Write-Host "    Fetching thumbnail: $id"
    $ytArgs = @(
        '--cookies', $CookiesFile,
        '--write-thumbnail', '--skip-download', '--convert-thumbnails', 'jpg',
        '--retries', '3',
        '-o', (Join-Path $MetadataDir '%(id)s'),
        $url
    )
    & yt-dlp @ytArgs 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) { Write-Host "    [!] Failed: $id" }
    $thumbInMeta = Join-Path $MetadataDir "$id.jpg"
    if (Test-Path $thumbInMeta) {
        Move-Item -Force $thumbInMeta (Join-Path $ThumbnailsDir "$id.jpg")
    }
}

Write-Host "[+] Done"
