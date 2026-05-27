BeforeAll {
  Import-Module (Join-Path $PSScriptRoot '..\scripts\lib\Yaml.psm1') -Force
  Import-Module (Join-Path $PSScriptRoot '..\scripts\lib\State.psm1') -Force
  $BuildsPath  = Join-Path $PSScriptRoot 'fixtures\builds.yaml'
  $EmptyPath   = Join-Path $PSScriptRoot 'fixtures\last-seen.empty.json'
  $PartialPath = Join-Path $PSScriptRoot 'fixtures\last-seen.partial.json'
}

Describe 'Read-State' {
  It 'reads empty state' {
    $s = Read-State -Path $EmptyPath
    $s.weasels.Count | Should -Be 0
    $s.datas.Count   | Should -Be 0
  }
  It 'reads partial state' {
    $s = Read-State -Path $PartialPath
    $s.weasels['official'].sha | Should -Be 'aaaaaaaa1111111111111111111111111111aaaa'
    $s.datas['tiger'].sha      | Should -Be 'bbbbbbbb2222222222222222222222222222bbbb'
  }
  It 'returns empty state when file missing' {
    $s = Read-State -Path 'nonexistent.json'
    $s.weasels.Count | Should -Be 0
    $s.datas.Count   | Should -Be 0
  }
}

Describe 'Compare-State' {
  It 'detects no change when probed equals previous' {
    $config = Read-BuildsYaml -Path $BuildsPath
    $previous = Read-State -Path $PartialPath
    $probed = @{
      weasels = @{
        official = @{ url = 'https://github.com/rime/weasel.git';        ref = 'master'; sha = 'aaaaaaaa1111111111111111111111111111aaaa' }
        mine     = @{ url = 'https://github.com/example/weasel.git';     ref = 'main';   sha = 'cccccccc3333333333333333333333333333cccc' }
      }
      datas = @{
        tiger = @{ url = 'https://github.com/example/rime-tiger.git'; ref = 'main'; sha = 'bbbbbbbb2222222222222222222222222222bbbb' }
        moqi  = @{ url = 'https://github.com/example/rime-moqi.git'; ref = 'main'; sha = 'dddddddd4444444444444444444444444444dddd' }
      }
    }
    # mine and moqi are new -> changed
    $diff = Compare-State -Previous $previous -Probed $probed
    $diff.changed                    | Should -BeTrue
    $diff.changed_targets.weasels    | Should -Contain 'mine'
    $diff.changed_targets.weasels    | Should -Not -Contain 'official'
    $diff.changed_targets.datas      | Should -Contain 'moqi'
    $diff.changed_targets.datas      | Should -Not -Contain 'tiger'
  }

  It 'detects SHA change in existing entry' {
    $previous = Read-State -Path $PartialPath
    $probed = @{
      weasels = @{ official = @{ url = 'https://github.com/rime/weasel.git'; ref = 'master'; sha = 'zzzzzzzz9999999999999999999999999999zzzz' } }
      datas   = @{ tiger    = @{ url = 'https://github.com/example/rime-tiger.git'; ref = 'main'; sha = 'bbbbbbbb2222222222222222222222222222bbbb' } }
    }
    $diff = Compare-State -Previous $previous -Probed $probed
    $diff.changed | Should -BeTrue
    $diff.changed_targets.weasels | Should -Be @('official')
    $diff.changed_targets.datas   | Should -BeNullOrEmpty
  }

  It 'detects no change' {
    $previous = Read-State -Path $PartialPath
    $probed = @{
      weasels = @{ official = @{ url = 'https://github.com/rime/weasel.git'; ref = 'master'; sha = 'aaaaaaaa1111111111111111111111111111aaaa' } }
      datas   = @{ tiger    = @{ url = 'https://github.com/example/rime-tiger.git'; ref = 'main'; sha = 'bbbbbbbb2222222222222222222222222222bbbb' } }
    }
    $diff = Compare-State -Previous $previous -Probed $probed
    $diff.changed | Should -BeFalse
  }

  It 'detects removed entry as no change (config drift, not upstream change)' {
    # previous has 'official' but probed (current builds.yaml) doesn't include it
    $previous = Read-State -Path $PartialPath
    $probed = @{
      weasels = @{}
      datas   = @{}
    }
    $diff = Compare-State -Previous $previous -Probed $probed
    $diff.changed | Should -BeFalse
  }

  It 'summary string is human readable' {
    $previous = Read-State -Path $EmptyPath
    $probed = @{
      weasels = @{ a = @{ url='x'; ref='y'; sha='z'*40 } }
      datas   = @{ b = @{ url='x'; ref='y'; sha='w'*40 } }
    }
    $diff = Compare-State -Previous $previous -Probed $probed
    $diff.summary | Should -Match 'weasels'
    $diff.summary | Should -Match 'datas'
  }
}

Describe 'Write-State' {
  It 'writes JSON that round-trips' {
    $tmp = New-TemporaryFile
    try {
      $probed = @{
        weasels = @{ official = @{ url = 'u'; ref = 'r'; sha = ('a'*40) } }
        datas   = @{ tiger    = @{ url = 'u'; ref = 'r'; sha = ('b'*40) } }
      }
      Write-State -Path $tmp.FullName -Probed $probed
      $reread = Read-State -Path $tmp.FullName
      $reread.weasels['official'].sha | Should -Be ('a'*40)
      $reread.datas['tiger'].sha      | Should -Be ('b'*40)
    } finally { Remove-Item $tmp.FullName -Force }
  }
}
