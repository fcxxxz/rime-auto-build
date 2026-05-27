#!/usr/bin/env pwsh
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $PSCommandPath
Import-Module (Join-Path $ScriptDir 'lib\Yaml.psm1') -Force

$BuildsPath = if ($env:BUILDS_YAML_PATH) { $env:BUILDS_YAML_PATH } else { Join-Path $ScriptDir '..\builds.yaml' }
$config = Read-BuildsYaml -Path $BuildsPath

function Resolve-Sha {
    param([string]$Url, [string]$Ref)
    # 优先匹配 refs/heads/$Ref，然后 refs/tags/$Ref，最后 refs/tags/$Ref^{}（annotated tag 解引用）
    $output = & git ls-remote $Url "refs/heads/$Ref" "refs/tags/$Ref" "refs/tags/$Ref^{}" 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "git ls-remote failed for $Url $Ref`: $output"
    }
    $lines = @(@($output) | Where-Object { $_ -is [string] -and $_.Length -gt 0 })
    if ($lines.Count -eq 0) {
        throw "ref not found: $Ref in $Url"
    }
    # 取第一条 head；没 head 取 tag 解引用；都没就第一条
    $head = $lines | Where-Object { $_ -match "refs/heads/$([regex]::Escape($Ref))$" } | Select-Object -First 1
    if ($head) { return ($head -split '\s+')[0] }
    $deref = $lines | Where-Object { $_ -match "refs/tags/$([regex]::Escape($Ref))\^\{\}$" } | Select-Object -First 1
    if ($deref) { return ($deref -split '\s+')[0] }
    return ($lines[0] -split '\s+')[0]
}

$weasels = @{}
foreach ($w in $config.weasels) {
    Write-Host "probe weasel: $($w.name) $($w.url) $($w.ref)"
    $weasels[$w.name] = @{
        url = $w.url
        ref = $w.ref
        sha = Resolve-Sha -Url $w.url -Ref $w.ref
    }
}
$datas = @{}
foreach ($d in $config.datas) {
    Write-Host "probe data: $($d.name) $($d.url) $($d.ref)"
    $datas[$d.name] = @{
        url = $d.url
        ref = $d.ref
        sha = Resolve-Sha -Url $d.url -Ref $d.ref
    }
}

$probed = [pscustomobject]@{ weasels = $weasels; datas = $datas }
$json   = $probed | ConvertTo-Json -Compress -Depth 10

if (-not $env:GITHUB_OUTPUT) { throw 'GITHUB_OUTPUT not set' }
# 多行/带特殊字符 → 用 heredoc 语法
$delim = "EOF_$([guid]::NewGuid().ToString('N'))"
Add-Content -Path $env:GITHUB_OUTPUT -Value "probed<<$delim"
Add-Content -Path $env:GITHUB_OUTPUT -Value $json
Add-Content -Path $env:GITHUB_OUTPUT -Value $delim
