BeforeAll {
  Import-Module (Join-Path $PSScriptRoot '..\scripts\lib\Yaml.psm1') -Force
  $BuildsPath = Join-Path $PSScriptRoot '..\builds.yaml'
}

Describe 'repository build configuration' {
  It 'builds all configured data packages for three Weasel variants' {
    $config = Read-BuildsYaml -Path $BuildsPath
    $matrix = @(Expand-BuildMatrix -Config $config)

    $config.datas.Count | Should -Be 2
    $config.weasels.Count | Should -Be 3
    $matrix.Count | Should -Be 6
  }

  It 'includes fxliang Weasel from its default pb branch' {
    $config = Read-BuildsYaml -Path $BuildsPath
    $fxliang = $config.weasels | Where-Object { $_.name -eq 'fxliang' }

    $fxliang | Should -Not -BeNullOrEmpty
    $fxliang.url | Should -Be 'https://github.com/fxliang/weasel.git'
    $fxliang.ref | Should -Be 'pb'
  }
}
