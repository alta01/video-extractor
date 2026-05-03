#!/usr/bin/env pwsh
# clean.ps1 -- remove metadata and thumbnails for IDs no longer in a playlist
# Usage: pwsh scripts/clean.ps1 <playlist-url>

param(
    [Parameter(Mandatory)][string]$Url
)

$ErrorActionPreference = 'Stop'

$ProjectDir    = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$MetadataDir   = Join-Path $ProjectDir 'metadata'
$ThumbnailsDir = Join-Path $ProjectDir 'thumbnails'
$CookiesFile   = if ($env:COOKIES_FILE) { $env:COOKIES_FILE }
                 else { Join-Path $ProjectDir 'cookies' 'cookies.txt' }

if (-not (Test-Path $CookiesFile)) {
    Write-Error "[!] No cookies file found at $CookiesFile"
    exit 1
}

Write-Host "[*] Fetching live ID list from playlist..."
$liveIds = @{}
$page    = 1

while ($true) {
    $pageUrl = "${Url}?page=${page}"
    $ids     = & yt-dlp --cookies $CookiesFile --flat-playlist --print '%(id)s' $pageUrl 2>$null
    if (-not $ids) { break }
    foreach ($id in ($ids -split "`n" | Where-Object { $_.Trim() })) {
        $liveIds[$id] = 1
    }
    $page++
}

Write-Host "[*] $($liveIds.Count) live IDs found"

$removed = 0
foreach ($f in Get-ChildItem $MetadataDir -Filter '*.info.json' -ErrorAction SilentlyContinue) {
    $id = $f.BaseName -replace '\.info$', ''
    if ($id -like '*favorites*') { continue }
    if (-not $liveIds.ContainsKey($id)) {
        Write-Host "    Removing: $id"
        Remove-Item $f.FullName -ErrorAction SilentlyContinue
        $thumb = Join-Path $ThumbnailsDir "$id.jpg"
        if (Test-Path $thumb) { Remove-Item $thumb }
        $removed++
    }
}

Write-Host "[+] Removed $removed orphaned entries"
