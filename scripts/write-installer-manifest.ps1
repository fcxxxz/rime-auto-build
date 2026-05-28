#!/usr/bin/env pwsh
param(
  [Parameter(Mandatory)][string]$InstallerName,
  [Parameter(Mandatory)][string]$DataName,
  [Parameter(Mandatory)][string]$DataUrl,
  [Parameter(Mandatory)][string]$DataRef,
  [Parameter(Mandatory)][string]$DataSha,
  [Parameter(Mandatory)][string]$WeaselName,
  [Parameter(Mandatory)][string]$WeaselUrl,
  [Parameter(Mandatory)][string]$WeaselRef,
  [Parameter(Mandatory)][string]$WeaselSha,
  [Parameter(Mandatory)][string]$OutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $PSCommandPath
Import-Module (Join-Path $ScriptDir 'lib\ReleaseNotes.psm1') -Force

$manifest = New-InstallerManifest `
  -InstallerName $InstallerName `
  -DataName $DataName `
  -DataUrl $DataUrl `
  -DataRef $DataRef `
  -DataSha $DataSha `
  -WeaselName $WeaselName `
  -WeaselUrl $WeaselUrl `
  -WeaselRef $WeaselRef `
  -WeaselSha $WeaselSha

$parent = Split-Path -Parent $OutputPath
if ($parent -and -not (Test-Path -LiteralPath $parent)) {
  New-Item -ItemType Directory -Path $parent -Force | Out-Null
}

[System.IO.File]::WriteAllText($OutputPath, ($manifest | ConvertTo-Json -Depth 10), [System.Text.UTF8Encoding]::new($false))
Write-Host "Wrote installer manifest: $OutputPath"
