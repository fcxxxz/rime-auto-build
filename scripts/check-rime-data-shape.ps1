#!/usr/bin/env pwsh
param(
  [Parameter(Mandatory)][string]$Path
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $PSCommandPath
Import-Module (Join-Path $ScriptDir 'lib\PackageRequest.psm1') -Force

function Add-RimeDataShapeOutput {
  param(
    [Parameter(Mandatory)][string]$Name,
    [AllowNull()][string]$Value
  )
  if (-not $env:GITHUB_OUTPUT) {
    return
  }
  Add-Content -Path $env:GITHUB_OUTPUT -Value "$Name=$Value"
}

if (Test-PackageRequestRimeDataShape -Path $Path) {
  Add-RimeDataShapeOutput -Name 'valid' -Value 'true'
  Write-Host "custom-data looks like a Rime data repository"
  exit 0
}

Add-RimeDataShapeOutput -Name 'valid' -Value 'false'
throw "custom-data does not look like a Rime data repository: expected *.schema.yaml or default.custom.yaml"
