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

function Format-ChinaTime {
  param(
    [Parameter(Mandatory)][string]$Value
  )

  if ([string]::IsNullOrWhiteSpace($Value)) {
    return ''
  }

  $styles = [Globalization.DateTimeStyles]::AssumeUniversal -bor [Globalization.DateTimeStyles]::AdjustToUniversal
  $timestamp = [datetimeoffset]::Parse($Value, [Globalization.CultureInfo]::InvariantCulture, $styles)
  return $timestamp.ToUniversalTime().AddHours(8).ToString('yyyy-MM-dd HH:mm:ss', [Globalization.CultureInfo]::InvariantCulture)
}

function Format-SourceSummaryCell {
  param(
    [Parameter(Mandatory)]$Source
  )

  $name = Get-ManifestValue -Object $Source -PropertyName 'name'
  $display = Get-ManifestValue -Object $Source -PropertyName 'display' -Default $name
  $commitTime = Format-ChinaTime (Get-ManifestValue -Object $Source -PropertyName 'commit_time')

  if ([string]::IsNullOrWhiteSpace($commitTime)) {
    return $display
  }
  return "$display<br>$commitTime"
}

function Format-InstallerLink {
  param(
    [Parameter(Mandatory)][string]$InstallerName,
    [Parameter(Mandatory)][string]$ReleaseTag,
    [Parameter(Mandatory)][string]$Repository
  )

  if ([string]::IsNullOrWhiteSpace($ReleaseTag) -or [string]::IsNullOrWhiteSpace($Repository)) {
    return "``$InstallerName``"
  }

  $encodedName = [Uri]::EscapeDataString($InstallerName)
  return "[$InstallerName](https://github.com/$Repository/releases/download/$ReleaseTag/$encodedName)"
}

function ConvertFrom-ReleaseNotes {
  param(
    [Parameter(Mandatory)][string]$Markdown
  )

  $manifests = New-Object System.Collections.Generic.List[object]
  $rowPattern = '^\|\s*`(?<installer>[^`]+)`\s*\|\s*(?<data>.*?)\s*\|\s*(?<weasel>.*?)\s*\|\s*$'
  foreach ($line in @($Markdown -split "`r?`n")) {
    $row = [regex]::Match($line, $rowPattern)
    if (-not $row.Success) {
      continue
    }

    $data = ConvertFrom-OldSourceCell -Cell $row.Groups['data'].Value
    $weasel = ConvertFrom-OldSourceCell -Cell $row.Groups['weasel'].Value
    if ($null -eq $data -or $null -eq $weasel) {
      continue
    }

    $manifests.Add([pscustomobject]@{
      installer = $row.Groups['installer'].Value
      data = $data
      weasel = $weasel
    })
  }

  return $manifests.ToArray()
}

function ConvertFrom-OldSourceCell {
  param(
    [Parameter(Mandatory)][string]$Cell
  )

  $parts = @($Cell -split '<br>')
  if ($parts.Count -lt 4) {
    return $null
  }

  $nameMatch = [regex]::Match($parts[0].Trim(), '^(?<display>.*?)\s+\(`(?<name>[^`]+)`\)$')
  $revMatch = [regex]::Match($parts[1].Trim(), '^`(?<ref>[^`]+)`\s+@\s+`(?<sha>[^`]+)`$')
  if (-not $nameMatch.Success -or -not $revMatch.Success) {
    return $null
  }

  return [pscustomobject]@{
    name = $nameMatch.Groups['name'].Value
    display = $nameMatch.Groups['display'].Value
    url = $parts[3].Trim()
    ref = $revMatch.Groups['ref'].Value
    sha = $revMatch.Groups['sha'].Value
    commit_time = $parts[2].Trim()
  }
}

function New-ReleaseNotes {
  param(
    [Parameter(Mandatory)][string]$EventName,
    [Parameter(Mandatory)][string]$StatePath,
    [Parameter(Mandatory)][string]$BuildsPath,
    [string]$ReleaseTag = '',
    [string]$Repository = '',
    [Parameter(Mandatory)][object[]]$Manifests
  )

  $lines = New-Object System.Collections.Generic.List[string]
  $lines.Add('自动构建。')
  $lines.Add('')
  $lines.Add("- 触发：``$EventName``")
  $lines.Add("- SHA 快照：见 ``$StatePath``")
  $lines.Add("- 配置：见 ``$BuildsPath``")
  if (-not [string]::IsNullOrWhiteSpace($ReleaseTag)) {
    $lines.Add("- Release：``$ReleaseTag``")
  }
  $lines.Add('')
  $lines.Add('## 安装包说明')
  $lines.Add('')
  $lines.Add('| 方案 | 小狼毫 | 安装包 |')
  $lines.Add('| --- | --- | --- |')

  foreach ($manifest in @($Manifests | Sort-Object installer)) {
    $installer = Get-ManifestValue -Object $manifest -PropertyName 'installer'
    $dataCell = Format-SourceSummaryCell -Source $manifest.data
    $weaselCell = Format-SourceSummaryCell -Source $manifest.weasel
    $installerCell = Format-InstallerLink -InstallerName $installer -ReleaseTag $ReleaseTag -Repository $Repository
    $lines.Add("| $dataCell | $weaselCell | $installerCell |")
  }

  return ($lines -join "`n") + "`n"
}

Export-ModuleMember -Function New-InstallerManifest,New-ReleaseNotes,ConvertFrom-ReleaseNotes
