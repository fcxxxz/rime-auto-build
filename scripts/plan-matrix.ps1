#!/usr/bin/env pwsh
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $PSCommandPath
Import-Module (Join-Path $ScriptDir 'lib\Yaml.psm1') -Force

$BuildsPath = if ($env:BUILDS_YAML_PATH) { $env:BUILDS_YAML_PATH } else { Join-Path $ScriptDir '..\builds.yaml' }
$config = Read-BuildsYaml -Path $BuildsPath
$full   = Expand-BuildMatrix -Config $config

$eventName = $env:EVENT_NAME

switch ($eventName) {
    'push' {
        $filtered = $full
        $tagSuffix = '-config'
    }
    'workflow_dispatch' {
        $onlyData   = $env:INPUT_ONLY_DATA
        $onlyWeasel = $env:INPUT_ONLY_WEASEL
        $filtered = $full
        if ($onlyData)   { $filtered = $filtered | Where-Object { $_.data_name   -eq $onlyData } }
        if ($onlyWeasel) { $filtered = $filtered | Where-Object { $_.weasel_name -eq $onlyWeasel } }
        $tagSuffix = '-manual'
    }
    'repository_dispatch' {
        $payload = $env:DISPATCH_PAYLOAD
        if ([string]::IsNullOrWhiteSpace($payload) -or $payload -eq 'null') {
            $changedWeasels = @(); $changedDatas = @()
        } else {
            $obj = $payload | ConvertFrom-Json
            $changedWeasels = @($obj.changed_targets.weasels)
            $changedDatas   = @($obj.changed_targets.datas)
        }
        $filtered = $full | Where-Object {
            ($changedWeasels -contains $_.weasel_name) -or
            ($changedDatas   -contains $_.data_name)
        }
        $tagSuffix = ''
    }
    default {
        # schedule / other => full
        $filtered = $full
        $tagSuffix = ''
    }
}

$filtered = @($filtered)
$includeJson = $filtered | ConvertTo-Json -Compress -AsArray
$nowUtc = if ($env:PLAN_NOW_UTC) {
    ([DateTimeOffset]::Parse($env:PLAN_NOW_UTC, [Globalization.CultureInfo]::InvariantCulture)).UtcDateTime
} else {
    (Get-Date).ToUniversalTime()
}
$timestamp   = $nowUtc.AddHours(8).ToString('yyyyMMdd-HHmm')
$tag         = "build-$timestamp$tagSuffix"

if (-not $env:GITHUB_OUTPUT) {
    throw "GITHUB_OUTPUT environment variable not set"
}
Add-Content -Path $env:GITHUB_OUTPUT -Value "include=$includeJson"
Add-Content -Path $env:GITHUB_OUTPUT -Value "tag=$tag"

Write-Host "Planned $($filtered.Count) build(s) for event=$eventName"
Write-Host "Tag: $tag"
$filtered | ForEach-Object { Write-Host "  - $($_.data_name) x $($_.weasel_name)" }
