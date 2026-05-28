BeforeAll {
  $WorkflowPath = Join-Path $PSScriptRoot '..\.github\workflows\build.yml'
  $PrepareBoostPath = Join-Path $PSScriptRoot '..\scripts\prepare-boost.ps1'
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
}
