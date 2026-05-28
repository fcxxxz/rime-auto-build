function New-InstallerManifest {
  param(
    [Parameter(Mandatory)][string]$InstallerName,
    [Parameter(Mandatory)][string]$DataName,
    [Parameter(Mandatory)][string]$DataUrl,
    [Parameter(Mandatory)][string]$DataRef,
    [Parameter(Mandatory)][string]$DataSha,
    [Parameter(Mandatory)][string]$WeaselName,
    [Parameter(Mandatory)][string]$WeaselUrl,
    [Parameter(Mandatory)][string]$WeaselRef,
    [Parameter(Mandatory)][string]$WeaselSha
  )

  return [pscustomobject]@{
    installer = $InstallerName
    data = [pscustomobject]@{
      name = $DataName
      url = $DataUrl
      ref = $DataRef
      sha = $DataSha
    }
    weasel = [pscustomobject]@{
      name = $WeaselName
      url = $WeaselUrl
      ref = $WeaselRef
      sha = $WeaselSha
    }
  }
}

function Format-ShortSha([string]$Sha) {
  if ([string]::IsNullOrWhiteSpace($Sha)) {
    return ''
  }
  if ($Sha.Length -le 7) {
    return $Sha
  }
  return $Sha.Substring(0, 7)
}

function New-ReleaseNotes {
  param(
    [Parameter(Mandatory)][string]$EventName,
    [Parameter(Mandatory)][string]$StatePath,
    [Parameter(Mandatory)][string]$BuildsPath,
    [Parameter(Mandatory)][object[]]$Manifests
  )

  $lines = New-Object System.Collections.Generic.List[string]
  $lines.Add('自动构建。')
  $lines.Add('')
  $lines.Add("- 触发：``$EventName``")
  $lines.Add("- SHA 快照：见 ``$StatePath``")
  $lines.Add("- 配置：见 ``$BuildsPath``")
  $lines.Add('')
  $lines.Add('## 安装包说明')
  $lines.Add('')

  foreach ($manifest in @($Manifests | Sort-Object installer)) {
    $dataSha = Format-ShortSha $manifest.data.sha
    $weaselSha = Format-ShortSha $manifest.weasel.sha
    $lines.Add("- ``$($manifest.installer)``")
    $lines.Add("  - 方案：``$($manifest.data.name)`` (``$($manifest.data.ref)`` @ ``$dataSha``) $($manifest.data.url)")
    $lines.Add("  - 小狼毫：``$($manifest.weasel.name)`` (``$($manifest.weasel.ref)`` @ ``$weaselSha``) $($manifest.weasel.url)")
  }

  return ($lines -join "`n") + "`n"
}

Export-ModuleMember -Function New-InstallerManifest,New-ReleaseNotes
