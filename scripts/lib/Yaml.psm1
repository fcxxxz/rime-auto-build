Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Get-Module -ListAvailable -Name powershell-yaml)) {
    throw "powershell-yaml module not installed. Run: Install-Module powershell-yaml -Scope CurrentUser -Force"
}
Import-Module powershell-yaml -DisableNameChecking

function Read-BuildsYaml {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "builds.yaml not found: $Path"
    }
    $raw = Get-Content -LiteralPath $Path -Raw
    $parsed = ConvertFrom-Yaml $raw

    foreach ($section in 'weasels','datas') {
        if (-not $parsed.ContainsKey($section)) {
            throw "builds.yaml is missing required section: $section"
        }
        if (-not $parsed[$section] -or $parsed[$section].Count -eq 0) {
            throw "builds.yaml section '$section' must not be empty"
        }
        $names = @()
        foreach ($item in $parsed[$section]) {
            foreach ($field in 'name','url','ref') {
                if (-not $item.ContainsKey($field) -or [string]::IsNullOrWhiteSpace($item[$field])) {
                    throw "builds.yaml: entry in '$section' missing field '$field'"
                }
            }
            if ($names -contains $item['name']) {
                $singular = $section.TrimEnd('s')
                throw "builds.yaml: duplicate $singular name '$($item['name'])'"
            }
            $names += $item['name']
        }
    }

    if (-not $parsed.ContainsKey('excludes') -or $null -eq $parsed['excludes']) {
        $parsed['excludes'] = @()
    }

    return [pscustomobject]@{
        weasels  = @($parsed['weasels']  | ForEach-Object { [pscustomobject]$_ })
        datas    = @($parsed['datas']    | ForEach-Object { [pscustomobject]$_ })
        excludes = @($parsed['excludes'] | ForEach-Object { [pscustomobject]$_ })
    }
}

function Expand-BuildMatrix {
    param([Parameter(Mandatory)]$Config)

    $excludeSet = @{}
    foreach ($ex in $Config.excludes) {
        $excludeSet["$($ex.data)|$($ex.weasel)"] = $true
    }

    $result = New-Object System.Collections.Generic.List[object]
    foreach ($d in $Config.datas) {
        foreach ($w in $Config.weasels) {
            if ($excludeSet.ContainsKey("$($d.name)|$($w.name)")) { continue }
            $result.Add([pscustomobject]@{
                data_name   = $d.name
                data_url    = $d.url
                data_ref    = $d.ref
                weasel_name = $w.name
                weasel_url  = $w.url
                weasel_ref  = $w.ref
            })
        }
    }
    return $result.ToArray()
}

Export-ModuleMember -Function Read-BuildsYaml, Expand-BuildMatrix
