#!/usr/bin/env pwsh
param(
  [string]$PreviousPackageRoot = 'out/previous-packages',
  [string]$PreviousManifestRoot = 'out/previous-manifests',
  [string]$CurrentPackageRoot = 'out/current',
  [string]$CurrentManifestRoot = 'out/current-manifests',
  [string]$OutputPackageRoot = 'out/packages',
  [string]$OutputManifestRoot = 'out/manifests',
  [string]$ManifestArchivePath = 'out/release-manifests.zip',
  [string]$BuildsPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $PSCommandPath
Import-Module (Join-Path $ScriptDir 'lib\Yaml.psm1') -Force

if ([string]::IsNullOrWhiteSpace($BuildsPath)) {
  $BuildsPath = Join-Path $ScriptDir '..\builds.yaml'
}

function Get-ManifestKey {
  param([Parameter(Mandatory)]$Manifest)

  if (-not $Manifest.data.name -or -not $Manifest.weasel.name) {
    throw "Manifest is missing data.name or weasel.name"
  }
  return "$($Manifest.data.name)--$($Manifest.weasel.name)"
}

function Read-ManifestFiles {
  param([Parameter(Mandatory)][string]$Root)

  if (-not (Test-Path -LiteralPath $Root)) {
    return @{}
  }

  $items = @{}
  Get-ChildItem -LiteralPath $Root -Recurse -Filter 'manifest-*.json' -File | ForEach-Object {
    $manifest = Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json
    $key = Get-ManifestKey -Manifest $manifest
    $items[$key] = [pscustomobject]@{
      manifest = $manifest
      path = $_.FullName
    }
  }
  return $items
}

function Get-ConfiguredManifestKeys {
  param([Parameter(Mandatory)][string]$Path)

  $keys = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
  foreach ($item in Expand-BuildMatrix -Config (Read-BuildsYaml -Path $Path)) {
    [void]$keys.Add("$($item.data_name)--$($item.weasel_name)")
  }
  return $keys
}

function Copy-InstallerForManifest {
  param(
    [Parameter(Mandatory)]$Manifest,
    [Parameter(Mandatory)][string[]]$Roots,
    [Parameter(Mandatory)][string]$DestinationRoot
  )

  $installer = [string]$Manifest.installer
  foreach ($root in $Roots) {
    if ([string]::IsNullOrWhiteSpace($root) -or -not (Test-Path -LiteralPath $root)) {
      continue
    }
    $source = Join-Path $root $installer
    if (Test-Path -LiteralPath $source) {
      Copy-Item -LiteralPath $source -Destination (Join-Path $DestinationRoot $installer) -Force
      return
    }
  }
  throw "Installer not found for manifest: $installer"
}

foreach ($path in @($OutputPackageRoot, $OutputManifestRoot)) {
  if (Test-Path -LiteralPath $path) {
    Remove-Item -LiteralPath $path -Recurse -Force
  }
  New-Item -ItemType Directory -Path $path -Force | Out-Null
}

$previous = Read-ManifestFiles -Root $PreviousManifestRoot
$current = Read-ManifestFiles -Root $CurrentManifestRoot
$configuredKeys = Get-ConfiguredManifestKeys -Path $BuildsPath

foreach ($key in @($previous.Keys)) {
  if (-not $configuredKeys.Contains($key)) {
    Write-Host "Dropping previous release asset outside current builds.yaml: $key"
    $previous.Remove($key)
  }
}

foreach ($key in $current.Keys) {
  $previous[$key] = $current[$key]
}

foreach ($key in @($previous.Keys | Sort-Object)) {
  $entry = $previous[$key]
  $manifest = $entry.manifest
  $manifestName = "manifest-$($manifest.data.name)-$($manifest.weasel.name).json"
  Copy-InstallerForManifest -Manifest $manifest -Roots @($CurrentPackageRoot, $PreviousPackageRoot) -DestinationRoot $OutputPackageRoot
  [System.IO.File]::WriteAllText(
    (Join-Path $OutputManifestRoot $manifestName),
    ($manifest | ConvertTo-Json -Depth 10),
    [System.Text.UTF8Encoding]::new($false)
  )
}

if (Test-Path -LiteralPath $ManifestArchivePath) {
  Remove-Item -LiteralPath $ManifestArchivePath -Force
}
$archiveParent = Split-Path -Parent $ManifestArchivePath
if ($archiveParent -and -not (Test-Path -LiteralPath $archiveParent)) {
  New-Item -ItemType Directory -Path $archiveParent -Force | Out-Null
}
Compress-Archive -Path (Join-Path $OutputManifestRoot '*') -DestinationPath $ManifestArchivePath -Force
Write-Host "Merged $($previous.Count) release asset(s)."
