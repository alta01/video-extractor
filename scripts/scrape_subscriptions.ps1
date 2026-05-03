#!/usr/bin/env pwsh
# scrape_subscriptions.ps1 -- scrape videos for each channel in a subscriptions page
# Usage: pwsh scripts/scrape_subscriptions.ps1 <subscriptions-url> [--Limit N] [--Parallel N] [--Yes] [--Force]
#
# Tip: source sources.conf.ps1 and run:
#   . ./sources.conf.ps1; pwsh scripts/scrape_subscriptions.ps1 $SUBSCRIPTIONS_URL

param(
    [Parameter(Mandatory)][string]$SubscriptionsUrl,
    [int]$Limit      = 0,
    [int]$Parallel   = 1,
    [switch]$Yes,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

$ProjectDir  = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$CookiesFile = if ($env:COOKIES_FILE) { $env:COOKIES_FILE }
               else { Join-Path $ProjectDir 'cookies' 'cookies.txt' }

if (-not (Test-Path $CookiesFile)) {
    Write-Error "[!] No cookies file found at $CookiesFile"
    exit 1
}

Write-Host "[*] Fetching subscriptions from: $SubscriptionsUrl"

# Parse subscriptions page via Python (platform-agnostic, reuses cookie jar logic)
$pyScript = @'
import sys, re, urllib.request, http.cookiejar
from urllib.parse import urlparse

url, cookie_file = sys.argv[1], sys.argv[2]
base = "{0.scheme}://{0.netloc}".format(urlparse(url))

cj = http.cookiejar.MozillaCookieJar(cookie_file)
try:
    cj.load(ignore_discard=True, ignore_expires=True)
except Exception:
    pass

opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(cj))
opener.addheaders = [
    ('User-Agent', 'Mozilla/5.0 (X11; Linux x86_64; rv:120.0) Gecko/20100101 Firefox/120.0'),
    ('Accept-Language', 'en-US,en;q=0.9'),
]

try:
    html = opener.open(url, timeout=15).read().decode('utf-8', errors='replace')
except Exception as e:
    print(f"# Error: {e}", file=sys.stderr)
    sys.exit(1)

skip_names = {'subscriptions','videos','playlists','photos','activity',
              'favorites','login','register','search','categories'}
found = set()
pattern = re.compile(
    r'href="((?:' + re.escape(base) + r')?/(model|pornstar|users|channels)/([^"/?#\s]+))'
)
for m in pattern.finditer(html):
    path, kind, name = m.group(1), m.group(2), m.group(3)
    if name.lower() in skip_names or name.startswith('?'):
        continue
    full = path if path.startswith('http') else base + path
    found.add((kind, name, full.rstrip('/')))

for kind, name, full_url in sorted(found):
    print(f"{kind}\t{name}\t{full_url}")
'@

$channelLines = python3 -c $pyScript $SubscriptionsUrl $CookiesFile 2>$null

if (-not $channelLines) {
    Write-Error "[!] No subscriptions found -- ensure cookies are current and the URL is correct."
    exit 1
}

$channels = $channelLines | Where-Object { $_.Trim() } | ForEach-Object {
    $parts = $_ -split '\t', 3
    [PSCustomObject]@{ Kind = $parts[0]; Name = $parts[1]; Url = $parts[2] }
}

Write-Host ""
Write-Host "[*] Found channels:"
foreach ($ch in $channels) {
    Write-Host ("    [{0,-10}] {1}" -f $ch.Kind, $ch.Name)
}
Write-Host ""

if (-not $Yes) {
    $confirm = Read-Host "[?] Scrape all of the above? [y/N]"
    if ($confirm -notmatch '^[Yy]$') { Write-Host "Aborted."; exit 0 }
}

$scrapeScript = Join-Path $PSScriptRoot 'scrape.ps1'
$total   = $channels.Count
$current = 0

foreach ($ch in $channels) {
    $current++
    Write-Host ""
    Write-Host "[->] ($current/$total) $($ch.Name)"
    $videoUrl = "$($ch.Url)/videos"
    $scrapeArgs = @($videoUrl)
    if ($Force)       { $scrapeArgs += '--Force' }
    if ($Parallel -gt 1) { $scrapeArgs += '--Parallel'; $scrapeArgs += $Parallel }
    if ($Limit -gt 0) { $scrapeArgs += '--Limit'; $scrapeArgs += $Limit }
    pwsh $scrapeScript @scrapeArgs
}

Write-Host ""
Write-Host "[+] All channels processed. Run: python3 scripts/build_catalog.py"
