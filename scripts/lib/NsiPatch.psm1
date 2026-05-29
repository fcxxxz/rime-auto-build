function Get-PackNsiStopServerReplacement([string]$Line) {
  $trimmed = $Line.Trim()
  $serverExecutables = @('$R1\WeaselServer.exe', '$INSTDIR\WeaselServer.exe')

  foreach ($serverExe in $serverExecutables) {
    foreach ($command in @('/stop', '/quit')) {
      $rawStopLine = "ExecWait '`"$serverExe`" $command'"
      if ($trimmed -eq $rawStopLine) {
        return "  !insertmacro PACK_PS1_STOP_WEASEL_SERVER $serverExe $command"
      }
    }
  }

  return $null
}

function Remove-PackNsiPatches([string[]]$Lines) {
  $clean = New-Object System.Collections.Generic.List[string]
  $insidePackBlock = $false

  foreach ($line in $Lines) {
    if ($line -match '^\s*;\s+---PACK_PS1_[A-Z0-9_]+---\s*$') {
      $insidePackBlock = $true
      continue
    }
    if ($line -match '^\s*;\s+---END_PACK_PS1_[A-Z0-9_]+---\s*$') {
      $insidePackBlock = $false
      continue
    }
    if ($insidePackBlock) {
      continue
    }

    $restoredStopServerLine = $false
    foreach ($serverExe in @('$R1\WeaselServer.exe', '$INSTDIR\WeaselServer.exe')) {
      foreach ($command in @('/stop', '/quit')) {
        if ($line.Trim() -eq "!insertmacro PACK_PS1_STOP_WEASEL_SERVER $serverExe $command") {
          $clean.Add("  ExecWait '`"$serverExe`" $command'")
          $restoredStopServerLine = $true
          break
        }
      }
      if ($restoredStopServerLine) {
        break
      }
      if ($line.Trim() -eq "!insertmacro PACK_PS1_STOP_WEASEL_SERVER $serverExe") {
        $clean.Add("  ExecWait '`"$serverExe`" /stop'")
        $restoredStopServerLine = $true
        break
      }
    }
    if ($restoredStopServerLine) {
      continue
    }
    if ($line.Trim() -eq '!insertmacro PACK_PS1_REFRESH_TEXT_SERVICES') {
      continue
    }

    $clean.Add($line)
  }

  return [string[]]$clean
}

function Add-PackNsiPostInstallTextServicesRefreshPatch([string[]]$Lines) {
  $patched = New-Object System.Collections.Generic.List[string]
  $inserted = $false
  $pendingAfterResultCheck = $false
  $insideResultCheck = $false

  foreach ($line in $Lines) {
    $patched.Add($line)
    $trimmed = $line.Trim()

    if ($pendingAfterResultCheck) {
      if (-not $insideResultCheck -and $trimmed -eq '${If} $R3 != 0') {
        $insideResultCheck = $true
        continue
      }

      if ($insideResultCheck) {
        if ($trimmed -eq '${Endif}') {
          $patched.Add('  !insertmacro PACK_PS1_REFRESH_TEXT_SERVICES')
          $inserted = $true
          $pendingAfterResultCheck = $false
          $insideResultCheck = $false
        }
        continue
      }

      $patched.Add('  !insertmacro PACK_PS1_REFRESH_TEXT_SERVICES')
      $inserted = $true
      $pendingAfterResultCheck = $false
    }

    if ($trimmed -like 'ExecWait ''"$INSTDIR\WeaselSetup.exe" $R2''*') {
      $pendingAfterResultCheck = $true
    }
  }

  if ($pendingAfterResultCheck) {
    $patched.Add('  !insertmacro PACK_PS1_REFRESH_TEXT_SERVICES')
    $inserted = $true
  }

  if (-not $inserted) {
    throw 'install.nsi post-install text-services refresh anchor (WeaselSetup.exe $R2) not found'
  }

  return [string[]]$patched
}

function Add-PackNsiUnregisterTextServicesRefreshPatch([string[]]$Lines) {
  $patched = New-Object System.Collections.Generic.List[string]
  $matched = New-Object System.Collections.Generic.HashSet[string]
  $unregisterLines = @(
    'ExecWait ''"$R1\WeaselSetup.exe" /u''',
    'ExecWait ''"$INSTDIR\WeaselSetup.exe" /u'''
  )

  foreach ($line in $Lines) {
    $patched.Add($line)
    $trimmed = $line.Trim()

    foreach ($unregisterLine in $unregisterLines) {
      if ($trimmed -eq $unregisterLine) {
        $patched.Add('  !insertmacro PACK_PS1_REFRESH_TEXT_SERVICES')
        [void]$matched.Add($unregisterLine)
        break
      }
    }
  }

  if ($matched.Count -lt $unregisterLines.Count) {
    throw 'install.nsi unregister text-services refresh anchors not found'
  }

  return [string[]]$patched
}

function ConvertFrom-PackNsiCodePoints([int[]]$CodePoints) {
  return -join @($CodePoints | ForEach-Object { [char]$_ })
}

function Add-PackNsiOverwriteConfirmationPatch([string[]]$Lines) {
  $traditionalChineseText = ConvertFrom-PackNsiCodePoints @(
    0x672c,0x6b21,0x5b89,0x88dd,0x5c07,0x8986,0x84cb,0x73fe,0x6709,0x65b9,0x6848,
    0x914d,0x7f6e,0xff0c,0x78ba,0x5b9a,0x7e7c,0x7e8c,0x5b89,0x88dd,0xff1f
  )
  $simplifiedChineseText = ConvertFrom-PackNsiCodePoints @(
    0x672c,0x6b21,0x5b89,0x88c5,0x5c06,0x8986,0x76d6,0x73b0,0x6709,0x65b9,0x6848,
    0x914d,0x7f6e,0xff0c,0x786e,0x5b9a,0x7ee7,0x7eed,0x5b89,0x88c5,0xff1f
  )
  $languageInsertion = @(
    '; ---PACK_PS1_OVERWRITE_CONFIRMATION_LANGSTRINGS---',
    ('LangString PACK_PS1_OVERWRITE_CONFIRMATION ${LANG_TRADCHINESE} "' + $traditionalChineseText + '"'),
    ('LangString PACK_PS1_OVERWRITE_CONFIRMATION ${LANG_SIMPCHINESE} "' + $simplifiedChineseText + '"'),
    'LangString PACK_PS1_OVERWRITE_CONFIRMATION ${LANG_ENGLISH} "This installation will overwrite the existing schema configuration. Continue?"',
    '; ---END_PACK_PS1_OVERWRITE_CONFIRMATION_LANGSTRINGS---'
  )
  $promptInsertion = @(
    '; ---PACK_PS1_OVERWRITE_CONFIRMATION_PROMPT---',
    '  IfSilent pack_ps1_overwrite_confirmed 0',
    '  MessageBox MB_OKCANCEL|MB_ICONEXCLAMATION "$(PACK_PS1_OVERWRITE_CONFIRMATION)" IDOK pack_ps1_overwrite_confirmed',
    '  Abort',
    '  pack_ps1_overwrite_confirmed:',
    '; ---END_PACK_PS1_OVERWRITE_CONFIRMATION_PROMPT---'
  )

  $patched = New-Object System.Collections.Generic.List[string]
  $insertedLanguage = $false
  $insertedPrompt = $false

  foreach ($line in $Lines) {
    $patched.Add($line)

    if (-not $insertedLanguage -and $line -match '^LangString\s+AUTOCHKUPDATE\s+\$\{LANG_ENGLISH\}\s+') {
      foreach ($ins in $languageInsertion) { $patched.Add($ins) }
      $insertedLanguage = $true
    }

    if (-not $insertedPrompt -and $line.Trim() -eq 'StrCmp $R0 "" done') {
      foreach ($ins in $promptInsertion) { $patched.Add($ins) }
      $insertedPrompt = $true
    }
  }

  if (-not $insertedLanguage) {
    throw "install.nsi overwrite confirmation language anchor (LangString AUTOCHKUPDATE LANG_ENGLISH) not found"
  }
  if (-not $insertedPrompt) {
    throw 'install.nsi overwrite confirmation prompt anchor (StrCmp $R0 "" done) not found'
  }

  return [string[]]$patched
}

Export-ModuleMember -Function Get-PackNsiStopServerReplacement,Remove-PackNsiPatches,Add-PackNsiOverwriteConfirmationPatch,Add-PackNsiPostInstallTextServicesRefreshPatch,Add-PackNsiUnregisterTextServicesRefreshPatch
