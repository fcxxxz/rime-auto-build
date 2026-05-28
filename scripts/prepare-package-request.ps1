#!/usr/bin/env pwsh
param(
  [Parameter(Mandatory)][string]$IssueBodyPath,
  [string]$BuildsPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $PSCommandPath
Import-Module (Join-Path $ScriptDir 'lib\Yaml.psm1') -Force
Import-Module (Join-Path $ScriptDir 'lib\PackageRequest.psm1') -Force

if (-not $BuildsPath) {
  $BuildsPath = if ($env:BUILDS_YAML_PATH) { $env:BUILDS_YAML_PATH } else { Join-Path $ScriptDir '..\builds.yaml' }
}

function Add-PackageRequestOutput {
  param(
    [Parameter(Mandatory)][string]$Name,
    [AllowNull()][string]$Value
  )
  if (-not $env:GITHUB_OUTPUT) {
    return
  }
  Add-Content -Path $env:GITHUB_OUTPUT -Value "$Name=$Value"
}

function Add-PackageRequestMultilineOutput {
  param(
    [Parameter(Mandatory)][string]$Name,
    [AllowNull()][string]$Value
  )
  if (-not $env:GITHUB_OUTPUT) {
    return
  }
  $delim = "EOF_$([guid]::NewGuid().ToString('N'))"
  Add-Content -Path $env:GITHUB_OUTPUT -Value "$Name<<$delim"
  Add-Content -Path $env:GITHUB_OUTPUT -Value $Value
  Add-Content -Path $env:GITHUB_OUTPUT -Value $delim
}

try {
  if (-not (Test-Path -LiteralPath $IssueBodyPath -PathType Leaf)) {
    throw "issue body file not found: $IssueBodyPath"
  }

  $body = Get-Content -LiteralPath $IssueBodyPath -Raw
  $request = ConvertFrom-PackageRequestIssueBody -Body $body
  $config = Read-BuildsYaml -Path $BuildsPath
  $validated = Resolve-PackageRequest -Request $request -Config $config
  $json = $validated | ConvertTo-Json -Compress -Depth 10

  Add-PackageRequestOutput -Name 'valid' -Value 'true'
  Add-PackageRequestOutput -Name 'data_name' -Value $validated.data_name
  Add-PackageRequestOutput -Name 'data_display' -Value $validated.data_display
  Add-PackageRequestOutput -Name 'data_url' -Value $validated.data_url
  Add-PackageRequestOutput -Name 'data_ref' -Value $validated.data_ref
  Add-PackageRequestOutput -Name 'github_owner' -Value $validated.github_owner
  Add-PackageRequestOutput -Name 'github_repo' -Value $validated.github_repo
  Add-PackageRequestOutput -Name 'weasel_name' -Value $validated.weasel_name
  Add-PackageRequestOutput -Name 'weasel_display' -Value $validated.weasel_display
  Add-PackageRequestOutput -Name 'weasel_url' -Value $validated.weasel_url
  Add-PackageRequestOutput -Name 'weasel_ref' -Value $validated.weasel_ref
  Add-PackageRequestMultilineOutput -Name 'request_json' -Value $json

  Write-Host "Package request validated: $($validated.data_name) x $($validated.weasel_name)"
} catch {
  Add-PackageRequestOutput -Name 'valid' -Value 'false'
  Add-PackageRequestOutput -Name 'error' -Value $_.Exception.Message
  throw
}
