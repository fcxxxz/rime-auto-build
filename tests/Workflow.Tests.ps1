BeforeAll {
  $WorkflowPath = Join-Path $PSScriptRoot '..\.github\workflows\build.yml'
  $WatchWorkflowPath = Join-Path $PSScriptRoot '..\.github\workflows\watch.yml'
  $PackPath = Join-Path $PSScriptRoot '..\pack.ps1'
  $PrepareBoostPath = Join-Path $PSScriptRoot '..\scripts\prepare-boost.ps1'
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
    $content | Should -Match 'build\.bat boost'
    $content | Should -Match 'bin\.v2'
  }

  It 'keeps missing-library checks as arrays when no library is missing' {
    $content = Get-Content -LiteralPath $PrepareBoostPath -Raw

    ([regex]::Matches($content, '\$missingBoost\s*=\s*@\(Get-MissingBoostLibraries \$BoostRoot\)')).Count |
      Should -Be 2
  }

  It 'uses a new prepared Boost cache generation after toolchain alignment changes' {
    $content = Get-Content -LiteralPath $WorkflowPath -Raw

    $content | Should -Match 'static-v2'
  }
}

Describe 'build workflow Windows toolchain' {
  It 'pins the build job to Windows Server 2022 for VS 2022 and Boost vc143 compatibility' {
    $content = Get-Content -LiteralPath $WorkflowPath -Raw

    $content | Should -Match '(?s)build:\s+needs: plan.*?runs-on:\s*windows-2022'
  }
}

Describe 'pack script Boost preparation' {
  It 'keeps the Boost preparation developer prompt on x86 so build.bat boost can produce both Win32 and x64 libraries' {
    $content = Get-Content -LiteralPath $PackPath -Raw

    $content | Should -Match '(?s)\$boostVsDevCmdCall\s*=\s*New-VsDevCmdCall.*?-Architecture x86\s*`.*?-HostArchitecture x86'
  }
}
