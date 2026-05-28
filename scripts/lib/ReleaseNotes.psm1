function New-InstallerManifest {
  param(
    [Parameter(Mandatory)][string]$InstallerName,
    [Parameter(Mandatory)][string]$DataName,
    [Parameter(Mandatory)][string]$DataDisplay,
    [Parameter(Mandatory)][string]$DataUrl,
    [Parameter(Mandatory)][string]$DataRef,
    [Parameter(Mandatory)][string]$DataSha,
    [Parameter(Mandatory)][string]$DataCommitTime,
    [Parameter(Mandatory)][string]$WeaselName,
    [Parameter(Mandatory)][string]$WeaselDisplay,
    [Parameter(Mandatory)][string]$WeaselUrl,
    [Parameter(Mandatory)][string]$WeaselRef,
    [Parameter(Mandatory)][string]$WeaselSha,
    [Parameter(Mandatory)][string]$WeaselCommitTime
  )

  return [pscustomobject]@{
    installer = $InstallerName
    data = [pscustomobject]@{
      name = $DataName
      display = $DataDisplay
      url = $DataUrl
      ref = $DataRef
      sha = $DataSha
      commit_time = $DataCommitTime
    }
    weasel = [pscustomobject]@{
      name = $WeaselName
      display = $WeaselDisplay
      url = $WeaselUrl
      ref = $WeaselRef
      sha = $WeaselSha
      commit_time = $WeaselCommitTime
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

function Get-ManifestValue {
  param(
    [Parameter(Mandatory)]$Object,
    [Parameter(Mandatory)][string]$PropertyName,
    [string]$Default = ''
  )

  if ($null -eq $Object) {
    return $Default
  }
  if ($Object.PSObject.Properties.Name -contains $PropertyName) {
    $value = $Object.$PropertyName
    if ($null -ne $value -and -not [string]::IsNullOrWhiteSpace([string]$value)) {
      if ($value -is [datetime]) {
        return $value.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ', [Globalization.CultureInfo]::InvariantCulture)
      }
      if ($value -is [datetimeoffset]) {
        return $value.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ', [Globalization.CultureInfo]::InvariantCulture)
      }
      return [string]$value
    }
  }
  return $Default
}

function Format-SourceCell {
  param(
    [Parameter(Mandatory)]$Source
  )

  $name = Get-ManifestValue -Object $Source -PropertyName 'name'
  $display = Get-ManifestValue -Object $Source -PropertyName 'display' -Default $name
  $ref = Get-ManifestValue -Object $Source -PropertyName 'ref'
  $sha = Format-ShortSha (Get-ManifestValue -Object $Source -PropertyName 'sha')
  $commitTime = Get-ManifestValue -Object $Source -PropertyName 'commit_time'
  $url = Get-ManifestValue -Object $Source -PropertyName 'url'

  return "$display (``$name``)<br>``$ref`` @ ``$sha``<br>$commitTime<br>$url"
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
  $lines.Add('| 安装包 | 方案 | 小狼毫 |')
  $lines.Add('| --- | --- | --- |')

  foreach ($manifest in @($Manifests | Sort-Object installer)) {
    $installer = Get-ManifestValue -Object $manifest -PropertyName 'installer'
    $dataCell = Format-SourceCell -Source $manifest.data
    $weaselCell = Format-SourceCell -Source $manifest.weasel
    $lines.Add("| ``$installer`` | $dataCell | $weaselCell |")
  }

  return ($lines -join "`n") + "`n"
}

Export-ModuleMember -Function New-InstallerManifest,New-ReleaseNotes
