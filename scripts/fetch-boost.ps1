#!/usr/bin/env pwsh
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$BoostVersion = '1.84.0'
$BoostVerUnderscored = $BoostVersion.Replace('.','_')
$BoostDir = "boost_$BoostVerUnderscored"

if (Test-Path -LiteralPath $BoostDir) {
    Write-Host "$BoostDir already present (cache hit). Skipping download."
    exit 0
}

# 官方下载有时被墙；用 jfrog 镜像，必要时 fallback
$urls = @(
    "https://archives.boost.io/release/$BoostVersion/source/boost_$BoostVerUnderscored.zip",
    "https://boostorg.jfrog.io/artifactory/main/release/$BoostVersion/source/boost_$BoostVerUnderscored.zip",
    "https://sourceforge.net/projects/boost/files/boost/$BoostVersion/boost_$BoostVerUnderscored.zip/download"
)

$zipPath = "boost_$BoostVerUnderscored.zip"
$downloaded = $false
foreach ($u in $urls) {
    Write-Host "trying $u"
    try {
        Invoke-WebRequest -Uri $u -OutFile $zipPath -UseBasicParsing -TimeoutSec 600
        if ((Get-Item $zipPath).Length -gt 50MB) {
            $downloaded = $true; break
        }
    } catch {
        Write-Host "  failed: $($_.Exception.Message)"
    }
}
if (-not $downloaded) { throw 'failed to download Boost from any mirror' }

Write-Host "extracting $zipPath ..."
Expand-Archive -Path $zipPath -DestinationPath . -Force
Remove-Item $zipPath -Force

if (-not (Test-Path -LiteralPath $BoostDir)) {
    throw "Boost extracted but $BoostDir not found"
}
Write-Host "Boost ready at $BoostDir"
