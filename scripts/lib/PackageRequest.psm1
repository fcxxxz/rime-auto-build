Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-PackageRequestField {
  param(
    [Parameter(Mandatory)][string]$Body,
    [Parameter(Mandatory)][string[]]$Names
  )

  $fieldPattern = ($Names | ForEach-Object { [regex]::Escape($_) }) -join '|'
  $pattern = "(?ms)^###\s+(?:$fieldPattern)\s*\r?\n(?<value>.*?)(?=^###\s+|\z)"
  $match = [regex]::Match($Body, $pattern)
  if (-not $match.Success) {
    return $null
  }

  $value = $match.Groups['value'].Value.Trim()
  if ($value -eq '_No response_') {
    return ''
  }
  return $value
}

function Resolve-PackageRequestGitHubUrl {
  param([Parameter(Mandatory)][string]$Url)

  $trimmed = $Url.Trim()
  $match = [regex]::Match($trimmed, '^https://github\.com/([A-Za-z0-9](?:[A-Za-z0-9-]{0,37}[A-Za-z0-9])?)/([A-Za-z0-9._-]+?)(?:\.git)?/?$')
  if (-not $match.Success) {
    throw "only public GitHub HTTPS repositories are supported: $Url"
  }

  $owner = $match.Groups[1].Value
  $repo = $match.Groups[2].Value
  if ([string]::IsNullOrWhiteSpace($repo) -or $repo -eq '.' -or $repo -eq '..') {
    throw "only public GitHub HTTPS repositories are supported: $Url"
  }

  return "https://github.com/$owner/$repo.git"
}

function Get-PackageRequestGitHubRepository {
  param([Parameter(Mandatory)][string]$Url)

  $normalized = Resolve-PackageRequestGitHubUrl $Url
  $match = [regex]::Match($normalized, '^https://github\.com/([^/]+)/([^/]+)\.git$')
  if (-not $match.Success) {
    throw "only public GitHub HTTPS repositories are supported: $Url"
  }

  return [pscustomobject]@{
    owner = $match.Groups[1].Value
    repo = $match.Groups[2].Value
    url = $normalized
  }
}

function Get-PackageRequestDerivedDataName {
  param([Parameter(Mandatory)][string]$RepositoryName)

  $name = $RepositoryName.Trim()
  $name = [regex]::Replace($name, '\.git$', '', 'IgnoreCase')
  $name = $name.ToLowerInvariant()
  $name = [regex]::Replace($name, '^(rime[-_.])', '')
  $name = [regex]::Replace($name, '[^a-z0-9]+', '-')
  $name = $name.Trim('-')

  if ([string]::IsNullOrWhiteSpace($name)) {
    throw "could not derive a package name from repository name: $RepositoryName"
  }
  if ($name.Length -gt 32) {
    $name = $name.Substring(0, 32).Trim('-')
  }
  if ($name.Length -lt 2) {
    throw "derived package name is too short: $name"
  }

  return $name
}

function Get-PackageRequestWeaselName {
  param([AllowNull()][string]$Value)

  $trimmed = if ($null -eq $Value) { '' } else { $Value.Trim() }
  foreach ($candidate in @('rime', 'qing', 'fxliang')) {
    $escaped = [regex]::Escape($candidate)
    if ($trimmed -eq $candidate -or
        $trimmed -match "(?i)^官方小狼毫[（(]$escaped[）)]$" -or
        $trimmed -match "(?i)^晴版小狼毫[（(]$escaped[）)]$" -or
        $trimmed -match "(?i)^fxliang 小狼毫[（(]$escaped[）)]$") {
      return $candidate
    }
  }

  return $trimmed
}

function ConvertFrom-PackageRequestIssueBody {
  param([Parameter(Mandatory)][string]$Body)

  $dataUrl = Get-PackageRequestField -Body $Body -Names @('Repository', '仓库', '公开 GitHub 仓库')
  if ([string]::IsNullOrWhiteSpace($dataUrl)) {
    throw "missing required issue field(s): Repository"
  }

  $repo = Get-PackageRequestGitHubRepository $dataUrl
  $derivedName = Get-PackageRequestDerivedDataName $repo.repo
  $legacyDataName = Get-PackageRequestField -Body $Body -Names @('Data short name', '方案短名')
  $legacyDisplay = Get-PackageRequestField -Body $Body -Names @('Display name', '显示名', '方案显示名')
  $dataName = if ($legacyDataName -and $legacyDataName.Trim() -match '^(?=.{2,32}$)[a-z0-9](?:[a-z0-9-]*[a-z0-9])$') {
    $legacyDataName.Trim()
  } else {
    $derivedName
  }
  $dataDisplay = if ($legacyDisplay -and $legacyDisplay.Trim() -notmatch '^\d+$') {
    $legacyDisplay.Trim()
  } else {
    $derivedName
  }

  $fields = [ordered]@{
    data_name = $dataName
    data_display = $dataDisplay
    data_url = $repo.url
    data_ref = Get-PackageRequestField -Body $Body -Names @('Ref', '分支或标签', '分支、标签或 commit')
    weasel_name = Get-PackageRequestWeaselName (Get-PackageRequestField -Body $Body -Names @('Weasel', '小狼毫版本'))
  }

  $missingFields = New-Object System.Collections.Generic.List[string]
  foreach ($entry in @(
    @{ Key = 'weasel_name'; Label = 'Weasel' }
  )) {
    if ([string]::IsNullOrWhiteSpace($fields[$entry.Key])) {
      $missingFields.Add($entry.Label)
    }
  }
  if ($missingFields.Count -gt 0) {
    throw "missing required issue field(s): $($missingFields -join ', ')"
  }

  $fields['data_name'] = $fields['data_name'].Trim()
  $fields['data_display'] = $fields['data_display'].Trim()
  $fields['data_ref'] = if ($fields['data_ref']) { $fields['data_ref'].Trim() } else { '' }
  $fields['weasel_name'] = $fields['weasel_name'].Trim()

  return [pscustomobject]$fields
}

function Resolve-PackageRequest {
  param(
    [Parameter(Mandatory)]$Request,
    [Parameter(Mandatory)]$Config
  )

  $dataName = [string]$Request.data_name
  if ($dataName -notmatch '^(?=.{2,32}$)[a-z0-9](?:[a-z0-9-]*[a-z0-9])$') {
    throw "data_name must match ^[a-z0-9][a-z0-9-]{1,31}$ and must not end with '-': $dataName"
  }

  $dataDisplay = [string]$Request.data_display
  if ([string]::IsNullOrWhiteSpace($dataDisplay)) {
    throw 'data_display must not be empty'
  }
  if ($dataDisplay -match '[\r\n]') {
    throw 'data_display must be a single line'
  }

  $dataRef = [string]$Request.data_ref
  if (-not [string]::IsNullOrWhiteSpace($dataRef) -and
      ($dataRef -notmatch '^[A-Za-z0-9._/-]{1,128}$' -or
      $dataRef.Contains('..') -or
      $dataRef.StartsWith('-') -or
      $dataRef.StartsWith('/') -or
      $dataRef.EndsWith('/') -or
      $dataRef.Contains('//'))) {
    throw "data_ref contains unsupported characters: $dataRef"
  }
  if (-not [string]::IsNullOrWhiteSpace($dataRef) -and $dataRef -match '^[0-9A-Fa-f]{4,39}$') {
    throw 'commit refs must be full 40-character SHA values'
  }

  $repo = Get-PackageRequestGitHubRepository ([string]$Request.data_url)

  $weaselName = ([string]$Request.weasel_name).Trim()
  if ($weaselName -match '[,\r\n/]') {
    throw "select exactly one weasel: $weaselName"
  }

  $weasel = @($Config.weasels | Where-Object { $_.name -eq $weaselName })
  if ($weasel.Count -ne 1) {
    throw "unknown weasel '$weaselName'"
  }

  return [pscustomobject]@{
    data_name = $dataName
    data_display = $dataDisplay
    data_url = $repo.url
    data_ref = $dataRef
    github_owner = $repo.owner
    github_repo = $repo.repo
    weasel_name = $weasel[0].name
    weasel_display = if ($weasel[0].PSObject.Properties.Name -contains 'display') { $weasel[0].display } else { $weasel[0].name }
    weasel_url = $weasel[0].url
    weasel_ref = $weasel[0].ref
  }
}

function Test-PackageRequestRimeDataShape {
  param([Parameter(Mandatory)][string]$Path)

  if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
    throw "custom-data path not found: $Path"
  }

  $defaultCustom = Join-Path $Path 'default.custom.yaml'
  if (Test-Path -LiteralPath $defaultCustom -PathType Leaf) {
    return $true
  }

  $schema = Get-ChildItem -LiteralPath $Path -File -Filter '*.schema.yaml' -ErrorAction SilentlyContinue |
    Select-Object -First 1
  return ($null -ne $schema)
}

Export-ModuleMember -Function `
  ConvertFrom-PackageRequestIssueBody, `
  Resolve-PackageRequestGitHubUrl, `
  Get-PackageRequestGitHubRepository, `
  Get-PackageRequestDerivedDataName, `
  Resolve-PackageRequest, `
  Test-PackageRequestRimeDataShape
