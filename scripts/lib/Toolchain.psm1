Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function ConvertTo-VcvarsVersion {
    param([AllowEmptyString()][string]$MsvcToolsVersion)

    if ([string]::IsNullOrWhiteSpace($MsvcToolsVersion)) {
        return $null
    }
    if ($MsvcToolsVersion -notmatch '^(\d+\.\d+)(?:\.\d+)?$') {
        throw "Invalid MSVC tools version '$MsvcToolsVersion'. Expected a version like 14.51.36231 or 14.51."
    }
    return $Matches[1]
}

function New-VsDevCmdCall {
    param(
        [Parameter(Mandatory)][string]$VsDevCmd,
        [AllowEmptyString()][string]$MsvcToolsVersion
    )

    $call = "call `"$VsDevCmd`" -arch=amd64 -host_arch=amd64"
    $vcvarsVersion = ConvertTo-VcvarsVersion $MsvcToolsVersion
    if ($vcvarsVersion) {
        $call += " -vcvars_ver=$vcvarsVersion"
    }
    return $call
}

function Get-DefaultToolsetForVsDevCmd {
    param([Parameter(Mandatory)][string]$VsDevCmd)

    $vsVersion = $null
    if ($VsDevCmd -match '\\Microsoft Visual Studio\\([^\\]+)\\') {
        $vsVersion = $Matches[1]
    }

    switch ($vsVersion) {
        '2019' { return @{ Platform = 'v142'; Bjam = 'msvc-14.2' } }
        '2022' { return @{ Platform = 'v143'; Bjam = 'msvc-14.3' } }
        '2026' { return @{ Platform = 'v145'; Bjam = 'msvc-14.3' } }
        '18'   { return @{ Platform = 'v145'; Bjam = 'msvc-14.3' } }
        default {
            return @{ Platform = 'v143'; Bjam = 'msvc-14.3' }
        }
    }
}

function Get-BoostLibraryNames {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('x32', 'x64')]
        [string]$Architecture,

        [Parameter(Mandatory)]
        [string[]]$Components
    )

    return @($Components | ForEach-Object {
        "libboost_$($_)-vc143-mt-s-$Architecture-1_84.lib"
    })
}

function Get-BoostLinkLibraries {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('x32', 'x64')]
        [string]$Architecture
    )

    return Get-BoostLibraryNames -Architecture $Architecture -Components @(
        'filesystem',
        'json',
        'locale',
        'regex',
        'serialization',
        'system',
        'wserialization',
        'thread',
        'chrono',
        'atomic'
    )
}

function Get-BoostDefaultLibraryOptions {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('x32', 'x64')]
        [string]$Architecture
    )

    return @((Get-BoostLinkLibraries $Architecture) | ForEach-Object {
        "/DEFAULTLIB:$_"
    })
}

function Get-BoostWholeArchiveOptions {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('x32', 'x64')]
        [string]$Architecture
    )

    return @((Get-BoostLinkLibraries $Architecture) | ForEach-Object {
        "/WHOLEARCHIVE:`"`$(BOOST_ROOT)\stage\lib\$_`""
    })
}

function Get-BoostLinkOptions {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('x32', 'x64')]
        [string]$Architecture
    )

    if ($Architecture -eq 'x32') {
        return Get-BoostWholeArchiveOptions $Architecture
    }

    return Get-BoostDefaultLibraryOptions $Architecture
}

function Get-ExpectedBoostLibraries {
    return @(
        Get-BoostLinkLibraries 'x32'
        Get-BoostLinkLibraries 'x64'
    )
}

function Get-MissingBoostLibraries {
    param([Parameter(Mandatory)][string]$BoostRoot)

    $stageLib = Join-Path $BoostRoot 'stage\lib'
    return @(Get-ExpectedBoostLibraries | Where-Object {
        -not (Test-Path -LiteralPath (Join-Path $stageLib $_))
    })
}

function New-BoostProjectConfig {
    param([Parameter(Mandatory)][string]$CompilerPath)

    return "using msvc : 14.3 : `"$CompilerPath`" ;"
}

function Select-ClPath {
    param([Parameter(Mandatory)][string[]]$Output)

    foreach ($line in $Output) {
        $trimmed = $line.Trim()
        if ($trimmed -match '^[A-Za-z]:\\.*\\cl\.exe$') {
            return $trimmed
        }
    }
    return $null
}

function Remove-BoostLibrariesFromDependencies {
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$AdditionalDependencies,
        [Parameter(Mandatory)][string[]]$Libraries
    )

    $boostLibraries = New-Object System.Collections.Generic.HashSet[string]([StringComparer]::OrdinalIgnoreCase)
    foreach ($lib in $Libraries) {
        [void]$boostLibraries.Add($lib)
    }

    $items = New-Object System.Collections.Generic.List[string]
    $seen = New-Object System.Collections.Generic.HashSet[string]([StringComparer]::OrdinalIgnoreCase)
    foreach ($item in ($AdditionalDependencies -split ';')) {
        if ([string]::IsNullOrWhiteSpace($item)) {
            continue
        }
        $trimmed = $item.Trim()
        if ($boostLibraries.Contains($trimmed)) {
            continue
        }
        if ($seen.Add($trimmed)) {
            $items.Add($trimmed)
        }
    }

    return ($items -join ';')
}

function Add-BoostOptionsToAdditionalOptions {
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$AdditionalOptions,
        [Parameter(Mandatory)][string[]]$Options
    )

    $current = $AdditionalOptions.Trim()
    $missing = @($Options | Where-Object {
        $current -notmatch [regex]::Escape($_)
    })

    if ($missing.Count -eq 0) {
        return $current
    }

    $insert = ($missing -join ' ')
    if ([string]::IsNullOrWhiteSpace($current)) {
        return "$insert %(AdditionalOptions)"
    }

    if ($current -match [regex]::Escape('%(AdditionalOptions)')) {
        return ($current -replace [regex]::Escape('%(AdditionalOptions)'), "$insert %(AdditionalOptions)")
    }

    return "$current $insert %(AdditionalOptions)"
}

function Remove-BoostOptionsFromAdditionalOptions {
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$AdditionalOptions
    )

    $items = New-Object System.Collections.Generic.List[string]
    foreach ($item in ($AdditionalOptions -split '\s+')) {
        if ([string]::IsNullOrWhiteSpace($item)) {
            continue
        }
        $trimmed = $item.Trim()
        if ($trimmed -match '^(?:/DEFAULTLIB:|/WHOLEARCHIVE:)?(?:.*[\\/])?libboost_[^"\s;]+\.lib"?$') {
            continue
        }
        $items.Add($trimmed)
    }

    return ($items -join ' ')
}

function Add-BoostLinkLibrariesToProject {
    param([Parameter(Mandatory)][string]$ProjectPath)

    $xml = [xml](Get-Content -LiteralPath $ProjectPath -Raw)
    $ns = New-Object System.Xml.XmlNamespaceManager($xml.NameTable)
    $ns.AddNamespace('msb', 'http://schemas.microsoft.com/developer/msbuild/2003')

    $changed = $false
    $groups = $xml.SelectNodes('//msb:ItemDefinitionGroup', $ns)
    foreach ($group in $groups) {
        $condition = $group.GetAttribute('Condition')
        $arch = $null
        if ($condition -match "\$\(Configuration\)\|\$\(Platform\)'\s*==\s*'Release\|Win32'") {
            $arch = 'x32'
        } elseif ($condition -match "\$\(Configuration\)\|\$\(Platform\)'\s*==\s*'Release\|x64'") {
            $arch = 'x64'
        }
        if (-not $arch) {
            continue
        }

        $link = $group.SelectSingleNode('msb:Link', $ns)
        if (-not $link) {
            continue
        }

        $boostLibraries = Get-BoostLinkLibraries $arch
        $boostOptions = Get-BoostLinkOptions $arch

        $additionalOptions = $link.SelectSingleNode('msb:AdditionalOptions', $ns)
        if (-not $additionalOptions) {
            $additionalOptions = $xml.CreateElement('AdditionalOptions', $xml.DocumentElement.NamespaceURI)
            [void]$link.AppendChild($additionalOptions)
        }

        $cleanOptions = Remove-BoostOptionsFromAdditionalOptions `
            -AdditionalOptions $additionalOptions.InnerText
        $updatedOptions = Add-BoostOptionsToAdditionalOptions `
            -AdditionalOptions $cleanOptions `
            -Options $boostOptions
        if ($additionalOptions.InnerText -ne $updatedOptions) {
            $additionalOptions.InnerText = $updatedOptions
            $changed = $true
        }

        $additional = $link.SelectSingleNode('msb:AdditionalDependencies', $ns)
        if ($additional) {
            $updated = Remove-BoostLibrariesFromDependencies `
                -AdditionalDependencies $additional.InnerText `
                -Libraries $boostLibraries
            if ($additional.InnerText -ne $updated) {
                $additional.InnerText = $updated
                $changed = $true
            }
        }
    }

    if ($changed) {
        $settings = [System.Xml.XmlWriterSettings]::new()
        $settings.Encoding = [System.Text.UTF8Encoding]::new($false)
        $settings.Indent = $true
        $settings.NewLineChars = "`r`n"
        $writer = [System.Xml.XmlWriter]::Create($ProjectPath, $settings)
        try {
            $xml.Save($writer)
        } finally {
            $writer.Close()
        }
    }

    return $changed
}

Export-ModuleMember -Function ConvertTo-VcvarsVersion, New-VsDevCmdCall, Get-DefaultToolsetForVsDevCmd, Get-BoostLinkLibraries, Get-ExpectedBoostLibraries, Get-MissingBoostLibraries, New-BoostProjectConfig, Select-ClPath, Add-BoostLinkLibrariesToProject
