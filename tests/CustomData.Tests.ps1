BeforeAll {
  $ModulePath = Join-Path $PSScriptRoot '..\scripts\lib\CustomData.psm1'
  Import-Module $ModulePath -Force
}

Describe 'custom-data file copying' {
  BeforeEach {
    $TestRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("rime-custom-data-test-" + [guid]::NewGuid().ToString('N'))
    $CustomRoot = Join-Path $TestRoot 'custom-data'
    $OutputRoot = Join-Path $TestRoot 'output-data'
    New-Item -ItemType Directory -Path (Join-Path $CustomRoot 'tools\data') -Force | Out-Null
    New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null
  }

  AfterEach {
    if (Test-Path -LiteralPath $TestRoot) {
      Remove-Item -LiteralPath $TestRoot -Recurse -Force
    }
  }

  It 'skips unresolved custom-data symlinks instead of failing the package' {
    $linkPath = Join-Path $CustomRoot 'tools\data\zrmdb.txt'
    $link = [pscustomobject]@{
      FullName = $linkPath
      Attributes = [System.IO.FileAttributes]::ReparsePoint
      Target = '..\..\lua\zrmdb.txt'
    }

    $result = Copy-PackCustomDataFile -File $link -CustomRoot $CustomRoot -OutputData $OutputRoot

    $result | Should -BeNullOrEmpty
    Test-Path -LiteralPath (Join-Path $OutputRoot 'tools\data\zrmdb.txt') | Should -BeFalse
  }

  It 'materializes resolvable custom-data symlinks as regular packaged files' {
    $targetDir = Join-Path $CustomRoot 'lua'
    New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
    $targetPath = Join-Path $targetDir 'zrmdb.txt'
    Set-Content -LiteralPath $targetPath -Value 'resolved-content' -NoNewline -Encoding UTF8

    $linkPath = Join-Path $CustomRoot 'tools\data\zrmdb.txt'
    $link = [pscustomobject]@{
      FullName = $linkPath
      Attributes = [System.IO.FileAttributes]::ReparsePoint
      Target = '..\..\lua\zrmdb.txt'
    }

    $result = Copy-PackCustomDataFile -File $link -CustomRoot $CustomRoot -OutputData $OutputRoot

    $result | Should -Be 'tools/data/zrmdb.txt'
    Get-Content -LiteralPath (Join-Path $OutputRoot 'tools\data\zrmdb.txt') -Raw | Should -Be 'resolved-content'
  }
}
