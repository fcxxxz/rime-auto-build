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
  It 'maps Visual Studio 2026 numeric install paths to v145' {
    $toolset = Get-DefaultToolsetForVsDevCmd 'C:\Program Files\Microsoft Visual Studio\18\Enterprise\Common7\Tools\VsDevCmd.bat'
    $toolset.Platform | Should -Be 'v145'
    $toolset.Bjam | Should -Be 'msvc-14.5'
  }

  It 'maps Visual Studio 2026 year install paths to v145' {
    $toolset = Get-DefaultToolsetForVsDevCmd 'C:\Program Files\Microsoft Visual Studio\2026\Enterprise\Common7\Tools\VsDevCmd.bat'
    $toolset.Platform | Should -Be 'v145'
    $toolset.Bjam | Should -Be 'msvc-14.5'
  }

  It 'keeps Visual Studio 2022 on v143' {
    $toolset = Get-DefaultToolsetForVsDevCmd 'C:\Program Files\Microsoft Visual Studio\2022\BuildTools\Common7\Tools\VsDevCmd.bat'
    $toolset.Platform | Should -Be 'v143'
    $toolset.Bjam | Should -Be 'msvc-14.3'
  }
}
