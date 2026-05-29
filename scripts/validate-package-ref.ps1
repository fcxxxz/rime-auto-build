#!/usr/bin/env pwsh
param(
  [Parameter(Mandatory)][string]$Ref
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $PSCommandPath
Import-Module (Join-Path $ScriptDir 'lib\PackageRequest.psm1') -Force

$request = [pscustomobject]@{
  data_name = 'sample'
  data_display = 'sample'
  data_url = 'https://github.com/example/sample.git'
  data_ref = $Ref
  weasel_name = 'rime'
}
$config = [pscustomobject]@{
  weasels = @(
    [pscustomobject]@{
      name = 'rime'
      display = '官方小狼毫'
      url = 'https://github.com/rime/weasel.git'
      ref = 'master'
    }
  )
  datas = @()
}

$null = Resolve-PackageRequest -Request $request -Config $config
