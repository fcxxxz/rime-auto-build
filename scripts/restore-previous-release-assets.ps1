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
gh release download $tag --repo $Repository --pattern '*.exe' --dir $PackageRoot --clobber
if ($LASTEXITCODE -ne 0) {
  throw "failed to download previous release installers from $tag"
}

$zipPath = Join-Path $env:RUNNER_TEMP 'release-manifests.zip'
if (-not $env:RUNNER_TEMP) {
  $zipPath = Join-Path ([System.IO.Path]::GetTempPath()) 'release-manifests.zip'
}
Remove-Item -LiteralPath $zipPath -Force -ErrorAction SilentlyContinue

gh release download $tag --repo $Repository --pattern 'release-manifests.zip' --dir (Split-Path -Parent $zipPath) --clobber 2>$null
if ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $zipPath)) {
  Expand-Archive -LiteralPath $zipPath -DestinationPath $ManifestRoot -Force
  Write-Host "Restored previous manifests from release-manifests.zip"
  return
}

$release = Invoke-GhJson -Args @('release', 'view', $tag, '--repo', $Repository, '--json', 'body')
$manifests = @(ConvertFrom-ReleaseNotes -Markdown ([string]$release.body))
foreach ($manifest in $manifests) {
  $path = Join-Path $ManifestRoot "manifest-$($manifest.data.name)-$($manifest.weasel.name).json"
  [System.IO.File]::WriteAllText($path, ($manifest | ConvertTo-Json -Depth 10), [System.Text.UTF8Encoding]::new($false))
}
Write-Host "Recovered $($manifests.Count) manifest(s) from previous release notes."
