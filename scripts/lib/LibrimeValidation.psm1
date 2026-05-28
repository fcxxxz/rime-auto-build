function Test-PackCustomDataNeedsLua([string]$CustomDataDir) {
  if (-not (Test-Path -LiteralPath $CustomDataDir)) {
    return $false
  }

  if (Test-Path -LiteralPath (Join-Path $CustomDataDir 'lua')) {
    return $true
  }

  $luaComponentPattern = '\blua_(processor|translator|filter|segmentor)\b'
  $yamlFiles = @(
    Get-ChildItem -LiteralPath $CustomDataDir -Recurse -File -Include '*.yaml','*.yml' -ErrorAction SilentlyContinue
  )
  foreach ($file in $yamlFiles) {
    $content = [System.IO.File]::ReadAllText($file.FullName)
    if ($content -match $luaComponentPattern) {
      return $true
    }
  }

  return $false
}

function Test-PackRimeDllSupportsLua([string]$RimeDllPath) {
  if (-not (Test-Path -LiteralPath $RimeDllPath -PathType Leaf)) {
    return $false
  }

  $bytes = [System.IO.File]::ReadAllBytes($RimeDllPath)
  $text = [System.Text.Encoding]::ASCII.GetString($bytes)
  foreach ($component in @('lua_processor', 'lua_translator', 'lua_filter', 'lua_segmentor')) {
    if ($text.IndexOf($component, [StringComparison]::Ordinal) -lt 0) {
      return $false
    }
  }

  return $true
}

function Test-PackLibrimeLuaPluginReady([string]$PluginRoot) {
  if (-not (Test-Path -LiteralPath (Join-Path $PluginRoot 'CMakeLists.txt') -PathType Leaf)) {
    return $false
  }
  if (-not (Test-Path -LiteralPath (Join-Path $PluginRoot 'thirdparty\lua5.4\lua.h') -PathType Leaf)) {
    return $false
  }
  return $true
}

function Invoke-PackGit {
  param(
    [Parameter(Mandatory)][object]$GitCommand,
    [Parameter(Mandatory)][string[]]$Arguments,
    [Parameter(Mandatory)][string]$FailureMessage
  )

  & $GitCommand.Source @Arguments
  if ($LASTEXITCODE -ne 0) {
    throw $FailureMessage
  }
}

function Install-PackLibrimeLuaPlugin(
  [string]$WeaselRoot,
  [string]$CustomDataDir,
  [string]$GitCommandName = 'git',
  [string]$LibrimeLuaRef,
  [string]$LibrimeLuaThirdpartyRef,
  [switch]$Force
) {
  if (-not $Force -and -not (Test-PackCustomDataNeedsLua $CustomDataDir)) {
    return
  }

  $librimeRoot = Join-Path $WeaselRoot 'librime'
  $pluginsRoot = Join-Path $librimeRoot 'plugins'
  $pluginRoot = Join-Path $pluginsRoot 'lua'

  if (Test-PackLibrimeLuaPluginReady $pluginRoot) {
    Write-Host "librime-lua plugin already prepared: $pluginRoot"
    return
  }

  $git = Get-Command $GitCommandName -ErrorAction SilentlyContinue
  if (-not $git) {
    throw "custom-data requires librime-lua, but $GitCommandName is not available to install the librime-lua plugin."
  }

  if (-not (Test-Path -LiteralPath $pluginsRoot)) {
    New-Item -ItemType Directory -Path $pluginsRoot -Force | Out-Null
  }
  if (Test-Path -LiteralPath $pluginRoot) {
    Remove-Item -LiteralPath $pluginRoot -Recurse -Force
  }

  Write-Host "Installing librime-lua plugin into: $pluginRoot"
  Invoke-PackGit `
    -GitCommand $git `
    -Arguments @('clone', '--depth', '1', 'https://github.com/hchunhui/librime-lua.git', $pluginRoot) `
    -FailureMessage 'failed to clone hchunhui/librime-lua for custom-data Lua support.'
  if ($LibrimeLuaRef) {
    Invoke-PackGit `
      -GitCommand $git `
      -Arguments @('-C', $pluginRoot, 'checkout', '--detach', $LibrimeLuaRef) `
      -FailureMessage "failed to checkout librime-lua ref: $LibrimeLuaRef"
  }

  Invoke-PackGit `
    -GitCommand $git `
    -Arguments @('-C', $pluginRoot, 'clone', '--depth', '1', '-b', 'thirdparty', 'https://github.com/hchunhui/librime-lua.git', 'thirdparty') `
    -FailureMessage 'failed to clone librime-lua thirdparty Lua sources.'
  if ($LibrimeLuaThirdpartyRef) {
    Invoke-PackGit `
      -GitCommand $git `
      -Arguments @('-C', (Join-Path $pluginRoot 'thirdparty'), 'checkout', '--detach', $LibrimeLuaThirdpartyRef) `
      -FailureMessage "failed to checkout librime-lua thirdparty ref: $LibrimeLuaThirdpartyRef"
  }

  if (-not (Test-PackLibrimeLuaPluginReady $pluginRoot)) {
    throw "librime-lua plugin preparation incomplete: $pluginRoot"
  }
}

function Assert-PackLibrimeLuaSupport(
  [string]$WeaselRoot,
  [string]$CustomDataDir,
  [switch]$Force
) {
  if (-not $Force -and -not (Test-PackCustomDataNeedsLua $CustomDataDir)) {
    return
  }

  $dllPaths = @(
    Join-Path $WeaselRoot 'output\rime.dll'
    Join-Path $WeaselRoot 'output\Win32\rime.dll'
  )
  $missingLuaSupport = @($dllPaths | Where-Object {
    -not (Test-PackRimeDllSupportsLua $_)
  })

  if ($missingLuaSupport.Count -gt 0) {
    throw @"
custom-data requires librime-lua, but packaged rime.dll file(s) do not expose Lua components.

Missing librime-lua support:
  $($missingLuaSupport -join "`n  ")

Rebuild librime with librime-lua enabled, or replace the cached/prebuilt rime.dll files before packaging.
"@
  }
}

Export-ModuleMember -Function Test-PackCustomDataNeedsLua,Test-PackRimeDllSupportsLua,Install-PackLibrimeLuaPlugin,Assert-PackLibrimeLuaSupport
