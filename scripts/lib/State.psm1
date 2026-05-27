Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Read-State {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return [pscustomobject]@{
            weasels = @{}
            datas   = @{}
        }
    }

    $raw = Get-Content -LiteralPath $Path -Raw
    if ([string]::IsNullOrWhiteSpace($raw)) {
        return [pscustomobject]@{ weasels = @{}; datas = @{} }
    }
    $obj = $raw | ConvertFrom-Json -AsHashtable

    $weasels = @{}
    if ($obj.ContainsKey('weasels') -and $obj['weasels']) {
        foreach ($k in $obj['weasels'].Keys) { $weasels[$k] = $obj['weasels'][$k] }
    }
    $datas = @{}
    if ($obj.ContainsKey('datas') -and $obj['datas']) {
        foreach ($k in $obj['datas'].Keys) { $datas[$k] = $obj['datas'][$k] }
    }

    return [pscustomobject]@{ weasels = $weasels; datas = $datas }
}

function Compare-State {
    param(
        [Parameter(Mandatory)]$Previous,
        [Parameter(Mandatory)]$Probed
    )

    $changedWeasels = @()
    foreach ($name in $Probed.weasels.Keys) {
        $newSha = $Probed.weasels[$name].sha
        $oldSha = if ($Previous.weasels.ContainsKey($name)) { $Previous.weasels[$name].sha } else { $null }
        if ($newSha -ne $oldSha) { $changedWeasels += $name }
    }

    $changedDatas = @()
    foreach ($name in $Probed.datas.Keys) {
        $newSha = $Probed.datas[$name].sha
        $oldSha = if ($Previous.datas.ContainsKey($name)) { $Previous.datas[$name].sha } else { $null }
        if ($newSha -ne $oldSha) { $changedDatas += $name }
    }

    $changed = ($changedWeasels.Count + $changedDatas.Count) -gt 0
    $summary = "weasels=[$($changedWeasels -join ',')] datas=[$($changedDatas -join ',')]"

    return [pscustomobject]@{
        changed = $changed
        changed_targets = [pscustomobject]@{
            weasels = $changedWeasels
            datas   = $changedDatas
        }
        summary = $summary
    }
}

function Write-State {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)]$Probed
    )

    $now = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    $weasels = @{}
    foreach ($name in $Probed.weasels.Keys) {
        $e = $Probed.weasels[$name]
        $weasels[$name] = @{
            url = $e.url; ref = $e.ref; sha = $e.sha; checked_at = $now
        }
    }
    $datas = @{}
    foreach ($name in $Probed.datas.Keys) {
        $e = $Probed.datas[$name]
        $datas[$name] = @{
            url = $e.url; ref = $e.ref; sha = $e.sha; checked_at = $now
        }
    }

    $payload = [ordered]@{
        weasels = $weasels
        datas   = $datas
    } | ConvertTo-Json -Depth 10

    $parent = Split-Path -Parent $Path
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    # 写入时强制 UTF-8 无 BOM，保证 git diff 干净
    [System.IO.File]::WriteAllText($Path, $payload, [System.Text.UTF8Encoding]::new($false))
}

Export-ModuleMember -Function Read-State, Compare-State, Write-State
