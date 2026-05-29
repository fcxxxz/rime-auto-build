BeforeAll {
  $ModulePath = Join-Path $PSScriptRoot '..\scripts\lib\NsiPatch.psm1'
  Import-Module $ModulePath -Force
}

Describe 'Get-PackNsiStopServerReplacement' {
  It 'replaces official upstream /quit stop-server anchors' {
    Get-PackNsiStopServerReplacement '  ExecWait ''"$R1\WeaselServer.exe" /quit''' |
      Should -Be '  !insertmacro PACK_PS1_STOP_WEASEL_SERVER $R1\WeaselServer.exe /quit'

    Get-PackNsiStopServerReplacement '  ExecWait ''"$INSTDIR\WeaselServer.exe" /quit''' |
      Should -Be '  !insertmacro PACK_PS1_STOP_WEASEL_SERVER $INSTDIR\WeaselServer.exe /quit'
  }

  It 'keeps existing /stop stop-server anchors compatible' {
    Get-PackNsiStopServerReplacement '  ExecWait ''"$R1\WeaselServer.exe" /stop''' |
      Should -Be '  !insertmacro PACK_PS1_STOP_WEASEL_SERVER $R1\WeaselServer.exe /stop'

    Get-PackNsiStopServerReplacement '  ExecWait ''"$INSTDIR\WeaselServer.exe" /stop''' |
      Should -Be '  !insertmacro PACK_PS1_STOP_WEASEL_SERVER $INSTDIR\WeaselServer.exe /stop'
  }

  It 'ignores unrelated ExecWait commands' {
    Get-PackNsiStopServerReplacement '  ExecWait ''"$INSTDIR\WeaselSetup.exe" /u''' |
      Should -BeNullOrEmpty
  }

  It 'restores patched stop-server macros with their original command' {
    $source = @(
      '  !insertmacro PACK_PS1_STOP_WEASEL_SERVER $R1\WeaselServer.exe /quit',
      '  !insertmacro PACK_PS1_STOP_WEASEL_SERVER $INSTDIR\WeaselServer.exe /stop'
    )

    Remove-PackNsiPatches $source | Should -Be @(
      '  ExecWait ''"$R1\WeaselServer.exe" /quit''',
      '  ExecWait ''"$INSTDIR\WeaselServer.exe" /stop'''
    )
  }

  It 'removes patched stop-server macro definitions during cleanup' {
    $source = @(
      '; ---PACK_PS1_STOP_WEASEL_SERVER_MACRO---',
      '!macro PACK_PS1_STOP_WEASEL_SERVER SERVER_EXE SERVER_COMMAND',
      '  Delete "$TEMP\rime.weasel\weasel-service-manual-exit.flag"',
      '!macroend',
      '; ---END_PACK_PS1_STOP_WEASEL_SERVER_MACRO---',
      'SectionEnd'
    )

    Remove-PackNsiPatches $source | Should -Be @('SectionEnd')
  }
}

Describe 'Add-PackNsiOverwriteConfirmationPatch' {
  It 'inserts localized overwrite warning before the existing uninstall prompt' {
    $source = @(
      'LangString AUTOCHKUPDATE ${LANG_ENGLISH} "Automatically check for updates?"',
      '',
      'Function .onInit',
      '  ReadRegStr $R0 HKLM \',
      '  "Software\Microsoft\Windows\CurrentVersion\Uninstall\Weasel" \',
      '  "UninstallString"',
      '  StrCmp $R0 "" done',
      '',
      '  StrCpy $0 "Upgrade"',
      '  IfSilent uninst 0',
      '  MessageBox MB_OKCANCEL|MB_ICONINFORMATION "$(CONFIRMATION)" IDOK uninst',
      '  Abort',
      '',
      'uninst:',
      'done:',
      'FunctionEnd'
    )

    $patched = Add-PackNsiOverwriteConfirmationPatch $source

    $langIndex = [Array]::IndexOf($patched, '; ---PACK_PS1_OVERWRITE_CONFIRMATION_LANGSTRINGS---')
    $autoUpdateIndex = [Array]::IndexOf($patched, $source[0])
    $promptIndex = [Array]::IndexOf($patched, '; ---PACK_PS1_OVERWRITE_CONFIRMATION_PROMPT---')
    $existingInstallIndex = [Array]::IndexOf($patched, '  StrCmp $R0 "" done')
    $upgradeIndex = [Array]::IndexOf($patched, '  StrCpy $0 "Upgrade"')

    $langIndex | Should -BeGreaterThan $autoUpdateIndex
    $promptIndex | Should -BeGreaterThan $existingInstallIndex
    $promptIndex | Should -BeLessThan $upgradeIndex
    $patched | Should -Contain 'LangString PACK_PS1_OVERWRITE_CONFIRMATION ${LANG_SIMPCHINESE} "本次安装将覆盖现有方案配置，确定继续安装？"'
    $patched | Should -Contain '  IfSilent pack_ps1_overwrite_confirmed 0'
    $patched | Should -Contain '  MessageBox MB_OKCANCEL|MB_ICONEXCLAMATION "$(PACK_PS1_OVERWRITE_CONFIRMATION)" IDOK pack_ps1_overwrite_confirmed'
    $patched | Should -Contain '  Abort'
  }

  It 'throws when the language-string anchor is missing' {
    {
      Add-PackNsiOverwriteConfirmationPatch @(
        'Function .onInit',
        '  StrCmp $R0 "" done',
        'FunctionEnd'
      )
    } | Should -Throw -ExpectedMessage '*overwrite confirmation language anchor*'
  }

  It 'throws when the installed-Weasel anchor is missing' {
    {
      Add-PackNsiOverwriteConfirmationPatch @(
        'LangString AUTOCHKUPDATE ${LANG_ENGLISH} "Automatically check for updates?"',
        'Function .onInit',
        'FunctionEnd'
      )
    } | Should -Throw -ExpectedMessage '*overwrite confirmation prompt anchor*'
  }

  It 'can be removed by the existing PACK_PS1 marker cleanup' {
    $source = @(
      'LangString AUTOCHKUPDATE ${LANG_ENGLISH} "Automatically check for updates?"',
      'Function .onInit',
      '  StrCmp $R0 "" done',
      'FunctionEnd'
    )

    $patched = Add-PackNsiOverwriteConfirmationPatch $source
    $cleaned = Remove-PackNsiPatches $patched

    $cleaned | Should -Be $source
  }
}

Describe 'Add-PackNsiPostInstallTextServicesRefreshPatch' {
  It 'refreshes text services immediately after upstream WeaselSetup registration' {
    $source = @(
      '  ExecWait ''"$INSTDIR\WeaselSetup.exe" $R2''',
      '',
      '  ; Write the uninstall keys for Windows'
    )

    $patched = Add-PackNsiPostInstallTextServicesRefreshPatch $source

    $setupIndex = [Array]::IndexOf($patched, $source[0])
    $refreshIndex = [Array]::IndexOf($patched, '  !insertmacro PACK_PS1_REFRESH_TEXT_SERVICES')
    $uninstallIndex = [Array]::IndexOf($patched, $source[2])

    $refreshIndex | Should -BeGreaterThan $setupIndex
    $refreshIndex | Should -BeLessThan $uninstallIndex
  }

  It 'waits until an existing WeaselSetup result check has passed' {
    $source = @(
      '  ExecWait ''"$INSTDIR\WeaselSetup.exe" $R2'' $R3',
      '  ${If} $R3 != 0',
      '    Abort',
      '  ${Endif}',
      '',
      '  ; Write the uninstall keys for Windows'
    )

    $patched = Add-PackNsiPostInstallTextServicesRefreshPatch $source

    $endifIndex = [Array]::IndexOf($patched, '  ${Endif}')
    $refreshIndex = [Array]::IndexOf($patched, '  !insertmacro PACK_PS1_REFRESH_TEXT_SERVICES')
    $uninstallIndex = [Array]::IndexOf($patched, $source[5])

    $refreshIndex | Should -BeGreaterThan $endifIndex
    $refreshIndex | Should -BeLessThan $uninstallIndex
  }

  It 'throws when the WeaselSetup registration anchor is missing' {
    {
      Add-PackNsiPostInstallTextServicesRefreshPatch @(
        'Section "Weasel"',
        'SectionEnd'
      )
    } | Should -Throw -ExpectedMessage '*post-install text-services refresh anchor*'
  }
}

Describe 'Add-PackNsiUnregisterTextServicesRefreshPatch' {
  It 'refreshes after old and current WeaselSetup unregistration commands' {
    $source = @(
      'call_uninstaller:',
      '  ExecWait ''"$R1\WeaselSetup.exe" /u''',
      '  ; Remove old registry keys',
      'Section "Uninstall"',
      '  ExecWait ''"$INSTDIR\WeaselSetup.exe" /u''',
      '  ; Remove current registry keys'
    )

    $patched = Add-PackNsiUnregisterTextServicesRefreshPatch $source

    $oldSetupIndex = [Array]::IndexOf($patched, $source[1])
    $oldRefreshIndex = [Array]::IndexOf($patched, '  !insertmacro PACK_PS1_REFRESH_TEXT_SERVICES')
    $currentSetupIndex = [Array]::IndexOf($patched, $source[4])
    $currentRefreshIndex = [Array]::LastIndexOf($patched, '  !insertmacro PACK_PS1_REFRESH_TEXT_SERVICES')

    $oldRefreshIndex | Should -BeGreaterThan $oldSetupIndex
    $oldRefreshIndex | Should -BeLessThan ([Array]::IndexOf($patched, $source[2]))
    $currentRefreshIndex | Should -BeGreaterThan $currentSetupIndex
    $currentRefreshIndex | Should -BeLessThan ([Array]::IndexOf($patched, $source[5]))
  }

  It 'throws when either unregister anchor is missing' {
    {
      Add-PackNsiUnregisterTextServicesRefreshPatch @(
        'Section "Uninstall"',
        '  ExecWait ''"$INSTDIR\WeaselSetup.exe" /u''',
        'SectionEnd'
      )
    } | Should -Throw -ExpectedMessage '*unregister text-services refresh anchors*'
  }

  It 'can be removed and reapplied without duplicate refresh commands' {
    $source = @(
      'call_uninstaller:',
      '  ExecWait ''"$R1\WeaselSetup.exe" /u''',
      '  ; Remove registry keys',
      'Section "Uninstall"',
      '  ExecWait ''"$INSTDIR\WeaselSetup.exe" /u''',
      '  ; Remove registry keys'
    )

    $patched = Add-PackNsiUnregisterTextServicesRefreshPatch $source
    $reapplied = Add-PackNsiUnregisterTextServicesRefreshPatch (Remove-PackNsiPatches $patched)

    @($reapplied | Where-Object { $_.Trim() -eq '!insertmacro PACK_PS1_REFRESH_TEXT_SERVICES' }).Count |
      Should -Be 2
  }
}
