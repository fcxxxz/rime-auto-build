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
  It 'adds Boost libraries as tail link inputs after project libraries' {
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

    $xml = [xml](Get-Content -LiteralPath $projectPath -Raw)
    $ns = New-Object System.Xml.XmlNamespaceManager($xml.NameTable)
    $ns.AddNamespace('msb', 'http://schemas.microsoft.com/developer/msbuild/2003')

    foreach ($case in @(
      @{ Platform = 'Win32'; Arch = 'x32'; Existing = 'imm32.lib' },
      @{ Platform = 'x64'; Arch = 'x64'; Existing = 'imm32.lib' }
    )) {
      $group = $xml.SelectSingleNode("//msb:ItemDefinitionGroup[@Condition=`"`'`$(Configuration)|`$(Platform)`'==`'Release|$($case.Platform)`'`"]", $ns)
      $expectedDependencies = @(($case.Existing, '%(AdditionalDependencies)') -join ';')
      $expectedOptions = '%(AdditionalOptions)'
      if ($case.Platform -eq 'x64') {
        $expectedOptions = "/DEBUG $expectedOptions"
      }

      $group.Link.AdditionalDependencies | Should -Be $expectedDependencies
      $group.Link.AdditionalOptions | Should -Be $expectedOptions
      $group.Link.AdditionalDependencies | Should -Not -Match 'libboost_'
      $group.Link.AdditionalOptions | Should -Not -Match 'libboost_'
    }

    $tailTarget = $xml.SelectSingleNode("//msb:Target[@Name='AddBoostTailLinkInputs']", $ns)
    $tailTarget | Should -Not -BeNullOrEmpty
    $tailTarget.GetAttribute('BeforeTargets') | Should -Be 'Link'

    foreach ($case in @(
      @{ Platform = 'Win32'; Arch = 'x32' },
      @{ Platform = 'x64'; Arch = 'x64' }
    )) {
      $items = @($tailTarget.SelectNodes(
          "msb:ItemGroup[@Condition=`"`'`$(Configuration)|`$(Platform)`'==`'Release|$($case.Platform)`'`"]/msb:Link",
          $ns
        ))
      $items.Count | Should -Be 10
      $items[0].GetAttribute('Include') | Should -Be "`$(BOOST_ROOT)\stage\lib\libboost_filesystem-vc143-mt-s-$($case.Arch)-1_84.lib"
      $items[-1].GetAttribute('Include') | Should -Be "`$(BOOST_ROOT)\stage\lib\libboost_atomic-vc143-mt-s-$($case.Arch)-1_84.lib"
      (@($items | Where-Object { $_.GetAttribute('Include') -like '*libboost_thread*' })).Count | Should -Be 1
    }

    $debugGroup = $xml.SelectSingleNode("//msb:ItemDefinitionGroup[@Condition=`"`'`$(Configuration)|`$(Platform)`'==`'Debug|Win32`'`"]", $ns)
    $debugGroup.Link.AdditionalDependencies | Should -Be 'debug.lib;%(AdditionalDependencies)'
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
