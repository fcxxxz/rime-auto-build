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
        [AllowEmptyString()][string]$MsvcToolsVersion,

        [ValidateSet('x86', 'amd64')]
        [string]$Architecture = 'amd64',

        [ValidateSet('x86', 'amd64')]
        [string]$HostArchitecture = 'amd64'
    )

    $call = "call `"$VsDevCmd`" -arch=$Architecture -host_arch=$HostArchitecture"
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

function Get-BoostBuildArchitectures {
    return @(
        [pscustomobject]@{
            Architecture = 'x32'
            VsArchitecture = 'x86'
            HostArchitecture = 'x86'
            BjamArchitecture = 'x86'
            AddressModel = '32'
        }
        [pscustomobject]@{
            Architecture = 'x64'
            VsArchitecture = 'amd64'
            HostArchitecture = 'amd64'
            BjamArchitecture = 'x86'
            AddressModel = '64'
        }
    )
}

function Get-BoostBuildArchitecture {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('x32', 'x64')]
        [string]$Architecture
    )

    foreach ($case in Get-BoostBuildArchitectures) {
        if ($case.Architecture -eq $Architecture) {
            return $case
        }
    }
    throw "Unsupported Boost architecture '$Architecture'."
}

function Get-BoostBjamOptions {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('x32', 'x64')]
        [string]$Architecture,

        [Parameter(Mandatory)]
        [string]$BjamToolset,

        [int]$JobCount = 0
    )

    if ($JobCount -le 0) {
        $processorCount = [Environment]::GetEnvironmentVariable('NUMBER_OF_PROCESSORS')
        if ([string]::IsNullOrWhiteSpace($processorCount)) {
            $processorCount = [Environment]::ProcessorCount
        }
        $JobCount = [Math]::Max(1, [int]$processorCount)
    }

    $case = Get-BoostBuildArchitecture $Architecture
    return @(
        "-j$JobCount",
        'variant=release',
        'threading=multi',
        '--with-filesystem',
        '--with-json',
        '--with-locale',
        '--with-regex',
        '--with-serialization',
        '--with-system',
        '--with-thread',
        '--with-chrono',
        '--with-atomic',
        'define=BOOST_USE_WINAPI_VERSION=0x0603',
        "toolset=$BjamToolset",
        'link=static',
        'runtime-link=static',
        "architecture=$($case.BjamArchitecture)",
        "address-model=$($case.AddressModel)"
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

    return Get-BoostWholeArchiveOptions $Architecture
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

function Add-BoostLibrariesToDependencies {
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$AdditionalDependencies,
        [Parameter(Mandatory)][string[]]$Libraries
    )

    $items = New-Object System.Collections.Generic.List[string]
    $seen = New-Object System.Collections.Generic.HashSet[string]([StringComparer]::OrdinalIgnoreCase)

    foreach ($lib in $Libraries) {
        if ($seen.Add($lib)) {
            $items.Add($lib)
        }
    }

    foreach ($item in ($AdditionalDependencies -split ';')) {
        if ([string]::IsNullOrWhiteSpace($item)) {
            continue
        }
        $trimmed = $item.Trim()
        if ($seen.Add($trimmed)) {
            $items.Add($trimmed)
        }
    }

    return ($items -join ';')
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

function Remove-BoostLibrariesFromDependencies {
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$AdditionalDependencies
    )

    $items = New-Object System.Collections.Generic.List[string]
    foreach ($item in ($AdditionalDependencies -split ';')) {
        if ([string]::IsNullOrWhiteSpace($item)) {
            continue
        }
        $trimmed = $item.Trim()
        if ($trimmed -match '^(?:.*[\\/])?libboost_[^"\s;]+\.lib"?$') {
            continue
        }
        $items.Add($trimmed)
    }

    return ($items -join ';')
}

function Ensure-InheritedLinkOptions {
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$AdditionalOptions
    )

    $current = $AdditionalOptions.Trim()
    if ([string]::IsNullOrWhiteSpace($current)) {
        return '%(AdditionalOptions)'
    }
    if ($current -notmatch [regex]::Escape('%(AdditionalOptions)')) {
        return "$current %(AdditionalOptions)"
    }
    return $current
}

function Add-BoostTailLinkInputsToProject {
    param(
        [Parameter(Mandatory)][xml]$ProjectXml,
        [Parameter(Mandatory)]$NamespaceManager
    )

    $project = $ProjectXml.DocumentElement
    $target = $ProjectXml.SelectSingleNode("//msb:Target[@Name='AddBoostTailLinkInputs']", $NamespaceManager)
    if ($target) {
        [void]$project.RemoveChild($target)
    }

    $target = $ProjectXml.CreateElement('Target', $project.NamespaceURI)
    [void]$target.SetAttribute('Name', 'AddBoostTailLinkInputs')
    [void]$target.SetAttribute('BeforeTargets', 'Link')

    foreach ($case in @(
        @{ Platform = 'Win32'; Arch = 'x32' },
        @{ Platform = 'x64'; Arch = 'x64' }
    )) {
        $itemGroup = $ProjectXml.CreateElement('ItemGroup', $project.NamespaceURI)
        [void]$itemGroup.SetAttribute('Condition', "'`$(Configuration)|`$(Platform)'=='Release|$($case.Platform)'")

        foreach ($library in Get-BoostLinkLibraries $case.Arch) {
            $linkItem = $ProjectXml.CreateElement('Link', $project.NamespaceURI)
            [void]$linkItem.SetAttribute('Include', "`$(BOOST_ROOT)\stage\lib\$library")
            [void]$itemGroup.AppendChild($linkItem)
        }

        [void]$target.AppendChild($itemGroup)
    }

    [void]$project.AppendChild($target)
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

        $additionalOptions = $link.SelectSingleNode('msb:AdditionalOptions', $ns)
        if (-not $additionalOptions) {
            $additionalOptions = $xml.CreateElement('AdditionalOptions', $xml.DocumentElement.NamespaceURI)
            [void]$link.AppendChild($additionalOptions)
        }

        $cleanOptions = Remove-BoostOptionsFromAdditionalOptions `
            -AdditionalOptions $additionalOptions.InnerText
        $updatedOptions = Ensure-InheritedLinkOptions `
            -AdditionalOptions $cleanOptions
        if ($additionalOptions.InnerText -ne $updatedOptions) {
            $additionalOptions.InnerText = $updatedOptions
            $changed = $true
        }

        $additional = $link.SelectSingleNode('msb:AdditionalDependencies', $ns)
        if (-not $additional) {
            $additional = $xml.CreateElement('AdditionalDependencies', $xml.DocumentElement.NamespaceURI)
            [void]$link.AppendChild($additional)
        }

        $updated = Remove-BoostLibrariesFromDependencies `
            -AdditionalDependencies $additional.InnerText
        if ($additional.InnerText -ne $updated) {
            $additional.InnerText = $updated
            $changed = $true
        }
    }

    Add-BoostTailLinkInputsToProject -ProjectXml $xml -NamespaceManager $ns
    $changed = $true

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

Export-ModuleMember -Function ConvertTo-VcvarsVersion, New-VsDevCmdCall, Get-DefaultToolsetForVsDevCmd, Get-BoostLinkLibraries, Get-BoostBuildArchitectures, Get-BoostBjamOptions, Get-ExpectedBoostLibraries, Get-MissingBoostLibraries, New-BoostProjectConfig, Select-ClPath, Add-BoostLinkLibrariesToProject
