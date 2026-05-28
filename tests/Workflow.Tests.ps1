BeforeAll {
  $WorkflowPath = Join-Path $PSScriptRoot '..\.github\workflows\build.yml'
  $WatchWorkflowPath = Join-Path $PSScriptRoot '..\.github\workflows\watch.yml'
  $PackPath = Join-Path $PSScriptRoot '..\pack.ps1'
  $PrepareBoostPath = Join-Path $PSScriptRoot '..\scripts\prepare-boost.ps1'
  $SaveLibrimeCachePath = Join-Path $PSScriptRoot '..\scripts\save-librime-cache.ps1'
}

Describe 'workflow YAML parsing' {
  It 'does not install powershell-yaml from PSGallery during CI planning' {
    $content = @(
      Get-Content -LiteralPath $WorkflowPath -Raw
      Get-Content -LiteralPath $WatchWorkflowPath -Raw
    ) -join "`n"

    $content | Should -Not -Match 'Install powershell-yaml'
    $content | Should -Not -Match 'Install-Module -Name powershell-yaml'
  }
}

Describe 'build workflow Boost cache' {
  It 'saves prepared Boost cache before installer-only dependencies and pack.ps1' {
    $content = Get-Content -LiteralPath $WorkflowPath -Raw

    $restore = $content.IndexOf('uses: actions/cache/restore@v4', [StringComparison]::Ordinal)
    $prepare = $content.IndexOf('name: Prepare Boost static libraries', [StringComparison]::Ordinal)
    $save = $content.IndexOf('uses: actions/cache/save@v4', [StringComparison]::Ordinal)
    $nsis = $content.IndexOf('name: Install NSIS', [StringComparison]::Ordinal)
    $pack = $content.IndexOf('name: Run pack.ps1', [StringComparison]::Ordinal)

    $restore | Should -BeGreaterOrEqual 0
    $prepare | Should -BeGreaterThan $restore
    $save | Should -BeGreaterThan $prepare
    $nsis | Should -BeGreaterThan $save
    $pack | Should -BeGreaterThan $save
  }

  It 'can restore the previous source-only Boost cache as a fallback' {
    $content = Get-Content -LiteralPath $WorkflowPath -Raw

    $content | Should -Match 'restore-keys:'
    $content | Should -Match 'boost-1\.84\.0-source-only-v1'
  }

  It 'uses a dedicated Boost preparation script for cacheable static libraries' {
    Test-Path -LiteralPath $PrepareBoostPath | Should -BeTrue
    $content = Get-Content -LiteralPath $PrepareBoostPath -Raw

    $content | Should -Match 'Get-MissingBoostLibraries'
    $content | Should -Match 'Get-BoostBuildArchitectures'
    $content | Should -Match 'Get-BoostBjamOptions'
    $content | Should -Not -Match 'build\.bat boost'
    $content | Should -Match 'bin\.v2'
  }

  It 'keeps missing-library checks as arrays when no library is missing' {
    $content = Get-Content -LiteralPath $PrepareBoostPath -Raw

    ([regex]::Matches($content, '\$missingBoost\s*=\s*@\(Get-MissingBoostLibraries \$BoostRoot\)')).Count |
      Should -Be 2
  }

  It 'uses a new prepared Boost cache generation after toolchain alignment changes' {
    $content = Get-Content -LiteralPath $WorkflowPath -Raw

    $content | Should -Match 'static-v3'
  }
}

Describe 'build workflow librime cache' {
  It 'restores librime outputs before pack.ps1 and saves them after a successful pack' {
    $content = Get-Content -LiteralPath $WorkflowPath -Raw

    $restore = $content.IndexOf('name: Restore librime cache', [StringComparison]::Ordinal)
    $pack = $content.IndexOf('name: Run pack.ps1', [StringComparison]::Ordinal)
    $sync = $content.IndexOf('name: Sync librime outputs for cache', [StringComparison]::Ordinal)
    $save = $content.IndexOf('name: Save librime cache', [StringComparison]::Ordinal)

    $restore | Should -BeGreaterOrEqual 0
    $pack | Should -BeGreaterThan $restore
    $sync | Should -BeGreaterThan $pack
    $save | Should -BeGreaterThan $sync
  }

  It 'keys librime cache by source revisions and selected MSVC toolset' {
    $content = Get-Content -LiteralPath $WorkflowPath -Raw

    $content | Should -Match 'id:\s*librime-rev'
    $content | Should -Match 'git -C weasel/librime rev-parse HEAD'
    $content | Should -Match 'sdk_version='
    $content | Should -Match 'librime-\$\{\{ runner\.os \}\}-weasel-\$\{\{ steps\.weasel-rev\.outputs\.sha \}\}-librime-\$\{\{ steps\.librime-rev\.outputs\.sha \}\}-msvc-\$\{\{ steps\.msvc\.outputs\.msvc_tools_version \}\}-sdk-\$\{\{ steps\.msvc\.outputs\.sdk_version \}\}-boost-static-v3-v1'
    $content | Should -Not -Match '(?m)^\s+weasel/output/data/opencc\s*$'
  }

  It 'uses a dedicated script to sync only cacheable librime outputs' {
    Test-Path -LiteralPath $SaveLibrimeCachePath | Should -BeTrue
    $content = Get-Content -LiteralPath $SaveLibrimeCachePath -Raw

    $content | Should -Match 'Copy-LibrimeCacheOutputs'
    $content | Should -Match '\.pack-work\\weasel'
    $content | Should -Match '\.\\weasel'
  }
}

Describe 'build workflow Windows toolchain' {
  It 'pins the build job to Windows Server 2022 for VS 2022 and Boost vc143 compatibility' {
    $content = Get-Content -LiteralPath $WorkflowPath -Raw

    $content | Should -Match '(?s)build:\s+needs: plan.*?runs-on:\s*windows-2022'
  }
}

Describe 'build workflow data checkout' {
  It 'enables symlink checkout for data repositories on Windows' {
    $content = Get-Content -LiteralPath $WorkflowPath -Raw

    $content | Should -Match 'git -c core\.symlinks=true clone --depth 1 -b \$\{\{ matrix\.data_ref \}\} \$\{\{ matrix\.data_url \}\} custom-data'
  }
}

Describe 'pack script Boost preparation' {
  It 'builds Boost libraries with target-matching Visual Studio prompts' {
    $content = Get-Content -LiteralPath $PackPath -Raw

    $content | Should -Match 'Get-BoostBuildArchitectures'
    $content | Should -Match 'Get-BoostBjamOptions'
    $content | Should -Not -Match '(?s)\$boostVsDevCmdCall\s*=\s*New-VsDevCmdCall.*?-Architecture x86\s*`.*?-HostArchitecture x86'
  }
}
