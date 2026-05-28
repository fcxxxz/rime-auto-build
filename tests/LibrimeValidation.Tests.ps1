BeforeAll {
  $ModulePath = Join-Path $PSScriptRoot '..\scripts\lib\LibrimeValidation.psm1'
  Import-Module $ModulePath -Force
}

Describe 'Test-PackCustomDataNeedsLua' {
  BeforeEach {
    $Root = Join-Path $TestDrive 'custom-data'
    if (Test-Path -LiteralPath $Root) {
      Remove-Item -LiteralPath $Root -Recurse -Force
    }
    New-Item -ItemType Directory -Path $Root -Force | Out-Null
  }

  It 'returns true when custom-data contains lua scripts' {
    New-Item -ItemType Directory -Path (Join-Path $Root 'lua') -Force | Out-Null

    Test-PackCustomDataNeedsLua $Root | Should -BeTrue
  }

  It 'returns true when schema YAML references lua components' {
    Set-Content -LiteralPath (Join-Path $Root 'sample.schema.yaml') -Value @'
engine:
  processors:
    - lua_processor@*symbol_proc
'@ -Encoding UTF8

    Test-PackCustomDataNeedsLua $Root | Should -BeTrue
  }

  It 'returns false when custom-data has no lua scripts or lua component references' {
    Set-Content -LiteralPath (Join-Path $Root 'sample.schema.yaml') -Value @'
engine:
  processors:
    - key_binder
'@ -Encoding UTF8

    Test-PackCustomDataNeedsLua $Root | Should -BeFalse
  }
}

Describe 'Test-PackRimeDllSupportsLua' {
  It 'requires all lua component names in rime.dll' {
    $dll = Join-Path $TestDrive 'rime.dll'
    [System.IO.File]::WriteAllText($dll, 'lua_processor lua_translator lua_filter lua_segmentor', [System.Text.Encoding]::ASCII)

    Test-PackRimeDllSupportsLua $dll | Should -BeTrue
  }

  It 'rejects rime.dll files that do not contain lua component names' {
    $dll = Join-Path $TestDrive 'rime.dll'
    [System.IO.File]::WriteAllText($dll, 'reverse_lookup_translator key_binder', [System.Text.Encoding]::ASCII)

    Test-PackRimeDllSupportsLua $dll | Should -BeFalse
  }
}

Describe 'Assert-PackLibrimeLuaSupport' {
  It 'throws when packaged custom-data needs lua but x64 rime.dll does not support lua' {
    $weasel = Join-Path $TestDrive 'weasel'
    $custom = Join-Path $TestDrive 'custom-data'
    New-Item -ItemType Directory -Path (Join-Path $weasel 'output\Win32'),(Join-Path $custom 'lua') -Force | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $weasel 'output\rime.dll'), 'no lua here', [System.Text.Encoding]::ASCII)
    [System.IO.File]::WriteAllText((Join-Path $weasel 'output\Win32\rime.dll'), 'lua_processor lua_translator lua_filter lua_segmentor', [System.Text.Encoding]::ASCII)

    { Assert-PackLibrimeLuaSupport -WeaselRoot $weasel -CustomDataDir $custom } |
      Should -Throw -ExpectedMessage '*requires librime-lua*output\rime.dll*'
  }

  It 'throws when forced even if custom-data does not need lua' {
    $weasel = Join-Path $TestDrive 'weasel-forced'
    $custom = Join-Path $TestDrive 'custom-data-forced'
    New-Item -ItemType Directory -Path (Join-Path $weasel 'output\Win32'),$custom -Force | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $weasel 'output\rime.dll'), 'no lua here', [System.Text.Encoding]::ASCII)
    [System.IO.File]::WriteAllText((Join-Path $weasel 'output\Win32\rime.dll'), 'lua_processor lua_translator lua_filter lua_segmentor', [System.Text.Encoding]::ASCII)

    { Assert-PackLibrimeLuaSupport -WeaselRoot $weasel -CustomDataDir $custom -Force } |
      Should -Throw -ExpectedMessage '*requires librime-lua*output\rime.dll*'
  }

  It 'does not throw when custom-data needs lua and both rime.dll files support lua' {
    $weasel = Join-Path $TestDrive 'weasel'
    $custom = Join-Path $TestDrive 'custom-data'
    New-Item -ItemType Directory -Path (Join-Path $weasel 'output\Win32'),(Join-Path $custom 'lua') -Force | Out-Null
    foreach ($dll in @((Join-Path $weasel 'output\rime.dll'), (Join-Path $weasel 'output\Win32\rime.dll'))) {
      [System.IO.File]::WriteAllText($dll, 'lua_processor lua_translator lua_filter lua_segmentor', [System.Text.Encoding]::ASCII)
    }

    { Assert-PackLibrimeLuaSupport -WeaselRoot $weasel -CustomDataDir $custom } | Should -Not -Throw
  }
}

Describe 'Install-PackLibrimeLuaPlugin' {
  It 'does nothing when custom-data does not need lua' {
    $root = Join-Path $TestDrive 'lua-not-needed'
    $weasel = Join-Path $root 'weasel'
    $custom = Join-Path $root 'custom-data'
    New-Item -ItemType Directory -Path $weasel,$custom -Force | Out-Null

    Install-PackLibrimeLuaPlugin -WeaselRoot $weasel -CustomDataDir $custom

    Test-Path -LiteralPath (Join-Path $weasel 'librime\plugins\lua') | Should -BeFalse
  }

  It 'prepares lua when forced even if custom-data does not need lua' {
    $root = Join-Path $TestDrive 'lua-forced'
    $weasel = Join-Path $root 'weasel'
    $custom = Join-Path $root 'custom-data'
    New-Item -ItemType Directory -Path (Join-Path $weasel 'librime\plugins'),$custom -Force | Out-Null

    { Install-PackLibrimeLuaPlugin -WeaselRoot $weasel -CustomDataDir $custom -GitCommandName 'missing-git-for-test' -Force } |
      Should -Throw -ExpectedMessage '*custom-data requires librime-lua*missing-git-for-test*'
  }

  It 'accepts an existing librime-lua plugin with thirdparty lua source when custom-data needs lua' {
    $root = Join-Path $TestDrive 'lua-existing-plugin'
    $weasel = Join-Path $root 'weasel'
    $custom = Join-Path $root 'custom-data'
    $plugin = Join-Path $weasel 'librime\plugins\lua'
    New-Item -ItemType Directory -Path (Join-Path $plugin 'thirdparty\lua5.4'),(Join-Path $custom 'lua') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $plugin 'CMakeLists.txt') -Value 'set(plugin_modules "lua" PARENT_SCOPE)'
    Set-Content -LiteralPath (Join-Path $plugin 'thirdparty\lua5.4\lua.h') -Value 'lua header'

    Install-PackLibrimeLuaPlugin -WeaselRoot $weasel -CustomDataDir $custom

    Test-Path -LiteralPath (Join-Path $plugin 'CMakeLists.txt') | Should -BeTrue
    Test-Path -LiteralPath (Join-Path $plugin 'thirdparty\lua5.4\lua.h') | Should -BeTrue
  }

  It 'throws before librime build when lua is needed but git is unavailable for plugin install' {
    $root = Join-Path $TestDrive 'lua-missing-git'
    $weasel = Join-Path $root 'weasel'
    $custom = Join-Path $root 'custom-data'
    New-Item -ItemType Directory -Path (Join-Path $weasel 'librime\plugins'),(Join-Path $custom 'lua') -Force | Out-Null

    { Install-PackLibrimeLuaPlugin -WeaselRoot $weasel -CustomDataDir $custom -GitCommandName 'missing-git-for-test' } |
      Should -Throw -ExpectedMessage '*custom-data requires librime-lua*missing-git-for-test*'
  }

  It 'checks out the requested librime-lua and thirdparty revisions' {
    $root = Join-Path $TestDrive 'lua-refs'
    $weasel = Join-Path $root 'weasel'
    $custom = Join-Path $root 'custom-data'
    $fakeGit = Join-Path $root 'git.ps1'
    $log = Join-Path $root 'git.log'
    New-Item -ItemType Directory -Path (Join-Path $weasel 'librime\plugins'),(Join-Path $custom 'lua') -Force | Out-Null
    Set-Content -LiteralPath $fakeGit -Value @'
$ErrorActionPreference = 'Stop'
Add-Content -LiteralPath $env:FAKE_GIT_LOG -Value ($args -join '|')
if ($args[0] -eq 'clone' -or ($args[0] -eq '-C' -and $args[2] -eq 'clone')) {
  $destination = $args[-1]
  if ($args[0] -eq '-C' -and -not [System.IO.Path]::IsPathRooted($destination)) {
    $destination = Join-Path $args[1] $destination
  }
  New-Item -ItemType Directory -Path $destination -Force | Out-Null
  if ((Split-Path -Leaf $destination) -eq 'thirdparty') {
    New-Item -ItemType Directory -Path (Join-Path $destination 'lua5.4') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $destination 'lua5.4\lua.h') -Value 'lua header'
  } else {
    Set-Content -LiteralPath (Join-Path $destination 'CMakeLists.txt') -Value 'plugin cmake'
  }
}
exit 0
'@

    $env:FAKE_GIT_LOG = $log
    try {
      Install-PackLibrimeLuaPlugin `
        -WeaselRoot $weasel `
        -CustomDataDir $custom `
        -GitCommandName $fakeGit `
        -LibrimeLuaRef 'lua-main-sha' `
        -LibrimeLuaThirdpartyRef 'lua-thirdparty-sha'
    } finally {
      $env:FAKE_GIT_LOG = $null
    }

    $calls = Get-Content -LiteralPath $log
    $calls | Should -Contain "-C|$(Join-Path $weasel 'librime\plugins\lua')|checkout|--detach|lua-main-sha"
    $calls | Should -Contain "-C|$(Join-Path $weasel 'librime\plugins\lua\thirdparty')|checkout|--detach|lua-thirdparty-sha"
  }
}
