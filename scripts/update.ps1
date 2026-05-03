#!/usr/bin/env pwsh
# update.ps1 -- scrape a playlist then rebuild the catalog
# Usage: pwsh scripts/update.ps1 <playlist-url> [scrape.ps1 params]

param(
    [Parameter(Mandatory)][string]$Url,
    [switch]$Force,
    [int]$Parallel = 1,
    [int]$Limit    = 0
)

$ErrorActionPreference = 'Stop'
$scrapeArgs = @($Url)
if ($Force)          { $scrapeArgs += '--Force' }
if ($Parallel -gt 1) { $scrapeArgs += '--Parallel'; $scrapeArgs += $Parallel }
if ($Limit -gt 0)    { $scrapeArgs += '--Limit'; $scrapeArgs += $Limit }

pwsh (Join-Path $PSScriptRoot 'scrape.ps1') @scrapeArgs
python3 (Join-Path $PSScriptRoot 'build_catalog.py')
