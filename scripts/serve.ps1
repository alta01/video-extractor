#!/usr/bin/env pwsh
# serve.ps1 -- start the catalog server
# Usage: pwsh scripts/serve.ps1 [port]   (default: 8765)

param(
    [int]$Port = 8765
)

$ErrorActionPreference = 'Stop'
$ProjectDir = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Set-Location $ProjectDir
python3 (Join-Path $PSScriptRoot 'serve.py') $Port
