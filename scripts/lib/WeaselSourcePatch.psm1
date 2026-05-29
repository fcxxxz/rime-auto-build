Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Remove-WeaselIpcArchiveExtensionLines([string[]]$Lines) {
  $patched = New-Object System.Collections.Generic.List[string]

  foreach ($line in $Lines) {
    if ($line -match '^\s*ar\s*&\s*s\.vertical_right_to_left\s*;\s*$') {
      continue
    }
    if ($line -match '^\s*ar\s*&\s*s\.hide_ime_mode_icon\s*;\s*$') {
      continue
    }
    $patched.Add($line)
  }

  return [string[]]$patched
}

function Repair-WeaselIpcArchiveCompatibility([string]$WeaselRoot) {
  $ipcData = Join-Path $WeaselRoot 'include\WeaselIPCData.h'
  if (-not (Test-Path -LiteralPath $ipcData)) {
    throw "Weasel IPC data header not found: $ipcData"
  }

  $original = [System.IO.File]::ReadAllLines($ipcData)
  $patched = Remove-WeaselIpcArchiveExtensionLines $original

  if ($patched.Count -eq $original.Count) {
    return $false
  }

  [System.IO.File]::WriteAllLines(
    $ipcData,
    $patched,
    [System.Text.UTF8Encoding]::new($false)
  )
  return $true
}

Export-ModuleMember -Function Remove-WeaselIpcArchiveExtensionLines,Repair-WeaselIpcArchiveCompatibility
