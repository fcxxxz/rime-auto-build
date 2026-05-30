BeforeAll {
  $ModulePath = Join-Path $PSScriptRoot '..\scripts\lib\LibrimeCache.psm1'
  Import-Module $ModulePath -Force
}

Describe 'Get-LibrimeCacheRelativePaths' {
  It 'contains only cacheable librime build outputs needed by pack.ps1' {
    $paths = @(Get-LibrimeCacheRelativePaths)

    $paths | Should -Contain 'include\rime_api.h'
    $paths | Should -Contain 'include\rime_api_deprecated.h'
    $paths | Should -Contain 'include\rime_api_stdbool.h'
    $paths | Should -Contain 'include\rime_levers_api.h'
    $paths | Should -Contain 'librime\bin\opencc_dict.exe'
    $paths | Should -Contain 'lib64\rime.lib'
    $paths | Should -Contain 'lib\rime.lib'
    $paths | Should -Contain 'output\rime.dll'
    $paths | Should -Contain 'output\rime.pdb'
    $paths | Should -Contain 'output\Win32\rime.dll'
    $paths | Should -Contain 'output\Win32\rime.pdb'
    $paths | Should -Contain 'output\data\opencc\TSCharacters.ocd2'

    $paths | Should -Not -Contain 'output\install.nsi'
    $paths | Should -Not -Contain 'output\data\weasel-custom-data.txt'
    $paths | Should -Not -Contain 'output\archives'
  }
}

Describe 'Copy-LibrimeCacheOutputs' {
  BeforeEach {
    $SourceRoot = Join-Path $TestDrive 'work-weasel'
    $DestinationRoot = Join-Path $TestDrive 'source-weasel'
    New-Item -ItemType Directory -Path $SourceRoot,$DestinationRoot -Force | Out-Null
  }

  It 'copies existing librime outputs while skipping missing optional files' {
    $requiredFiles = @(
      'include\rime_api.h',
      'include\rime_api_deprecated.h',
      'include\rime_api_stdbool.h',
      'include\rime_levers_api.h',
      'librime\bin\opencc_dict.exe',
      'lib64\rime.lib',
      'lib\rime.lib',
      'output\rime.dll',
      'output\Win32\rime.dll',
      'output\data\opencc\TSCharacters.ocd2'
    )

    foreach ($rel in $requiredFiles) {
      $path = Join-Path $SourceRoot $rel
      New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force | Out-Null
      Set-Content -LiteralPath $path -Value $rel -NoNewline -Encoding ASCII
    }

    $copied = @(Copy-LibrimeCacheOutputs -SourceWeaselRoot $SourceRoot -DestinationWeaselRoot $DestinationRoot)

    $copied | Should -Contain 'include\rime_api.h'
    $copied | Should -Contain 'librime\bin\opencc_dict.exe'
    $copied | Should -Contain 'output\data\opencc\TSCharacters.ocd2'
    Test-Path -LiteralPath (Join-Path $DestinationRoot 'output\Win32\rime.dll') | Should -BeTrue
    Test-Path -LiteralPath (Join-Path $DestinationRoot 'output\rime.pdb') | Should -BeFalse
  }
}
