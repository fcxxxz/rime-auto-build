BeforeAll {
  $ModulePath = Join-Path $PSScriptRoot '..\scripts\lib\WeaselSourcePatch.psm1'
  Import-Module $ModulePath -Force
}

Describe 'Remove-WeaselIpcArchiveExtensionLines' {
  It 'removes fxliang-only Boost archive fields while keeping runtime fields' {
    $source = @(
      '  bool vertical_right_to_left;',
      '  ar & s.vertical_text_with_wrap;',
      '  ar & s.vertical_right_to_left;',
      '  ar & s.paging_on_scroll;',
      '  ar & s.inline_preedit;',
      '  ar & s.hide_ime_mode_icon;'
    )

    $patched = Remove-WeaselIpcArchiveExtensionLines $source

    $patched | Should -Contain '  bool vertical_right_to_left;'
    $patched | Should -Contain '  ar & s.vertical_text_with_wrap;'
    $patched | Should -Contain '  ar & s.paging_on_scroll;'
    $patched | Should -Contain '  ar & s.inline_preedit;'
    $patched | Should -Not -Contain '  ar & s.vertical_right_to_left;'
    $patched | Should -Not -Contain '  ar & s.hide_ime_mode_icon;'
  }

  It 'is idempotent for already-compatible archive definitions' {
    $source = @(
      '  ar & s.layout_type;',
      '  ar & s.vertical_text_left_to_right;',
      '  ar & s.vertical_text_with_wrap;',
      '  ar & s.paging_on_scroll;'
    )

    Remove-WeaselIpcArchiveExtensionLines $source | Should -Be $source
  }

  It 'keeps the patched UIStyle archive field order compatible with upstream' {
    $upstream = @(
      '  ar & s.layout_type;',
      '  ar & s.vertical_text_left_to_right;',
      '  ar & s.vertical_text_with_wrap;',
      '  ar & s.paging_on_scroll;',
      '  ar & s.min_width;',
      '  ar & s.max_width;'
    )
    $fxliang = @(
      '  ar & s.layout_type;',
      '  ar & s.vertical_text_left_to_right;',
      '  ar & s.vertical_text_with_wrap;',
      '  ar & s.vertical_right_to_left;',
      '  ar & s.paging_on_scroll;',
      '  ar & s.min_width;',
      '  ar & s.max_width;'
    )

    Remove-WeaselIpcArchiveExtensionLines $fxliang | Should -Be $upstream
  }

  It 'keeps the patched Config archive field order compatible with upstream' {
    $upstream = @('  ar & s.inline_preedit;')
    $fxliang = @(
      '  ar & s.inline_preedit;',
      '  ar & s.hide_ime_mode_icon;'
    )

    Remove-WeaselIpcArchiveExtensionLines $fxliang | Should -Be $upstream
  }
}

Describe 'Repair-WeaselIpcArchiveCompatibility' {
  It 'patches include\WeaselIPCData.h in the isolated work tree' {
    $root = Join-Path $TestDrive 'weasel'
    $include = Join-Path $root 'include'
    New-Item -ItemType Directory -Path $include -Force | Out-Null
    $ipcData = Join-Path $include 'WeaselIPCData.h'
    Set-Content -LiteralPath $ipcData -Encoding UTF8 -Value @(
      '  ar & s.vertical_text_with_wrap;',
      '  ar & s.vertical_right_to_left;',
      '  ar & s.paging_on_scroll;'
    )

    Repair-WeaselIpcArchiveCompatibility $root | Should -BeTrue
    Get-Content -LiteralPath $ipcData | Should -Be @(
      '  ar & s.vertical_text_with_wrap;',
      '  ar & s.paging_on_scroll;'
    )
    Repair-WeaselIpcArchiveCompatibility $root | Should -BeFalse
  }
}
