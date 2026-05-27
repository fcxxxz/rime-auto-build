BeforeAll {
  $ModulePath = Join-Path $PSScriptRoot '..\scripts\lib\Yaml.psm1'
  Import-Module $ModulePath -Force
  $FixturePath = Join-Path $PSScriptRoot 'fixtures\builds.yaml'
}

Describe 'Read-BuildsYaml' {
  It 'parses weasels' {
    $config = Read-BuildsYaml -Path $FixturePath
    $config.weasels.Count | Should -Be 2
    $config.weasels[0].name | Should -Be 'official'
    $config.weasels[0].url  | Should -Be 'https://github.com/rime/weasel.git'
    $config.weasels[0].ref  | Should -Be 'master'
  }

  It 'parses datas' {
    $config = Read-BuildsYaml -Path $FixturePath
    $config.datas.Count | Should -Be 2
    $config.datas[1].name | Should -Be 'moqi'
  }

  It 'parses excludes' {
    $config = Read-BuildsYaml -Path $FixturePath
    $config.excludes.Count | Should -Be 1
    $config.excludes[0].data   | Should -Be 'moqi'
    $config.excludes[0].weasel | Should -Be 'official'
  }

  It 'defaults excludes to empty array if missing' {
    $tmp = New-TemporaryFile
    @'
weasels:
  - { name: a, url: x, ref: main }
datas:
  - { name: b, url: y, ref: main }
'@ | Set-Content $tmp.FullName
    try {
      $config = Read-BuildsYaml -Path $tmp.FullName
      $config.excludes | Should -BeOfType ([System.Collections.IList])
      $config.excludes.Count | Should -Be 0
    } finally { Remove-Item $tmp.FullName -Force }
  }

  It 'throws on duplicate weasel name' {
    $tmp = New-TemporaryFile
    @'
weasels:
  - { name: a, url: x, ref: main }
  - { name: a, url: y, ref: main }
datas:
  - { name: b, url: z, ref: main }
'@ | Set-Content $tmp.FullName
    try {
      { Read-BuildsYaml -Path $tmp.FullName } | Should -Throw -ExpectedMessage '*duplicate weasel*'
    } finally { Remove-Item $tmp.FullName -Force }
  }
}

Describe 'Expand-BuildMatrix' {
  It 'returns cartesian product minus excludes' {
    $config = Read-BuildsYaml -Path $FixturePath
    $matrix = Expand-BuildMatrix -Config $config
    # 2 weasels x 2 datas = 4, minus 1 exclude = 3
    $matrix.Count | Should -Be 3
    ($matrix | Where-Object { $_.data_name -eq 'moqi' -and $_.weasel_name -eq 'official' }).Count | Should -Be 0
    ($matrix | Where-Object { $_.data_name -eq 'tiger' -and $_.weasel_name -eq 'official' }).Count | Should -Be 1
  }

  It 'each entry has required fields' {
    $config = Read-BuildsYaml -Path $FixturePath
    $matrix = Expand-BuildMatrix -Config $config
    foreach ($e in $matrix) {
      $e.data_name   | Should -Not -BeNullOrEmpty
      $e.data_url    | Should -Not -BeNullOrEmpty
      $e.data_ref    | Should -Not -BeNullOrEmpty
      $e.weasel_name | Should -Not -BeNullOrEmpty
      $e.weasel_url  | Should -Not -BeNullOrEmpty
      $e.weasel_ref  | Should -Not -BeNullOrEmpty
    }
  }
}
