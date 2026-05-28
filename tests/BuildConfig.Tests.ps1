BeforeAll {
  Import-Module (Join-Path $PSScriptRoot '..\scripts\lib\Yaml.psm1') -Force
  $BuildsPath = Join-Path $PSScriptRoot '..\builds.yaml'
}

Describe 'repository build configuration' {
  It 'builds all configured data packages for three Weasel variants' {
    $config = Read-BuildsYaml -Path $BuildsPath
    $matrix = @(Expand-BuildMatrix -Config $config)

    $config.datas.Count | Should -Be 4
    $config.weasels.Count | Should -Be 3
    $matrix.Count | Should -Be 12
  }

  It 'uses release-friendly names for official and qing Weasel variants' {
    $config = Read-BuildsYaml -Path $BuildsPath
    $rime = $config.weasels | Where-Object { $_.name -eq 'rime' }
    $qing = $config.weasels | Where-Object { $_.name -eq 'qing' }

    $rime | Should -Not -BeNullOrEmpty
    $rime.display | Should -Be '官方小狼毫'
    $rime.url | Should -Be 'https://github.com/rime/weasel.git'
    $rime.ref | Should -Be 'master'

    $qing | Should -Not -BeNullOrEmpty
    $qing.display | Should -Be '我的小狼毫'
    $qing.url | Should -Be 'https://github.com/a810439322/weasel.git'
    $qing.ref | Should -Be 'master'
  }

  It 'includes fxliang Weasel from its default pb branch' {
    $config = Read-BuildsYaml -Path $BuildsPath
    $fxliang = $config.weasels | Where-Object { $_.name -eq 'fxliang' }

    $fxliang | Should -Not -BeNullOrEmpty
    $fxliang.display | Should -Be 'fxliang 小狼毫'
    $fxliang.url | Should -Be 'https://github.com/fxliang/weasel.git'
    $fxliang.ref | Should -Be 'pb'
  }

  It 'includes 092wb and lutai data packages' {
    $config = Read-BuildsYaml -Path $BuildsPath
    $wb092 = $config.datas | Where-Object { $_.name -eq '092wb' }
    $lutai = $config.datas | Where-Object { $_.name -eq 'lutai' }

    $wb092 | Should -Not -BeNullOrEmpty
    $wb092.display | Should -Be '092五笔'
    $wb092.url | Should -Be 'https://github.com/092wb/092wb.git'
    $wb092.ref | Should -Be 'main'

    $lutai | Should -Not -BeNullOrEmpty
    $lutai.display | Should -Be '露台码'
    $lutai.url | Should -Be 'https://github.com/Flauver/lutai.git'
    $lutai.ref | Should -Be 'dev'
  }

  It 'carries display names into the build matrix' {
    $config = Read-BuildsYaml -Path $BuildsPath
    $matrix = @(Expand-BuildMatrix -Config $config)
    $tigerRime = $matrix | Where-Object { $_.data_name -eq 'tiger' -and $_.weasel_name -eq 'rime' }

    $tigerRime | Should -Not -BeNullOrEmpty
    $tigerRime.data_display | Should -Be '虎码'
    $tigerRime.weasel_display | Should -Be '官方小狼毫'
  }
}
