function Get-PackNsiStopServerReplacement([string]$Line) {
  $trimmed = $Line.Trim()
  $serverExecutables = @('$R1\WeaselServer.exe', '$INSTDIR\WeaselServer.exe')

  foreach ($serverExe in $serverExecutables) {
    foreach ($command in @('/stop', '/quit')) {
      $rawStopLine = "ExecWait '`"$serverExe`" $command'"
      if ($trimmed -eq $rawStopLine) {
        return "  !insertmacro PACK_PS1_STOP_WEASEL_SERVER $serverExe"
      }
    }
  }

  return $null
}

Export-ModuleMember -Function Get-PackNsiStopServerReplacement
