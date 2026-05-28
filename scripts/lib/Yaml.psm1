Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function ConvertFrom-BuildsYamlValue {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Value)

    $trimmed = $Value.Trim()
    if (($trimmed.StartsWith("'") -and $trimmed.EndsWith("'")) -or
        ($trimmed.StartsWith('"') -and $trimmed.EndsWith('"'))) {
        return $trimmed.Substring(1, $trimmed.Length - 2)
    }
    return $trimmed
}

function ConvertFrom-BuildsYamlInlineMap {
    param([Parameter(Mandatory)][string]$Text)

    $trimmed = $Text.Trim()
    if (-not ($trimmed.StartsWith('{') -and $trimmed.EndsWith('}'))) {
        throw "unsupported inline YAML map: $Text"
    }

    $map = [ordered]@{}
    $body = $trimmed.Substring(1, $trimmed.Length - 2).Trim()
    if ([string]::IsNullOrWhiteSpace($body)) {
        return $map
    }

    foreach ($pair in ($body -split ',')) {
        $parts = $pair -split ':', 2
        if ($parts.Count -ne 2) {
            throw "unsupported inline YAML pair: $pair"
        }
        $map[$parts[0].Trim()] = ConvertFrom-BuildsYamlValue $parts[1]
    }
    return $map
}

function ConvertFrom-BuildsYaml {
    param([Parameter(Mandatory)][string]$Raw)

    $parsed = [ordered]@{}
    $section = $null
    $currentItem = $null

    foreach ($line in ($Raw -split "`r?`n")) {
        $withoutComment = ($line -split '#', 2)[0]
        if ([string]::IsNullOrWhiteSpace($withoutComment)) {
            continue
        }

        if ($withoutComment -match '^([A-Za-z_][A-Za-z0-9_-]*):\s*(?:\[\])?\s*$') {
            $section = $Matches[1]
            $parsed[$section] = New-Object System.Collections.Generic.List[object]
            $currentItem = $null
            continue
        }

        if (-not $section) {
            throw "unsupported YAML outside a section: $line"
        }

        if ($withoutComment -match '^\s*-\s*(.+?)\s*$') {
            $rest = $Matches[1]
            if ($rest.Trim().StartsWith('{')) {
                $currentItem = ConvertFrom-BuildsYamlInlineMap $rest
            } elseif ($rest -match '^([^:]+):\s*(.*)$') {
                $currentItem = [ordered]@{}
                $currentItem[$Matches[1].Trim()] = ConvertFrom-BuildsYamlValue $Matches[2]
            } else {
                throw "unsupported YAML list item: $line"
            }
            $parsed[$section].Add($currentItem)
            continue
        }

        if ($withoutComment -match '^\s+([^:]+):\s*(.*)$' -and $currentItem) {
            $currentItem[$Matches[1].Trim()] = ConvertFrom-BuildsYamlValue $Matches[2]
            continue
        }

        throw "unsupported YAML line: $line"
    }

    return $parsed
}

function Read-BuildsYaml {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "builds.yaml not found: $Path"
    }
    $raw = Get-Content -LiteralPath $Path -Raw
    $parsed = ConvertFrom-BuildsYaml $raw

    foreach ($section in 'weasels','datas') {
        if (-not $parsed.Contains($section)) {
            throw "builds.yaml is missing required section: $section"
        }
        if (-not $parsed[$section] -or $parsed[$section].Count -eq 0) {
            throw "builds.yaml section '$section' must not be empty"
        }
        $names = @()
        foreach ($item in $parsed[$section]) {
            foreach ($field in 'name','url','ref') {
                if (-not $item.Contains($field) -or [string]::IsNullOrWhiteSpace($item[$field])) {
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

    if (-not $parsed.Contains('excludes') -or $null -eq $parsed['excludes']) {
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
