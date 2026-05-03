#!/usr/bin/env pwsh
# scrape_youtube.ps1 -- interactive YouTube channel or search scraper
# Usage: pwsh scripts/scrape_youtube.ps1 [--Url <channel-url-or-search>] [--Parallel N] [--Force]
#
# Prompts for source (channel / search) and scope (all / last N / date range) when not passed.
# No cookies required for public content.

param(
    [string]$Url,
    [int]$Parallel = 1,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

$ProjectDir    = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$MetadataDir   = Join-Path $ProjectDir 'metadata'
$ThumbnailsDir = Join-Path $ProjectDir 'thumbnails'

$extraArgs  = [System.Collections.Generic.List[string]]::new()
$scopeDesc  = ''
$isSearch   = $false

# ---- Prompt for source if not provided ----
if (-not $Url) {
    Write-Host ""
    Write-Host "What do you want to scrape?"
    Write-Host "  1) YouTube channel"
    Write-Host "  2) YouTube search / tag"
    $srcChoice = Read-Host "Choice [1/2]"

    if ($srcChoice -eq '2') {
        $term = Read-Host "Search term or tag"
        $Url  = "search:$term"
    } else {
        $Url = Read-Host "Channel URL (e.g. https://www.youtube.com/@mkbhd)"
    }
}

if ($Url.StartsWith('search:')) {
    $isSearch = $true
    $term     = $Url.Substring(7)
    $countStr = Read-Host "Max results [50]"
    $count    = if ($countStr) { $countStr } else { '50' }
    $Url      = "ytsearch${count}:${term}"
    $scopeDesc = "Search: `"$term`" (up to $count results)"
} else {
    # Normalise channel URL
    $channelUrl = $Url.TrimEnd('/')
    if (-not $channelUrl.EndsWith('/videos')) { $channelUrl = "$channelUrl/videos" }

    Write-Host ""
    Write-Host "Scrape scope:"
    Write-Host "  1) All videos"
    Write-Host "  2) Last N videos"
    Write-Host "  3) Date range"
    $scope = Read-Host "Choice [1/2/3]"

    switch ($scope) {
        '2' {
            $n = Read-Host "How many videos? [100]"
            if (-not $n) { $n = '100' }
            $extraArgs.Add('--playlist-end')
            $extraArgs.Add($n)
            $scopeDesc = "Last $n videos"
        }
        '3' {
            $fromDate = Read-Host "From date (YYYYMMDD)"
            if (-not $fromDate) { Write-Error "[!] From date required."; exit 1 }
            $toDate   = Read-Host "To date   (YYYYMMDD, blank = today)"
            $extraArgs.Add('--dateafter')
            $extraArgs.Add($fromDate)
            if ($toDate) { $extraArgs.Add('--datebefore'); $extraArgs.Add($toDate) }
            $scopeDesc = "Date range: $fromDate -> $(if ($toDate) { $toDate } else { 'today' })"
        }
        default { $scopeDesc = 'All videos' }
    }

    $Url = $channelUrl
}

Write-Host ""
Write-Host "[*] $scopeDesc"
Write-Host "[*] Fetching video list from YouTube..."

$ytListArgs = @('--flat-playlist', '--print', '%(id)s %(url)s') + $extraArgs + @($Url)
$rawEntries = & yt-dlp @ytListArgs 2>$null
if (-not $rawEntries) {
    Write-Error "[!] No videos found. Check the URL or search term and try again."
    exit 1
}

$entries = $rawEntries -split "`n" | Where-Object { $_.Trim() }
Write-Host "[*] $($entries.Count) video(s) found -- fetching metadata and thumbnails..."

function Fetch-YtEntry {
    param([string]$Id, [string]$VideoUrl, [bool]$ForceFlag)
    $metaFile = Join-Path $using:MetadataDir "$Id.info.json"
    if ((-not $ForceFlag) -and (Test-Path $metaFile)) {
        Write-Host "    Skipping (exists): $Id"; return $false
    }
    Write-Host "    Fetching: $Id"
    $args = @(
        '--write-info-json', '--write-thumbnail', '--skip-download',
        '--convert-thumbnails', 'jpg',
        '--retries', '3', '--sleep-interval', '1', '--max-sleep-interval', '3',
        '-o', (Join-Path $using:MetadataDir '%(id)s'),
        $VideoUrl
    )
    & yt-dlp @args 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) { Write-Host "    [!] Failed: $Id" }
    $thumbInMeta = Join-Path $using:MetadataDir "$Id.jpg"
    if (Test-Path $thumbInMeta) {
        Move-Item -Force $thumbInMeta (Join-Path $using:ThumbnailsDir "$Id.jpg")
    }
    return $true
}

$fetched = 0
if ($Parallel -gt 1) {
    $results = $entries | ForEach-Object -Parallel {
        $id  = ($_ -split ' ', 2)[0]
        $vid = ($_ -split ' ', 2)[1]
        $metaFile = Join-Path $using:MetadataDir "$id.info.json"
        if ((-not $using:Force) -and (Test-Path $metaFile)) {
            Write-Host "    Skipping (exists): $id"; return $false
        }
        Write-Host "    Fetching: $id"
        $ytArgs = @(
            '--write-info-json', '--write-thumbnail', '--skip-download',
            '--convert-thumbnails', 'jpg', '--retries', '3',
            '--sleep-interval', '1', '--max-sleep-interval', '3',
            '-o', (Join-Path $using:MetadataDir '%(id)s'), $vid
        )
        & yt-dlp @ytArgs 2>$null | Out-Null
        $thumbInMeta = Join-Path $using:MetadataDir "$id.jpg"
        if (Test-Path $thumbInMeta) {
            Move-Item -Force $thumbInMeta (Join-Path $using:ThumbnailsDir "$id.jpg")
        }
        return $true
    } -ThrottleLimit $Parallel
    $fetched = ($results | Where-Object { $_ -eq $true }).Count
} else {
    foreach ($entry in $entries) {
        $id  = ($entry -split ' ', 2)[0]
        $vid = ($entry -split ' ', 2)[1]
        $metaFile = Join-Path $MetadataDir "$id.info.json"
        if ((-not $Force) -and (Test-Path $metaFile)) {
            Write-Host "    Skipping (exists): $id"; continue
        }
        Write-Host "    Fetching: $id"
        $ytArgs = @(
            '--write-info-json', '--write-thumbnail', '--skip-download',
            '--convert-thumbnails', 'jpg', '--retries', '3',
            '--sleep-interval', '1', '--max-sleep-interval', '3',
            '-o', (Join-Path $MetadataDir '%(id)s'), $vid
        )
        & yt-dlp @ytArgs 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) { Write-Host "    [!] Failed: $id" } else { $fetched++ }
        $thumbInMeta = Join-Path $MetadataDir "$id.jpg"
        if (Test-Path $thumbInMeta) {
            Move-Item -Force $thumbInMeta (Join-Path $ThumbnailsDir "$id.jpg")
        }
    }
}

$jsonCount  = @(Get-ChildItem $MetadataDir  -Filter '*.info.json' -ErrorAction SilentlyContinue).Count
$thumbCount = @(Get-ChildItem $ThumbnailsDir -Filter '*.jpg'       -ErrorAction SilentlyContinue).Count
Write-Host ""
Write-Host "[+] Done. Fetched: $fetched new  |  Metadata: $jsonCount  |  Thumbnails: $thumbCount"
Write-Host ""
Write-Host "[*] Run: python3 scripts/build_catalog.py"
