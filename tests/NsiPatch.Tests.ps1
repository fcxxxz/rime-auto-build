BeforeAll {
  $ModulePath = Join-Path $PSScriptRoot '..\scripts\lib\NsiPatch.psm1'
  Import-Module $ModulePath -Force
}

Describe 'Get-PackNsiStopServerReplacement' {
  It 'replaces official upstream /quit stop-server anchors' {
    Get-PackNsiStopServerReplacement '  ExecWait ''"$R1\WeaselServer.exe" /quit''' |
      Should -Be '  !insertmacro PACK_PS1_STOP_WEASEL_SERVER $R1\WeaselServer.exe'

    Get-PackNsiStopServerReplacement '  ExecWait ''"$INSTDIR\WeaselServer.exe" /quit''' |
      Should -Be '  !insertmacro PACK_PS1_STOP_WEASEL_SERVER $INSTDIR\WeaselServer.exe'
  }

  It 'keeps existing /stop stop-server anchors compatible' {
    Get-PackNsiStopServerReplacement '  ExecWait ''"$R1\WeaselServer.exe" /stop''' |
      Should -Be '  !insertmacro PACK_PS1_STOP_WEASEL_SERVER $R1\WeaselServer.exe'

    Get-PackNsiStopServerReplacement '  ExecWait ''"$INSTDIR\WeaselServer.exe" /stop''' |
      Should -Be '  !insertmacro PACK_PS1_STOP_WEASEL_SERVER $INSTDIR\WeaselServer.exe'
  }

  It 'ignores unrelated ExecWait commands' {
    Get-PackNsiStopServerReplacement '  ExecWait ''"$INSTDIR\WeaselSetup.exe" /u''' |
      Should -BeNullOrEmpty
  }
}
