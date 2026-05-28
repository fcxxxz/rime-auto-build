#!/usr/bin/env pwsh
param(
  [string]$ManifestRoot = 'out',
  [string]$OutputPath = 'out/release-notes.md',
  [string]$EventName = $env:GITHUB_EVENT_NAME,
  [string]$StatePath = 'state/last-seen.json',
  [string]$BuildsPath = 'builds.yaml'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $PSCommandPath
Import-Module (Join-Path $ScriptDir 'lib\ReleaseNotes.psm1') -Force

$manifestFiles = @(Get-ChildItem -LiteralPath $ManifestRoot -Recurse -Filter '*.json' -File |
  Where-Object { $_.Name -like 'manifest-*.json' })
if ($manifestFiles.Count -eq 0) {
  throw "No installer manifest files found under $ManifestRoot"
}

$manifests = @($manifestFiles | ForEach-Object {
  Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json
})

$notes = New-ReleaseNotes `
  -EventName $EventName `
  -StatePath $StatePath `
  -BuildsPath $BuildsPath `
  -Manifests $manifests

$parent = Split-Path -Parent $OutputPath
if ($parent -and -not (Test-Path -LiteralPath $parent)) {
  New-Item -ItemType Directory -Path $parent -Force | Out-Null
}

[System.IO.File]::WriteAllText($OutputPath, $notes, [System.Text.UTF8Encoding]::new($false))
Write-Host "Wrote release notes: $OutputPath"
