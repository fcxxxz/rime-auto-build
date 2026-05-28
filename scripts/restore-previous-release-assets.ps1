#!/usr/bin/env pwsh
param(
  [string]$Repository = $env:GITHUB_REPOSITORY,
  [string]$CurrentTag = '',
  [string]$PackageRoot = 'out/previous-packages',
  [string]$ManifestRoot = 'out/previous-manifests',
  [string]$FallbackReleaseTag = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $PSCommandPath
Import-Module (Join-Path $ScriptDir 'lib\ReleaseNotes.psm1') -Force
Import-Module (Join-Path $ScriptDir 'lib\Yaml.psm1') -Force

foreach ($path in @($PackageRoot, $ManifestRoot)) {
  if (Test-Path -LiteralPath $path) {
    Remove-Item -LiteralPath $path -Recurse -Force
  }
  New-Item -ItemType Directory -Path $path -Force | Out-Null
}

function Invoke-GhJson {
  param([Parameter(Mandatory)][string[]]$Args)
  $json = & gh @Args
  if ($LASTEXITCODE -ne 0) {
    throw "gh failed: gh $($Args -join ' ')"
  }
  return $json | ConvertFrom-Json
}

function Get-GhAuthToken {
  if (-not [string]::IsNullOrWhiteSpace($env:GH_TOKEN)) {
    return $env:GH_TOKEN
  }
  if (-not [string]::IsNullOrWhiteSpace($env:GITHUB_TOKEN)) {
    return $env:GITHUB_TOKEN
  }

  $token = & gh auth token
  if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($token)) {
    throw 'failed to resolve GitHub token for release asset downloads'
  }
  return ([string]$token).Trim()
}

function Download-ReleaseAsset {
  param(
    [Parameter(Mandatory)]$Asset,
    [Parameter(Mandatory)][string]$DestinationRoot,
    [Parameter(Mandatory)][string]$Token
  )

  if (-not (Test-Path -LiteralPath $DestinationRoot)) {
    New-Item -ItemType Directory -Path $DestinationRoot -Force | Out-Null
  }

  $name = [string]$Asset.name
  $apiUrl = [string]$Asset.apiUrl
  $expectedSize = [int64]$Asset.size
  if ([string]::IsNullOrWhiteSpace($name) -or [string]::IsNullOrWhiteSpace($apiUrl)) {
    throw 'Release asset is missing name or apiUrl.'
  }

  $destination = Join-Path $DestinationRoot $name
  if (Test-Path -LiteralPath $destination) {
    $existingSize = (Get-Item -LiteralPath $destination).Length
    if ($existingSize -eq $expectedSize) {
      Write-Host "Already downloaded: $name"
      return $destination
    }
    Remove-Item -LiteralPath $destination -Force
  }

  $headers = @{
    Accept = 'application/octet-stream'
    Authorization = "Bearer $Token"
    'User-Agent' = 'rime-auto-build'
    'X-GitHub-Api-Version' = '2022-11-28'
  }

  Write-Host "Downloading release asset: $name"
  Invoke-WebRequest -Uri $apiUrl -Headers $headers -OutFile $destination -MaximumRedirection 10

  $actualSize = (Get-Item -LiteralPath $destination).Length
  if ($actualSize -ne $expectedSize) {
    throw "Size mismatch for $name`: expected $expectedSize byte(s), got $actualSize byte(s)."
  }
  return $destination
}

if ([string]::IsNullOrWhiteSpace($Repository)) {
  throw 'Repository is required.'
}

$BuildsPath = if ($env:BUILDS_YAML_PATH) { $env:BUILDS_YAML_PATH } else { Join-Path $ScriptDir '..\builds.yaml' }
$expectedInstallerCount = @(Expand-BuildMatrix -Config (Read-BuildsYaml -Path $BuildsPath)).Count

$releases = @(Invoke-GhJson -Args @('release', 'list', '--repo', $Repository, '--limit', '30', '--json', 'tagName,isDraft,isPrerelease,createdAt'))
$previousRelease = $null
foreach ($candidate in @($releases |
  Where-Object { -not $_.isDraft -and $_.tagName -ne $CurrentTag } |
  Sort-Object createdAt -Descending)) {
  $view = Invoke-GhJson -Args @('release', 'view', $candidate.tagName, '--repo', $Repository, '--json', 'assets')
  $assetNames = @($view.assets | ForEach-Object { $_.name })
  $installerCount = @($assetNames | Where-Object { $_ -like '*.exe' }).Count
  if (($assetNames -contains 'release-manifests.zip') -or $installerCount -ge $expectedInstallerCount) {
    $previousRelease = $candidate
    break
  }
  Write-Host "Skipping incomplete previous release $($candidate.tagName): $installerCount/$expectedInstallerCount installer asset(s)."
}

if (-not $previousRelease -and -not [string]::IsNullOrWhiteSpace($FallbackReleaseTag)) {
  $previousRelease = [pscustomobject]@{ tagName = $FallbackReleaseTag }
}

if (-not $previousRelease) {
  Write-Host 'No previous release found.'
  return
}

$tag = $previousRelease.tagName
Write-Host "Restoring previous release assets from $tag"

$previousView = Invoke-GhJson -Args @('release', 'view', $tag, '--repo', $Repository, '--json', 'assets,body')
$token = Get-GhAuthToken
$installerAssets = @($previousView.assets | Where-Object { $_.name -like '*.exe' })
foreach ($asset in $installerAssets) {
  Download-ReleaseAsset -Asset $asset -DestinationRoot $PackageRoot -Token $token | Out-Null
}

$zipPath = Join-Path $env:RUNNER_TEMP 'release-manifests.zip'
if (-not $env:RUNNER_TEMP) {
  $zipPath = Join-Path ([System.IO.Path]::GetTempPath()) 'release-manifests.zip'
}
Remove-Item -LiteralPath $zipPath -Force -ErrorAction SilentlyContinue

$manifestArchive = @($previousView.assets | Where-Object { $_.name -eq 'release-manifests.zip' } | Select-Object -First 1)
if ($manifestArchive.Count -gt 0) {
  $zipPath = Download-ReleaseAsset -Asset $manifestArchive[0] -DestinationRoot (Split-Path -Parent $zipPath) -Token $token
  Expand-Archive -LiteralPath $zipPath -DestinationPath $ManifestRoot -Force
  Write-Host "Restored previous manifests from release-manifests.zip"
  return
}

$manifests = @(ConvertFrom-ReleaseNotes -Markdown ([string]$previousView.body))
foreach ($manifest in $manifests) {
  $path = Join-Path $ManifestRoot "manifest-$($manifest.data.name)-$($manifest.weasel.name).json"
  [System.IO.File]::WriteAllText($path, ($manifest | ConvertTo-Json -Depth 10), [System.Text.UTF8Encoding]::new($false))
}
Write-Host "Recovered $($manifests.Count) manifest(s) from previous release notes."
