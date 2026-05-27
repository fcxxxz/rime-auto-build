#!/usr/bin/env pwsh
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $PSCommandPath
Import-Module (Join-Path $ScriptDir 'lib\State.psm1') -Force

$StatePath = if ($env:STATE_PATH) { $env:STATE_PATH } else { Join-Path $ScriptDir '..\state\last-seen.json' }

if (-not $env:PROBED_JSON) { throw 'PROBED_JSON not set' }
$probedRaw = $env:PROBED_JSON | ConvertFrom-Json -AsHashtable
$probed = [pscustomobject]@{
    weasels = if ($probedRaw.ContainsKey('weasels')) { $probedRaw['weasels'] } else { @{} }
    datas   = if ($probedRaw.ContainsKey('datas'))   { $probedRaw['datas'] }   else { @{} }
}

$previous = Read-State -Path $StatePath
$diff = Compare-State -Previous $previous -Probed $probed

if (-not $env:GITHUB_OUTPUT) { throw 'GITHUB_OUTPUT not set' }
Add-Content -Path $env:GITHUB_OUTPUT -Value "changed=$($diff.changed.ToString().ToLower())"
$ctJson = $diff.changed_targets | ConvertTo-Json -Compress
Add-Content -Path $env:GITHUB_OUTPUT -Value "changed_targets=$ctJson"
Add-Content -Path $env:GITHUB_OUTPUT -Value "summary=$($diff.summary)"

if ($diff.changed) {
    Write-Host "Changes detected: $($diff.summary)"
    Write-State -Path $StatePath -Probed $probed
} else {
    Write-Host "No upstream changes."
}
