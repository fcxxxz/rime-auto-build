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

function Get-ExpectedBoostLibraries {
    return @(
        'libboost_filesystem-vc143-mt-s-x64-1_84.lib',
        'libboost_json-vc143-mt-s-x64-1_84.lib',
        'libboost_locale-vc143-mt-s-x64-1_84.lib',
        'libboost_regex-vc143-mt-s-x64-1_84.lib',
        'libboost_serialization-vc143-mt-s-x64-1_84.lib',
        'libboost_system-vc143-mt-s-x64-1_84.lib',
        'libboost_thread-vc143-mt-s-x64-1_84.lib',
        'libboost_wserialization-vc143-mt-s-x64-1_84.lib'
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

Export-ModuleMember -Function ConvertTo-VcvarsVersion, New-VsDevCmdCall, Get-DefaultToolsetForVsDevCmd, Get-ExpectedBoostLibraries, Get-MissingBoostLibraries, New-BoostProjectConfig, Select-ClPath
