BeforeAll {
  $ModulePath = Join-Path $PSScriptRoot '..\scripts\lib\Toolchain.psm1'
  Import-Module $ModulePath -Force
}

Describe 'ConvertTo-VcvarsVersion' {
  It 'keeps major and minor parts from a full MSVC tools version' {
    ConvertTo-VcvarsVersion '14.51.36231' | Should -Be '14.51'
  }

  It 'leaves an already-short vcvars version unchanged' {
    ConvertTo-VcvarsVersion '14.44' | Should -Be '14.44'
  }

  It 'returns null for empty input' {
    ConvertTo-VcvarsVersion '' | Should -BeNullOrEmpty
  }
}

Describe 'New-VsDevCmdCall' {
  It 'adds -vcvars_ver when an MSVC tools version is supplied' {
    New-VsDevCmdCall -VsDevCmd 'C:\VS\Common7\Tools\VsDevCmd.bat' -MsvcToolsVersion '14.51.36231' |
      Should -Be 'call "C:\VS\Common7\Tools\VsDevCmd.bat" -arch=amd64 -host_arch=amd64 -vcvars_ver=14.51'
  }

  It 'omits -vcvars_ver when no MSVC tools version is supplied' {
    New-VsDevCmdCall -VsDevCmd 'C:\VS\Common7\Tools\VsDevCmd.bat' |
      Should -Be 'call "C:\VS\Common7\Tools\VsDevCmd.bat" -arch=amd64 -host_arch=amd64'
  }
}

Describe 'Get-DefaultToolsetForVsDevCmd' {
  It 'maps Visual Studio 2026 numeric install paths to v145 and a Boost 1.84-compatible bjam toolset' {
    $toolset = Get-DefaultToolsetForVsDevCmd 'C:\Program Files\Microsoft Visual Studio\18\Enterprise\Common7\Tools\VsDevCmd.bat'
    $toolset.Platform | Should -Be 'v145'
    $toolset.Bjam | Should -Be 'msvc-14.3'
  }

  It 'maps Visual Studio 2026 year install paths to v145 and a Boost 1.84-compatible bjam toolset' {
    $toolset = Get-DefaultToolsetForVsDevCmd 'C:\Program Files\Microsoft Visual Studio\2026\Enterprise\Common7\Tools\VsDevCmd.bat'
    $toolset.Platform | Should -Be 'v145'
    $toolset.Bjam | Should -Be 'msvc-14.3'
  }

  It 'keeps Visual Studio 2022 on v143' {
    $toolset = Get-DefaultToolsetForVsDevCmd 'C:\Program Files\Microsoft Visual Studio\2022\BuildTools\Common7\Tools\VsDevCmd.bat'
    $toolset.Platform | Should -Be 'v143'
    $toolset.Bjam | Should -Be 'msvc-14.3'
  }
}

Describe 'Get-MissingBoostLibraries' {
  It 'reports Boost 1.84 x64 static libraries missing from stage lib' {
    $root = Join-Path $TestDrive 'boost_1_84_0'
    New-Item -ItemType Directory -Path (Join-Path $root 'stage\lib') -Force | Out-Null

    $missing = Get-MissingBoostLibraries $root

    $missing | Should -Contain 'libboost_thread-vc143-mt-s-x64-1_84.lib'
    $missing | Should -Contain 'libboost_wserialization-vc143-mt-s-x64-1_84.lib'
    $missing.Count | Should -Be 8
  }

  It 'returns no missing Boost libraries when the expected stage libs exist' {
    $root = Join-Path $TestDrive 'complete_boost_1_84_0'
    $stageLib = Join-Path $root 'stage\lib'
    New-Item -ItemType Directory -Path $stageLib -Force | Out-Null

    foreach ($name in Get-ExpectedBoostLibraries) {
      New-Item -ItemType File -Path (Join-Path $stageLib $name) | Out-Null
    }

    Get-MissingBoostLibraries $root | Should -BeNullOrEmpty
  }
}

Describe 'New-BoostProjectConfig' {
  It 'pins Boost.Build msvc-14.3 to the compiler selected by VsDevCmd' {
    New-BoostProjectConfig 'C:\VS\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe' |
      Should -Be 'using msvc : 14.3 : "C:\VS\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe" ;'
  }
}

Describe 'Select-ClPath' {
  It 'ignores VsDevCmd banner output and returns the first cl.exe path' {
    $output = @(
      '**********************************************************************',
      '** Visual Studio 2026 Developer Command Prompt v18.6.0',
      '**********************************************************************',
      'C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\Hostx64\x64\cl.exe'
    )

    Select-ClPath $output |
      Should -Be 'C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\Hostx64\x64\cl.exe'
  }
}
