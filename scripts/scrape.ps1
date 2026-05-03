#!/usr/bin/env pwsh
# scrape.ps1 -- fetch metadata + thumbnails from a paginated video playlist
# Usage: pwsh scripts/scrape.ps1 [--Force] [--Parallel <N>] [--Limit <N>] <playlist-url>
#
# Requires: yt-dlp, python3
# Output:   metadata/ and thumbnails/ under project root

param(
    [string]$Url,
    [switch]$Force,
    [int]$Parallel = 1,
    [int]$Limit     = 0
)

$ErrorActionPreference = 'Stop'

$ProjectDir    = (Resolve-Path (Join-Path $PSScriptRoot '..'))
$MetadataDir   = Join-Path $ProjectDir 'metadata'
$ThumbnailsDir = Join-Path $ProjectDir 'thumbnails'
$CookiesFile   = if ($env:COOKIES_FILE) { $env:COOKIES_FILE }
                 else { Join-Path $ProjectDir 'cookies' 'cookies.txt' }

if (-not $Url) {
    Write-Error "[!] Usage: pwsh scrape.ps1 [--Force] [--Parallel <N>] [--Limit <N>] <playlist-url>"
    exit 1
}

if (-not (Test-Path $CookiesFile)) {
    Write-Error "[!] No cookies file found at $CookiesFile"
    exit 1
}

# Cookie freshness check
$now   = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$stale = 0
foreach ($line in (Get-Content $CookiesFile)) {
    if ($line.StartsWith('#') -or -not $line.Trim()) { continue }
    $parts = $line -split '\t'
    if ($parts.Count -ge 5) {
        $expiry = [long]0
        if ([long]::TryParse($parts[4], [ref]$expiry)) {
            if (($expiry -gt 0) -and ($expiry -lt ($now + 604800))) { $stale++ }
        }
    }
}
if ($stale -gt 0) {
    Write-Host "[!] Warning: $stale cookie(s) expired or expiring within 7 days -- consider re-exporting"
}

function Fetch-Entry {
    param([string]$Id, [string]$VideoUrl)
    $metaFile = Join-Path $MetadataDir "$Id.info.json"
    if ((-not $Force) -and (Test-Path $metaFile)) {
        Write-Host "    Skipping (exists): $Id"
        return $false
    }
    Write-Host "    Fetching: $Id"
    $args = @(
        '--cookies', $CookiesFile,
        '--write-info-json', '--write-thumbnail', '--skip-download',
        '--convert-thumbnails', 'jpg',
        '--retries', '3', '--sleep-interval', '1', '--max-sleep-interval', '3',
        '-o', (Join-Path $MetadataDir '%(id)s'),
        $VideoUrl
    )
    $result = & yt-dlp @args 2>$null
    if ($LASTEXITCODE -ne 0) { Write-Host "    [!] Failed: $Id" }
    $thumbInMeta = Join-Path $MetadataDir "$Id.jpg"
    if (Test-Path $thumbInMeta) {
        Move-Item -Force $thumbInMeta (Join-Path $ThumbnailsDir "$Id.jpg")
    }
    return $true
}

$seenIds  = @{}
$page     = 1
$fetched  = 0

while ($true) {
    if (($Limit -gt 0) -and ($fetched -ge $Limit)) {
        Write-Host "[*] Limit of $Limit reached -- stopping"
        break
    }

    $pageUrl = "${Url}?page=${page}"
    Write-Host "[*] Scraping page ${page}: $pageUrl"

    $rawEntries = & yt-dlp --cookies $CookiesFile --flat-playlist `
        --print '%(id)s %(url)s' $pageUrl 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $rawEntries) {
        Write-Host "[*] No results on page $page -- done paginating"
        break
    }

    $lines      = $rawEntries -split "`n" | Where-Object { $_.Trim() }
    $newEntries = [System.Collections.Generic.List[string]]::new()
    foreach ($line in $lines) {
        $id = ($line -split ' ', 2)[0]
        if (-not $seenIds.ContainsKey($id)) {
            $null = $newEntries.Add($line)
            $seenIds[$id] = 1
        }
    }

    if ($newEntries.Count -eq 0) {
        Write-Host "[*] Page $page returned only duplicates -- done paginating"
        break
    }

    # Trim to limit
    if (($Limit -gt 0) -and ($newEntries.Count -gt ($Limit - $fetched))) {
        $newEntries = $newEntries.GetRange(0, $Limit - $fetched)
    }

    Write-Host "[*] Page ${page}: $($newEntries.Count) entries to process"

    if ($Parallel -gt 1) {
        $results = $newEntries | ForEach-Object -Parallel {
            $id  = ($_ -split ' ', 2)[0]
            $url = ($_ -split ' ', 2)[1]
            # Re-import the function in the parallel runspace
            $metaFile = Join-Path $using:MetadataDir "$id.info.json"
            if ((-not $using:Force) -and (Test-Path $metaFile)) {
                Write-Host "    Skipping (exists): $id"
                return $false
            }
            Write-Host "    Fetching: $id"
            $ytArgs = @(
                '--cookies', $using:CookiesFile,
                '--write-info-json', '--write-thumbnail', '--skip-download',
                '--convert-thumbnails', 'jpg',
                '--retries', '3', '--sleep-interval', '1', '--max-sleep-interval', '3',
                '-o', (Join-Path $using:MetadataDir '%(id)s'),
                $url
            )
            & yt-dlp @ytArgs 2>$null | Out-Null
            $thumbInMeta = Join-Path $using:MetadataDir "$id.jpg"
            if (Test-Path $thumbInMeta) {
                Move-Item -Force $thumbInMeta (Join-Path $using:ThumbnailsDir "$id.jpg")
            }
            return $true
        } -ThrottleLimit $Parallel
        $fetched += ($results | Where-Object { $_ -eq $true }).Count
    } else {
        foreach ($entry in $newEntries) {
            $id  = ($entry -split ' ', 2)[0]
            $vid = ($entry -split ' ', 2)[1]
            if (Fetch-Entry -Id $id -VideoUrl $vid) { $fetched++ }
        }
    }

    $page++
}

$jsonCount  = @(Get-ChildItem $MetadataDir  -Filter '*.info.json' -ErrorAction SilentlyContinue).Count
$thumbCount = @(Get-ChildItem $ThumbnailsDir -Filter '*.jpg'       -ErrorAction SilentlyContinue).Count
Write-Host ""
Write-Host "[+] Done. Fetched: $fetched new  |  Metadata: $jsonCount  |  Thumbnails: $thumbCount"
Write-Host ""
Write-Host "[*] Run: python3 scripts/build_catalog.py"
