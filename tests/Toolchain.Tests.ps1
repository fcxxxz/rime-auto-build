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

  It 'can request a 32-bit host environment for Boost.Build' {
    New-VsDevCmdCall -VsDevCmd 'C:\VS\Common7\Tools\VsDevCmd.bat' -MsvcToolsVersion '14.51.36231' -Architecture x86 -HostArchitecture x86 |
      Should -Be 'call "C:\VS\Common7\Tools\VsDevCmd.bat" -arch=x86 -host_arch=x86 -vcvars_ver=14.51'
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
  It 'reports Boost 1.84 static libraries missing from stage lib' {
    $root = Join-Path $TestDrive 'boost_1_84_0'
    New-Item -ItemType Directory -Path (Join-Path $root 'stage\lib') -Force | Out-Null

    $missing = Get-MissingBoostLibraries $root

    $missing | Should -Contain 'libboost_thread-vc143-mt-s-x64-1_84.lib'
    $missing | Should -Contain 'libboost_thread-vc143-mt-s-x32-1_84.lib'
    $missing | Should -Contain 'libboost_chrono-vc143-mt-s-x32-1_84.lib'
    $missing | Should -Contain 'libboost_wserialization-vc143-mt-s-x64-1_84.lib'
    $missing.Count | Should -Be 20
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

Describe 'Get-BoostLinkLibraries' {
  It 'returns arch-specific Boost release libraries needed by Weasel link consumers' {
    Get-BoostLinkLibraries 'x32' | Should -Be @(
      'libboost_filesystem-vc143-mt-s-x32-1_84.lib',
      'libboost_json-vc143-mt-s-x32-1_84.lib',
      'libboost_locale-vc143-mt-s-x32-1_84.lib',
      'libboost_regex-vc143-mt-s-x32-1_84.lib',
      'libboost_serialization-vc143-mt-s-x32-1_84.lib',
      'libboost_system-vc143-mt-s-x32-1_84.lib',
      'libboost_wserialization-vc143-mt-s-x32-1_84.lib',
      'libboost_thread-vc143-mt-s-x32-1_84.lib',
      'libboost_chrono-vc143-mt-s-x32-1_84.lib',
      'libboost_atomic-vc143-mt-s-x32-1_84.lib'
    )

    Get-BoostLinkLibraries 'x64' | Should -Contain 'libboost_thread-vc143-mt-s-x64-1_84.lib'
  }
}

Describe 'Add-BoostLinkLibrariesToProject' {
  It 'forces Win32 Boost static libraries with full-path whole-archive options and keeps x64 default libraries' {
    $projectPath = Join-Path $TestDrive 'WeaselServer.vcxproj'
    [System.IO.File]::WriteAllText(
      $projectPath,
      @'
<Project DefaultTargets="Build" xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
  <ItemDefinitionGroup Condition="'$(Configuration)|$(Platform)'=='Release|Win32'">
    <Link>
      <AdditionalOptions>/WHOLEARCHIVE:libboost_thread-vc143-mt-s-x32-1_84.lib /DEFAULTLIB:libboost_serialization-vc143-mt-s-x32-1_84.lib %(AdditionalOptions)</AdditionalOptions>
      <AdditionalDependencies>libboost_thread-vc143-mt-s-x32-1_84.lib;imm32.lib;%(AdditionalDependencies)</AdditionalDependencies>
    </Link>
  </ItemDefinitionGroup>
  <ItemDefinitionGroup Condition="'$(Configuration)|$(Platform)'=='Release|x64'">
    <Link>
      <AdditionalOptions>/DEBUG %(AdditionalOptions)</AdditionalOptions>
      <AdditionalDependencies>imm32.lib;libboost_thread-vc143-mt-s-x64-1_84.lib;%(AdditionalDependencies)</AdditionalDependencies>
    </Link>
  </ItemDefinitionGroup>
  <ItemDefinitionGroup Condition="'$(Configuration)|$(Platform)'=='Debug|Win32'">
    <Link>
      <AdditionalDependencies>debug.lib;%(AdditionalDependencies)</AdditionalDependencies>
    </Link>
  </ItemDefinitionGroup>
</Project>
'@,
      [System.Text.Encoding]::UTF8
    )

    Add-BoostLinkLibrariesToProject $projectPath
    Add-BoostLinkLibrariesToProject $projectPath

    $content = Get-Content -LiteralPath $projectPath -Raw
    $content | Should -Match '/WHOLEARCHIVE:"\$\(BOOST_ROOT\)\\stage\\lib\\libboost_filesystem-vc143-mt-s-x32-1_84\.lib" /WHOLEARCHIVE:"\$\(BOOST_ROOT\)\\stage\\lib\\libboost_json-vc143-mt-s-x32-1_84\.lib" /WHOLEARCHIVE:"\$\(BOOST_ROOT\)\\stage\\lib\\libboost_locale-vc143-mt-s-x32-1_84\.lib" /WHOLEARCHIVE:"\$\(BOOST_ROOT\)\\stage\\lib\\libboost_regex-vc143-mt-s-x32-1_84\.lib" /WHOLEARCHIVE:"\$\(BOOST_ROOT\)\\stage\\lib\\libboost_serialization-vc143-mt-s-x32-1_84\.lib" /WHOLEARCHIVE:"\$\(BOOST_ROOT\)\\stage\\lib\\libboost_system-vc143-mt-s-x32-1_84\.lib" /WHOLEARCHIVE:"\$\(BOOST_ROOT\)\\stage\\lib\\libboost_wserialization-vc143-mt-s-x32-1_84\.lib" /WHOLEARCHIVE:"\$\(BOOST_ROOT\)\\stage\\lib\\libboost_thread-vc143-mt-s-x32-1_84\.lib" /WHOLEARCHIVE:"\$\(BOOST_ROOT\)\\stage\\lib\\libboost_chrono-vc143-mt-s-x32-1_84\.lib" /WHOLEARCHIVE:"\$\(BOOST_ROOT\)\\stage\\lib\\libboost_atomic-vc143-mt-s-x32-1_84\.lib" %\(AdditionalOptions\)'
    $content | Should -Match '/DEBUG /DEFAULTLIB:libboost_filesystem-vc143-mt-s-x64-1_84\.lib /DEFAULTLIB:libboost_json-vc143-mt-s-x64-1_84\.lib /DEFAULTLIB:libboost_locale-vc143-mt-s-x64-1_84\.lib /DEFAULTLIB:libboost_regex-vc143-mt-s-x64-1_84\.lib /DEFAULTLIB:libboost_serialization-vc143-mt-s-x64-1_84\.lib /DEFAULTLIB:libboost_system-vc143-mt-s-x64-1_84\.lib /DEFAULTLIB:libboost_wserialization-vc143-mt-s-x64-1_84\.lib /DEFAULTLIB:libboost_thread-vc143-mt-s-x64-1_84\.lib /DEFAULTLIB:libboost_chrono-vc143-mt-s-x64-1_84\.lib /DEFAULTLIB:libboost_atomic-vc143-mt-s-x64-1_84\.lib %\(AdditionalOptions\)'
    $content | Should -Not -Match '<AdditionalDependencies>[^<]*libboost_'
    $content | Should -Not -Match '/DEFAULTLIB:libboost_thread-vc143-mt-s-x32-1_84\.lib'
    $content | Should -Not -Match '/DEFAULTLIB:libboost_serialization-vc143-mt-s-x32-1_84\.lib'
    $content | Should -Not -Match '/WHOLEARCHIVE:libboost_thread-vc143-mt-s-x32-1_84\.lib'
    $content | Should -Not -Match '\s+libboost_thread-vc143-mt-s-x32-1_84\.lib\s+'
    ([regex]::Matches($content, '/DEFAULTLIB:libboost_thread-vc143-mt-s-x64-1_84\.lib')).Count | Should -Be 1
    ([regex]::Matches($content, '/WHOLEARCHIVE:"\$\(BOOST_ROOT\)\\stage\\lib\\libboost_thread-vc143-mt-s-x32-1_84\.lib"')).Count | Should -Be 1
    $content | Should -Match 'debug\.lib;%\(AdditionalDependencies\)'
  }
}

Describe 'New-BoostProjectConfig' {
  It 'pins Boost.Build msvc-14.3 to the 32-bit MSVC compiler path' {
    New-BoostProjectConfig 'C:\VS\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe' |
      Should -Be 'using msvc : 14.3 : "C:\VS\VC\Tools\MSVC\14.51.36231\bin\HostX86\x86\cl.exe" ;'
  }

  It 'keeps non-standard compiler invocations unchanged' {
    New-BoostProjectConfig 'C:\toolchains\msvc-wrapper.cmd' |
      Should -Be 'using msvc : 14.3 : "C:\toolchains\msvc-wrapper.cmd" ;'
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
