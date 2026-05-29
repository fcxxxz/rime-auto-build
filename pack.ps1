$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $PSCommandPath
Import-Module (Join-Path $ScriptDir 'scripts\lib\Toolchain.psm1') -Force
Import-Module (Join-Path $ScriptDir 'scripts\lib\CustomData.psm1') -Force
Import-Module (Join-Path $ScriptDir 'scripts\lib\LibrimeValidation.psm1') -Force
Import-Module (Join-Path $ScriptDir 'scripts\lib\NsiPatch.psm1') -Force
Import-Module (Join-Path $ScriptDir 'scripts\lib\WeaselSourcePatch.psm1') -Force

# ---------------------------------------------------------------------------
# User-tweakable paths and options.
# All package inputs and outputs are resolved relative to this script's folder
# and must remain inside it. Toolchain paths such as VsDevCmd can still be
# absolute because they are external prerequisites, not package work folders.
# ---------------------------------------------------------------------------
$WeaselRepoPath    = '.\weasel'         # bundled weasel source repo under this folder
$WorkRootPath      = '.\.pack-work'     # generated build workspace; source weasel is never modified
$LibrimeSourcePath = '.\librime'        # used only when .\weasel\librime is incomplete
$PlumSourcePath    = '.\plum'           # used only when .\weasel\plum is incomplete
$CustomDataDirPath = '.\custom-data'    # your schemas, dicts, lua, opencc, etc.
$BoostRootPath     = '.\boost_1_84_0'   # boost source root that ships with this folder
$OutputDirPath     = '.'                # where the final installer is copied

$BuildArch         = 'x64'              # x64 | Win32 | arm64

# Leave $null to auto-detect. Override only if auto-detect picks the wrong thing.
$VsDevCmdPath      = $null              # path to VsDevCmd.bat (any VS 2022 edition)
$MsvcToolsVersion  = $env:PACK_MSVC_TOOLS_VERSION  # e.g. '14.51.36231'; $null = VsDevCmd default
$SdkVer            = $null              # e.g. '10.0.22621.0'; $null = latest installed
$PlatformToolset   = $null              # e.g. 'v143'; $null = auto from VS edition
$BjamToolset       = $null              # e.g. 'msvc-14.3'; $null = auto from VS edition

function Resolve-PackPath([string]$Path) {
  $expanded = [Environment]::ExpandEnvironmentVariables($Path)
  if ([System.IO.Path]::IsPathRooted($expanded)) {
    return [System.IO.Path]::GetFullPath($expanded)
  }
  return [System.IO.Path]::GetFullPath((Join-Path $ScriptDir $expanded))
}

function Test-PathUnderRoot([string]$Path, [string]$Root) {
  $trimChars = [char[]]@([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
  $full = [System.IO.Path]::GetFullPath($Path).TrimEnd($trimChars)
  $rootFull = [System.IO.Path]::GetFullPath($Root).TrimEnd($trimChars)
  return $full.Equals($rootFull, [StringComparison]::OrdinalIgnoreCase) -or
    $full.StartsWith($rootFull + [System.IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)
}

function Require-PathUnderScriptDir([string]$Path, [string]$Name) {
  if (-not (Test-PathUnderRoot $Path $ScriptDir)) {
    throw @"
$Name must stay under the packaging folder.
  Packaging folder: $ScriptDir
  Resolved path    : $Path

Move/copy the required files into this folder instead of pointing pack.ps1 at a sibling or external directory.
"@
  }
}

function Require-Path([string]$Path, [string]$Name) {
  if (-not (Test-Path -LiteralPath $Path)) {
    throw "$Name not found: $Path"
  }
}

function Test-GitWorkTree([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path)) {
    return $false
  }
  if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    return $false
  }

  $oldErrorActionPreference = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try {
    $inside = & git -C $Path rev-parse --is-inside-work-tree 2>$null
    return ($LASTEXITCODE -eq 0 -and "$inside".Trim() -eq 'true')
  } finally {
    $ErrorActionPreference = $oldErrorActionPreference
  }
}

function Initialize-WeaselWorkTree([string]$SourceRoot, [string]$WorkTreeRoot) {
  Require-PathUnderScriptDir $SourceRoot 'Weasel source repo'
  Require-PathUnderScriptDir $WorkTreeRoot 'Weasel work tree'

  if (Test-PathUnderRoot $WorkTreeRoot $SourceRoot) {
    throw @"
Weasel work tree must not be inside the source repo.
  Source: $SourceRoot
  Work  : $WorkTreeRoot
"@
  }
  if (Test-PathUnderRoot $SourceRoot $WorkTreeRoot) {
    throw @"
Weasel source repo must not be inside the generated work tree.
  Source: $SourceRoot
  Work  : $WorkTreeRoot
"@
  }

  $workParent = Split-Path -Parent $WorkTreeRoot
  if (-not (Test-Path -LiteralPath $workParent)) {
    New-Item -ItemType Directory -Path $workParent -Force | Out-Null
  }

  Write-Host "Preparing isolated Weasel work tree..."
  Write-Host "  source: $SourceRoot"
  Write-Host "  work  : $WorkTreeRoot"

  $robo = Get-Command robocopy.exe -ErrorAction SilentlyContinue
  if ($robo) {
    & $robo.Source $SourceRoot $WorkTreeRoot /MIR /R:2 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
    if ($LASTEXITCODE -gt 7) {
      throw "robocopy failed while preparing isolated Weasel work tree (exit code $LASTEXITCODE)."
    }
  } else {
    if (Test-Path -LiteralPath $WorkTreeRoot) {
      Remove-Item -LiteralPath $WorkTreeRoot -Recurse -Force
    }
    New-Item -ItemType Directory -Path $WorkTreeRoot -Force | Out-Null
    Get-ChildItem -LiteralPath $SourceRoot -Force | ForEach-Object {
      Copy-Item -LiteralPath $_.FullName -Destination $WorkTreeRoot -Recurse -Force
    }
  }
}

function Copy-PackDirectoryMirror([string]$SourceRoot, [string]$TargetRoot, [string]$Name) {
  Require-PathUnderScriptDir $SourceRoot "$Name source"
  Require-PathUnderScriptDir $TargetRoot "$Name work target"

  $parent = Split-Path -Parent $TargetRoot
  if (-not (Test-Path -LiteralPath $parent)) {
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
  }

  $robo = Get-Command robocopy.exe -ErrorAction SilentlyContinue
  if ($robo) {
    & $robo.Source $SourceRoot $TargetRoot /MIR /R:2 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
    if ($LASTEXITCODE -gt 7) {
      throw "robocopy failed while copying $Name source into the work tree (exit code $LASTEXITCODE)."
    }
  } else {
    if (Test-Path -LiteralPath $TargetRoot) {
      Remove-Item -LiteralPath $TargetRoot -Recurse -Force
    }
    New-Item -ItemType Directory -Path $TargetRoot -Force | Out-Null
    Get-ChildItem -LiteralPath $SourceRoot -Force | ForEach-Object {
      Copy-Item -LiteralPath $_.FullName -Destination $TargetRoot -Recurse -Force
    }
  }
}

function Ensure-WorkTreeDependencySource(
  [string]$WeaselWorkRoot,
  [string]$DependencyName,
  [string]$SourceRoot,
  [string[]]$RequiredMarkers
) {
  Require-PathUnderScriptDir $WeaselWorkRoot 'Weasel work tree'
  Require-PathUnderScriptDir $SourceRoot "$DependencyName source"

  $missing = @($RequiredMarkers | Where-Object {
    -not (Test-Path -LiteralPath (Join-Path $WeaselWorkRoot $_))
  })
  if ($missing.Count -eq 0) {
    return
  }

  if (-not (Test-Path -LiteralPath $SourceRoot)) {
    Write-Host "Package-local $DependencyName source not found: $SourceRoot"
    Write-Host "  Will use the copy already under .\weasel if complete, or git submodule fallback if available."
    return
  }

  $target = Join-Path $WeaselWorkRoot $DependencyName
  Write-Host "Using package-local .\$DependencyName because work-tree $DependencyName is incomplete..."
  Copy-PackDirectoryMirror $SourceRoot $target $DependencyName

  $stillMissing = @($RequiredMarkers | Where-Object {
    -not (Test-Path -LiteralPath (Join-Path $WeaselWorkRoot $_))
  })
  if ($stillMissing.Count -gt 0) {
    throw @"
Package-local $DependencyName source is incomplete:
  $SourceRoot

Missing after copy:
  $($stillMissing -join "`n  ")
"@
  }
}

function Get-MissingLibrimeFiles([string]$WeaselRoot) {
  $required = @(
    'include\rime_api.h',
    'lib64\rime.lib',
    'lib\rime.lib',
    'output\rime.dll',
    'output\Win32\rime.dll'
  )
  return @($required | Where-Object {
    -not (Test-Path -LiteralPath (Join-Path $WeaselRoot $_))
  })
}

function Write-WeaselEnvBat([string]$WeaselRoot) {
  $envBat = Join-Path $WeaselRoot 'env.bat'
  [System.IO.File]::WriteAllLines(
    $envBat,
    [string[]]@(
      'rem Generated by pack.ps1 - defaults only apply when not already set by the caller.',
      'if not defined BOOST_ROOT set BOOST_ROOT=C:\Libraries\boost_1_78_0'
    ),
    [System.Text.Encoding]::ASCII
  )
}

function Invoke-GetRimePrebuilt([string]$WeaselRoot) {
  Write-Host 'Falling back to get-rime.ps1 for prebuilt librime (needs network, ~50MB)...'
  $getRime = Join-Path $WeaselRoot 'get-rime.ps1'
  Require-Path $getRime 'weasel\get-rime.ps1'
  Push-Location $WeaselRoot
  try {
    & $getRime -use dev -extract $true
    if (-not $?) {
      throw "get-rime.ps1 failed. Check your network/GitHub access."
    }
  } finally { Pop-Location }
}

function Get-PackArchiveExtractor {
  foreach ($name in @('7z', '7zz', '7za', '7zr', 'bz')) {
    $cmd = Get-Command $name -ErrorAction SilentlyContinue
    if ($cmd) {
      return $cmd
    }
  }
  throw @"
No archive extractor found for librime release .7z files.

Install 7-Zip and put 7z.exe in PATH, or install Bandizip so bz.exe is in PATH.
"@
}

function Expand-PackSevenZipArchive(
  [string]$ArchivePath,
  [string]$DestinationPath,
  [object]$ExtractorCommand,
  [string]$SafeRoot
) {
  Require-PathUnderScriptDir $ArchivePath 'librime release archive'
  Require-PathUnderScriptDir $DestinationPath 'librime release extraction directory'
  if (-not (Test-PathUnderRoot $DestinationPath $SafeRoot)) {
    throw @"
Refusing to extract outside the generated work tree.
  Work tree  : $SafeRoot
  Destination: $DestinationPath
"@
  }

  if (Test-Path -LiteralPath $DestinationPath) {
    Remove-Item -LiteralPath $DestinationPath -Recurse -Force
  }
  New-Item -ItemType Directory -Path $DestinationPath -Force | Out-Null

  if ($ExtractorCommand.Name -like 'bz*') {
    & $ExtractorCommand.Source x -aoa -y "-o:$DestinationPath" $ArchivePath | Out-Null
  } else {
    & $ExtractorCommand.Source x $ArchivePath "-o$DestinationPath" -y | Out-Null
  }
  if ($LASTEXITCODE -ne 0) {
    throw "Failed to extract librime archive: $ArchivePath"
  }
}

function Copy-PackFilesIfPresent([string]$SourceDir, [string]$Filter, [string]$DestinationDir) {
  if (-not (Test-Path -LiteralPath $SourceDir)) {
    return
  }
  if (-not (Test-Path -LiteralPath $DestinationDir)) {
    New-Item -ItemType Directory -Path $DestinationDir -Force | Out-Null
  }
  Get-ChildItem -LiteralPath $SourceDir -Filter $Filter -File -ErrorAction SilentlyContinue | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination $DestinationDir -Force
  }
}

function Copy-PackRimeReleasePayload([string]$ExtractRoot, [string]$WeaselRoot) {
  $releaseDirs = @(Get-ChildItem -LiteralPath $ExtractRoot -Directory -ErrorAction SilentlyContinue)
  foreach ($dir in $releaseDirs) {
    if ($dir.Name -match 'Windows-msvc-x86$') {
      Copy-PackFilesIfPresent (Join-Path $dir.FullName 'dist\include') 'rime_*.h' (Join-Path $WeaselRoot 'include')
      Copy-PackFilesIfPresent (Join-Path $dir.FullName 'dist\lib') 'rime.lib' (Join-Path $WeaselRoot 'lib')
      Copy-PackFilesIfPresent (Join-Path $dir.FullName 'dist\lib') 'rime.dll' (Join-Path $WeaselRoot 'output\Win32')
      Copy-PackFilesIfPresent (Join-Path $dir.FullName 'dist\lib') 'rime.pdb' (Join-Path $WeaselRoot 'output\Win32')
    }

    if ($dir.Name -match 'Windows-msvc-x64$') {
      Copy-PackFilesIfPresent (Join-Path $dir.FullName 'dist\include') 'rime_*.h' (Join-Path $WeaselRoot 'include')
      Copy-PackFilesIfPresent (Join-Path $dir.FullName 'dist\lib') 'rime.lib' (Join-Path $WeaselRoot 'lib64')
      Copy-PackFilesIfPresent (Join-Path $dir.FullName 'dist\lib') 'rime.dll' (Join-Path $WeaselRoot 'output')
      Copy-PackFilesIfPresent (Join-Path $dir.FullName 'dist\lib') 'rime.pdb' (Join-Path $WeaselRoot 'output')
      Copy-PackFilesIfPresent (Join-Path $dir.FullName 'share\opencc') '*.*' (Join-Path $WeaselRoot 'output\data\opencc')
    }
  }
}

function Invoke-GetRimePrebuiltWithGitHubCli([string]$WeaselRoot) {
  $gh = Get-Command gh -ErrorAction SilentlyContinue
  if (-not $gh) {
    Write-Warning 'GitHub CLI (gh) is not available; cannot use authenticated librime release fallback.'
    return
  }

  $extractor = Get-PackArchiveExtractor
  $cacheRoot = Join-Path $WeaselRoot '.pack-rime'
  $downloadRoot = Join-Path $cacheRoot 'downloads'
  $extractRoot = Join-Path $cacheRoot 'extracted'
  foreach ($path in @($cacheRoot, $downloadRoot, $extractRoot)) {
    Require-PathUnderScriptDir $path 'librime GitHub CLI cache'
    if (-not (Test-PathUnderRoot $path $WeaselRoot)) {
      throw "librime GitHub CLI cache must stay under the generated work tree: $path"
    }
    if (-not (Test-Path -LiteralPath $path)) {
      New-Item -ItemType Directory -Path $path -Force | Out-Null
    }
  }
  $stableDownloadRoot = Join-Path $ScriptDir '.pack-rime-cache\downloads'
  Require-PathUnderScriptDir $stableDownloadRoot 'stable librime release download cache'
  if (-not (Test-Path -LiteralPath $stableDownloadRoot)) {
    New-Item -ItemType Directory -Path $stableDownloadRoot -Force | Out-Null
  }

  Write-Host 'Downloading prebuilt librime with GitHub CLI (authenticated fallback)...'
  $releaseJson = & $gh.Source release view --repo rime/librime --json tagName,assets
  if ($LASTEXITCODE -ne 0) {
    Write-Warning 'gh release view failed; cannot use GitHub CLI librime fallback.'
    return
  }
  $release = $releaseJson | ConvertFrom-Json
  $assets = @($release.assets | Where-Object {
    $_.name -match '^rime(-deps)?-[0-9a-fA-F]+-Windows-msvc-x(64|86)\.7z$'
  })
  if ($assets.Count -eq 0) {
    Write-Warning "No Windows MSVC librime assets found in rime/librime release $($release.tagName)."
    return
  }

  foreach ($asset in $assets) {
    $archivePath = Join-Path $downloadRoot $asset.name
    $stableArchivePath = Join-Path $stableDownloadRoot $asset.name
    if ((Test-Path -LiteralPath $stableArchivePath) -and ((Get-Item -LiteralPath $stableArchivePath).Length -eq $asset.size)) {
      Copy-Item -LiteralPath $stableArchivePath -Destination $archivePath -Force
    }
    if ((-not (Test-Path -LiteralPath $archivePath)) -or ((Get-Item -LiteralPath $archivePath).Length -ne $asset.size)) {
      Remove-Item -LiteralPath $archivePath -Force -ErrorAction SilentlyContinue
      & $gh.Source release download $release.tagName --repo rime/librime --pattern $asset.name --dir $downloadRoot --clobber
      if ($LASTEXITCODE -ne 0) {
        throw "gh release download failed for librime asset: $($asset.name)"
      }
      if ((Get-Item -LiteralPath $archivePath).Length -ne $asset.size) {
        throw "gh release download produced incomplete librime asset: $($asset.name)"
      }
      Copy-Item -LiteralPath $archivePath -Destination $stableArchivePath -Force
    }
    $assetExtractRoot = Join-Path $extractRoot ([System.IO.Path]::GetFileNameWithoutExtension($asset.name))
    Expand-PackSevenZipArchive $archivePath $assetExtractRoot $extractor $WeaselRoot
  }

  Copy-PackRimeReleasePayload $extractRoot $WeaselRoot
}

function Invoke-LibrimePrebuiltFallback([string]$WeaselRoot) {
  Invoke-GetRimePrebuilt $WeaselRoot
  $missingAfterGetRime = Get-MissingLibrimeFiles $WeaselRoot
  if ($missingAfterGetRime.Count -gt 0) {
    Invoke-GetRimePrebuiltWithGitHubCli $WeaselRoot
  }
}

function Ensure-OutputDataBuildGuards([string]$WeaselRoot) {
  $outputData = Join-Path $WeaselRoot 'output\data'
  if (-not (Test-Path -LiteralPath $outputData)) {
    New-Item -ItemType Directory -Path $outputData -Force | Out-Null
  }

  $outputEssay = Join-Path $outputData 'essay.txt'
  if (-not (Test-Path -LiteralPath $outputEssay)) {
    $minimalEssay = Join-Path $WeaselRoot 'librime\data\minimal\essay.txt'
    if (Test-Path -LiteralPath $minimalEssay) {
      Copy-Item -LiteralPath $minimalEssay -Destination $outputEssay -Force
    }
  }

  $openccOut = Join-Path $outputData 'opencc'
  $hasOpenCcData = Test-Path -LiteralPath (Join-Path $openccOut 'TSCharacters.ocd2')
  if (-not $hasOpenCcData) {
    $openccShare = Join-Path $WeaselRoot 'librime\share\opencc'
    if (Test-Path -LiteralPath $openccShare) {
      if (-not (Test-Path -LiteralPath $openccOut)) {
        New-Item -ItemType Directory -Path $openccOut -Force | Out-Null
      }
      Get-ChildItem -LiteralPath $openccShare -File | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination $openccOut -Force
      }
    }
  }
}

function Ensure-OutputInstallerSupportFiles([string]$WeaselRoot) {
  $output = Join-Path $WeaselRoot 'output'
  if (-not (Test-Path -LiteralPath $output)) {
    New-Item -ItemType Directory -Path $output -Force | Out-Null
  }

  $licenseSrc = Join-Path $WeaselRoot 'LICENSE.txt'
  $licenseDst = Join-Path $output 'LICENSE.txt'
  if ((Test-Path -LiteralPath $licenseSrc) -and -not (Test-Path -LiteralPath $licenseDst)) {
    Copy-Item -LiteralPath $licenseSrc -Destination $licenseDst -Force
  }

  $readmeSrc = Join-Path $WeaselRoot 'README.md'
  $readmeDst = Join-Path $output 'README.txt'
  if ((Test-Path -LiteralPath $readmeSrc) -and -not (Test-Path -LiteralPath $readmeDst)) {
    Copy-Item -LiteralPath $readmeSrc -Destination $readmeDst -Force
  }

  $rimeInstall = Join-Path $output 'rime-install.bat'
  if (Test-Path -LiteralPath $rimeInstall) {
    return
  }

  $plumRimeInstall = Join-Path $WeaselRoot 'plum\rime-install.bat'
  Require-Path $plumRimeInstall 'plum\rime-install.bat (in isolated work tree)'
  Copy-Item -LiteralPath $plumRimeInstall -Destination $rimeInstall -Force
}

function Require-Command([string]$Name, [string]$Hint) {
  $cmd = Get-Command $Name -ErrorAction SilentlyContinue
  if (-not $cmd) {
    throw "Required tool '$Name' not found in PATH.`n  $Hint"
  }
  return $cmd.Source
}

function Get-WeaselCustomThemePatch([string]$Path) {
  $result = @{
    Schemes = New-Object System.Collections.Generic.List[object]
    ColorScheme = $null
  }
  if (-not (Test-Path -LiteralPath $Path)) {
    return $result
  }

  $lines = [System.IO.File]::ReadAllLines($Path)
  for ($i = 0; $i -lt $lines.Count; $i++) {
    $line = $lines[$i]
    if ($line -match '^\s{2}"?preset_color_schemes/([^":]+)"?\s*:\s*$') {
      $scheme = @{
        Id = $Matches[1]
        Lines = New-Object System.Collections.Generic.List[string]
      }
      $scheme.Lines.Add("  $($scheme.Id):")
      $j = $i + 1
      while ($j -lt $lines.Count) {
        $next = $lines[$j]
        if ($next -match '^\s{2}\S' -and $next -notmatch '^\s{4}') {
          break
        }
        $scheme.Lines.Add($next)
        $j++
      }
      $result.Schemes.Add($scheme)
      $i = $j - 1
      continue
    }

    if ($line -match '^\s{2}"?style/color_scheme"?\s*:\s*([^#\s]+)') {
      $result.ColorScheme = $Matches[1].Trim('"', "'")
    }
  }
  return $result
}

function Merge-WeaselCustomThemePatch(
  [string]$WeaselYamlPath,
  [string]$WeaselCustomPath
) {
  if (-not (Test-Path -LiteralPath $WeaselYamlPath)) {
    return
  }
  $patch = Get-WeaselCustomThemePatch $WeaselCustomPath
  if ($patch.Schemes.Count -eq 0 -and -not $patch.ColorScheme) {
    return
  }

  $lines = [System.IO.File]::ReadAllLines($WeaselYamlPath)
  $out = New-Object System.Collections.Generic.List[string]
  $inStyle = $false
  $styleColorSet = $false
  $inPreset = $false
  $presetInserted = $false
  $existingSchemeIds = New-Object System.Collections.Generic.HashSet[string]([StringComparer]::OrdinalIgnoreCase)
  foreach ($line in $lines) {
    if ($line -match '^\s{2}([A-Za-z0-9_.-]+)\s*:\s*$') {
      [void]$existingSchemeIds.Add($Matches[1])
    }
  }

  foreach ($line in $lines) {
    if ($inStyle -and $line -match '^\S') {
      if (-not $styleColorSet -and $patch.ColorScheme) {
        $out.Add("  color_scheme: $($patch.ColorScheme)")
      }
      $inStyle = $false
    }

    if ($inPreset -and $line -match '^\S') {
      if (-not $presetInserted) {
        foreach ($scheme in $patch.Schemes) {
          if (-not $existingSchemeIds.Contains($scheme.Id)) {
            foreach ($schemeLine in $scheme.Lines) { $out.Add($schemeLine) }
          }
        }
        $presetInserted = $true
      }
      $inPreset = $false
    }

    if ($line -match '^style\s*:\s*$') {
      $inStyle = $true
      $styleColorSet = $false
      $out.Add($line)
      continue
    }

    if ($inStyle -and $line -match '^\s{2}color_scheme\s*:') {
      if ($patch.ColorScheme) {
        $out.Add("  color_scheme: $($patch.ColorScheme)")
      } else {
        $out.Add($line)
      }
      $styleColorSet = $true
      continue
    }

    if ($line -match '^preset_color_schemes\s*:\s*$') {
      $inPreset = $true
      $out.Add($line)
      continue
    }

    $out.Add($line)
  }

  if ($inStyle -and -not $styleColorSet -and $patch.ColorScheme) {
    $out.Add("  color_scheme: $($patch.ColorScheme)")
  }
  if ($inPreset -and -not $presetInserted) {
    foreach ($scheme in $patch.Schemes) {
      if (-not $existingSchemeIds.Contains($scheme.Id)) {
        foreach ($schemeLine in $scheme.Lines) { $out.Add($schemeLine) }
      }
    }
  }

  [System.IO.File]::WriteAllLines($WeaselYamlPath, $out, [System.Text.UTF8Encoding]::new($false))
}

# ---------------------------------------------------------------------------
# Step 0a: Resolve user-supplied paths.
# ---------------------------------------------------------------------------
$WeaselSource  = Resolve-PackPath $WeaselRepoPath
$WorkRoot      = Resolve-PackPath $WorkRootPath
$WeaselRepo    = Join-Path $WorkRoot 'weasel'
$LibrimeSource = Resolve-PackPath $LibrimeSourcePath
$PlumSource    = Resolve-PackPath $PlumSourcePath
$CustomDataDir = Resolve-PackPath $CustomDataDirPath
$BoostRoot     = Resolve-PackPath $BoostRootPath
$OutputDir     = Resolve-PackPath $OutputDirPath

Require-PathUnderScriptDir $WeaselSource  'Weasel source repo'
Require-PathUnderScriptDir $WorkRoot      'Work root'
Require-PathUnderScriptDir $WeaselRepo    'Weasel work tree'
Require-PathUnderScriptDir $LibrimeSource 'librime source'
Require-PathUnderScriptDir $PlumSource    'plum source'
Require-PathUnderScriptDir $CustomDataDir 'custom-data dir'
Require-PathUnderScriptDir $BoostRoot     'Boost root'
Require-PathUnderScriptDir $OutputDir     'Output dir'

Require-Path $CustomDataDir 'custom-data dir'
Require-Path $BoostRoot     'Boost root (drop boost_1_xx_x next to pack.ps1 or edit $BoostRootPath)'
Require-Path (Join-Path $BoostRoot 'boost') 'Boost headers (expected boost\boost\ subdirectory)'

if (-not (Test-Path -LiteralPath $WeaselSource)) {
  throw @"
Weasel source repo not found: $WeaselSource

Expected layout:
  <pack-folder>\
    pack.ps1
    weasel\                       <- bundled weasel source tree
    librime\                      <- package-local fallback when weasel\librime is incomplete
    plum\                         <- package-local fallback when weasel\plum is incomplete
    custom-data\
    boost_1_84_0\

Copy the weasel source tree into this folder, or edit `$WeaselRepoPath to another subdirectory inside this folder.
"@
}
Require-Path (Join-Path $WeaselSource 'build.bat') 'weasel\build.bat'

Initialize-WeaselWorkTree $WeaselSource $WeaselRepo
Ensure-WorkTreeDependencySource $WeaselRepo 'librime' $LibrimeSource @(
  'librime\data\minimal\default.yaml',
  'librime\data\minimal\essay.txt',
  'librime\build.bat'
)
Ensure-WorkTreeDependencySource $WeaselRepo 'plum' $PlumSource @(
  'plum\rime-install.bat'
)
Require-Path (Join-Path $WeaselRepo 'build.bat') 'work tree weasel\build.bat'

# ---------------------------------------------------------------------------
# Step 0b: Auto-detect VsDevCmd / SDK / toolset if not overridden.
# ---------------------------------------------------------------------------
function Find-VsDevCmd {
  $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
  if (-not (Test-Path -LiteralPath $vswhere)) {
    throw @"
Visual Studio Installer's vswhere.exe not found.

Install one of (free for personal/open-source use):
  - Visual Studio 2022 Build Tools   https://visualstudio.microsoft.com/downloads/#build-tools-for-visual-studio-2022
  - Visual Studio 2022 Community     https://visualstudio.microsoft.com/downloads/

Required workload: "Desktop development with C++" (includes MSVC, ATL, MFC, Windows SDK).
"@
  }
  # Prefer the newest VS2022 install that has the C++ toolset.
  $instPath = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath 2>$null
  if (-not $instPath) {
    throw "No Visual Studio install with C++ toolset (Microsoft.VisualStudio.Component.VC.Tools.x86.x64) found. Add the 'Desktop development with C++' workload in the VS Installer."
  }
  $candidate = Join-Path $instPath 'Common7\Tools\VsDevCmd.bat'
  if (-not (Test-Path -LiteralPath $candidate)) {
    throw "VsDevCmd.bat missing under detected VS install: $candidate"
  }
  return $candidate
}

function Detect-Toolset([string]$vsDevCmd) {
  return Get-DefaultToolsetForVsDevCmd $vsDevCmd
}

function Detect-LatestSdk {
  $sdkRoot = "${env:ProgramFiles(x86)}\Windows Kits\10\Include"
  if (-not (Test-Path -LiteralPath $sdkRoot)) {
    throw @"
Windows 10/11 SDK not found at $sdkRoot.

Install via VS Installer (component: 'Windows 11 SDK' or 'Windows 10 SDK'),
or standalone: https://developer.microsoft.com/windows/downloads/windows-sdk/
"@
  }
  $versions = Get-ChildItem -LiteralPath $sdkRoot -Directory |
    Where-Object { $_.Name -match '^10\.\d+\.\d+\.\d+$' } |
    Sort-Object { [Version]$_.Name } -Descending
  if (-not $versions) {
    throw "No Windows SDK versions found under $sdkRoot."
  }
  return $versions[0].Name
}

if ($VsDevCmdPath) {
  $VsDevCmd = Resolve-PackPath $VsDevCmdPath
  Require-Path $VsDevCmd 'VsDevCmd.bat (override)'
} else {
  $VsDevCmd = Find-VsDevCmd
}
if (-not $SdkVer)          { $SdkVer = Detect-LatestSdk }
if (-not $PlatformToolset -or -not $BjamToolset) {
  $auto = Detect-Toolset $VsDevCmd
  if (-not $PlatformToolset) { $PlatformToolset = $auto.Platform }
  if (-not $BjamToolset)     { $BjamToolset     = $auto.Bjam }
}
$VsDevCmdCall = New-VsDevCmdCall -VsDevCmd $VsDevCmd -MsvcToolsVersion $MsvcToolsVersion

# ---------------------------------------------------------------------------
# Step 0c: Other required system tools.
# ---------------------------------------------------------------------------
$nsisCandidates = @(
  "${env:ProgramFiles(x86)}\NSIS\Bin\makensis.exe",
  "${env:ProgramFiles}\NSIS\Bin\makensis.exe"
) | Where-Object { Test-Path -LiteralPath $_ }
if (-not $nsisCandidates) {
  throw @"
NSIS (makensis.exe) not found.

Install NSIS: https://nsis.sourceforge.io/Download
Default install path is "C:\Program Files (x86)\NSIS\".
"@
}

$archivesDir = Join-Path $WeaselRepo 'output\archives'
$startedAt = Get-Date

Write-Host "Weasel source: $WeaselSource"
Write-Host "Weasel work  : $WeaselRepo"
Write-Host "Custom data : $CustomDataDir"
Write-Host "Boost root  : $BoostRoot"
Write-Host "Output dir  : $OutputDir"
Write-Host "VsDevCmd    : $VsDevCmd"
Write-Host "MSVC tools  : $(if ($MsvcToolsVersion) { $MsvcToolsVersion } else { 'VsDevCmd default' })"
Write-Host "SDK version : $SdkVer"
Write-Host "Toolset     : $PlatformToolset ($BjamToolset)"
Write-Host "Build arch  : $BuildArch"
Write-Host ''

Write-Host 'Probing MSVC/ATL environment...'
$expectedAtlBase = if ($MsvcToolsVersion) {
  Join-Path (Split-Path -Parent $VsDevCmd) "..\..\VC\Tools\MSVC\$MsvcToolsVersion\atlmfc\include\atlbase.h" |
    ForEach-Object { [System.IO.Path]::GetFullPath($_) }
} else {
  $null
}
if ($expectedAtlBase) {
  Require-Path $expectedAtlBase 'ATL header for selected MSVC toolset'
}
$probeCmd = "$VsDevCmdCall && where cl"
& cmd.exe /d /s /c $probeCmd
if ($LASTEXITCODE -ne 0) {
  throw 'VsDevCmd did not expose cl.exe.'
}
$probeVersionCmd = "$VsDevCmdCall && cl /Bv || exit /b 0"
& cmd.exe /d /s /c $probeVersionCmd
if ($expectedAtlBase) {
  Write-Host "atlbase.h   : $expectedAtlBase"
}
Write-Host ''

# ---------------------------------------------------------------------------
# Step 0d: Auto-prepare the generated work tree only.
#  - package-local .\plum / .\librime were already copied in Step 0a if
#    the mirrored .\weasel tree was incomplete
#  - if those inputs are still missing and the work tree is a git checkout,
#    try upstream submodule/prebuilt fallback inside .pack-work only
# ---------------------------------------------------------------------------
$weaselIsGitRepo = Test-GitWorkTree $WeaselRepo
$plumMarker = Join-Path $WeaselRepo 'plum\rime-install.bat'
if (-not (Test-Path -LiteralPath $plumMarker)) {
  if ($weaselIsGitRepo) {
    [void](Require-Command 'git' 'Install Git for Windows: https://git-scm.com/download/win  (needed for submodules).')
    Write-Host 'Initializing plum submodule (one-time, needs network)...'
    Push-Location $WeaselRepo
    try {
      & git submodule update --init plum
      if ($LASTEXITCODE -ne 0) {
        throw "git submodule update --init plum failed. Check your network/GitHub access."
      }
    } finally { Pop-Location }
    Require-Path $plumMarker 'plum\rime-install.bat (after submodule init)'
    Write-Host ''
  }
}
Require-Path $plumMarker 'plum\rime-install.bat (in isolated work tree)'

$boostHeaderReader = {
  param($LibraryPath)

  & cmd.exe /d /s /c "$VsDevCmdCall >nul && dumpbin /headers `"$LibraryPath`""
}

$missingBoost = Get-MissingBoostLibraries $BoostRoot
$invalidBoost = @(Get-InvalidBoostLibraries -BoostRoot $BoostRoot -ReadHeaders $boostHeaderReader)
if ($invalidBoost.Count -gt 0) {
  Write-Host 'Removing Boost static libraries with the wrong COFF machine type...'
  foreach ($library in $invalidBoost) {
    $libraryPath = Join-Path $BoostRoot "stage\lib\$library"
    Write-Host "  invalid: $library"
    Remove-Item -LiteralPath $libraryPath -Force
  }
  $boostBuildCache = Join-Path $BoostRoot 'bin.v2'
  if (Test-Path -LiteralPath $boostBuildCache) {
    if (-not (Test-PathUnderRoot $boostBuildCache $BoostRoot)) {
      throw "Refusing to remove Boost.Build cache outside Boost root: $boostBuildCache"
    }
    Write-Host "  removing stale Boost.Build cache: $boostBuildCache"
    Remove-Item -LiteralPath $boostBuildCache -Recurse -Force
  }
  $missingBoost = Get-MissingBoostLibraries $BoostRoot
}
if ($missingBoost.Count -gt 0) {
  Write-Host 'Preparing Boost static libraries...'
  Write-Host "  missing: $($missingBoost -join ', ')"
  Write-WeaselEnvBat $WeaselRepo

  $boostArchitectures = @(Get-BoostBuildArchitectures)
  $bootstrapArch = $boostArchitectures[0]
  $boostBootstrapVsDevCmdCall = New-VsDevCmdCall `
    -VsDevCmd $VsDevCmd `
    -MsvcToolsVersion $MsvcToolsVersion `
    -Architecture $bootstrapArch.VsArchitecture `
    -HostArchitecture $bootstrapArch.HostArchitecture

  $boostBootstrapCmd = "$boostBootstrapVsDevCmdCall && cd /d `"$BoostRoot`" && call bootstrap.bat vc143"
  & cmd.exe /d /s /c $boostBootstrapCmd
  if ($LASTEXITCODE -ne 0) {
    throw "Boost bootstrap failed with exit code $LASTEXITCODE"
  }

  foreach ($boostArch in $boostArchitectures) {
    $archMissing = @(Get-BoostLinkLibraries $boostArch.Architecture | Where-Object {
      -not (Test-Path -LiteralPath (Join-Path $BoostRoot "stage\lib\$_"))
    })
    if ($archMissing.Count -eq 0) {
      Write-Host "  Boost $($boostArch.Architecture): already prepared."
      continue
    }

    $boostVsDevCmdCall = New-VsDevCmdCall `
      -VsDevCmd $VsDevCmd `
      -MsvcToolsVersion $MsvcToolsVersion `
      -Architecture $boostArch.VsArchitecture `
      -HostArchitecture $boostArch.HostArchitecture

    $selectedCl = & cmd.exe /d /s /c "$boostVsDevCmdCall && where cl"
    $selectedClPath = Select-ClPath $selectedCl
    if ($LASTEXITCODE -ne 0 -or -not $selectedClPath) {
      throw "VsDevCmd did not expose cl.exe for Boost.Build $($boostArch.Architecture) configuration."
    }

    $boostProjectConfig = New-BoostProjectConfig $selectedClPath
    Set-Content -LiteralPath (Join-Path $BoostRoot 'project-config.jam') -Value $boostProjectConfig -Encoding ASCII
    Write-Host "  Boost.Build $($boostArch.Architecture): $boostProjectConfig"

    $bjamOptions = (Get-BoostBjamOptions -Architecture $boostArch.Architecture -BjamToolset $BjamToolset) -join ' '
    $cmd = "$boostVsDevCmdCall && set `"SDKVER=$SdkVer`" && set `"BOOST_ROOT=$BoostRoot`" && set `"PLATFORM_TOOLSET=$PlatformToolset`" && set `"BJAM_TOOLSET=$BjamToolset`" && cd /d `"$BoostRoot`" && b2.exe $bjamOptions stage"
    & cmd.exe /d /s /c $cmd
    if ($LASTEXITCODE -ne 0) {
      throw "Boost $($boostArch.Architecture) build failed with exit code $LASTEXITCODE"
    }
  }

  $missingBoost = Get-MissingBoostLibraries $BoostRoot
  if ($missingBoost.Count -gt 0) {
    throw @"
Boost static library preparation incomplete.
Expected Boost 1.84 x64 static libraries under:
  $(Join-Path $BoostRoot 'stage\lib')

Missing:
  $($missingBoost -join "`n  ")
"@
  }
  $invalidBoost = @(Get-InvalidBoostLibraries -BoostRoot $BoostRoot -ReadHeaders $boostHeaderReader)
  if ($invalidBoost.Count -gt 0) {
    throw @"
Boost static library preparation produced wrong-machine libraries.

Invalid:
  $($invalidBoost -join "`n  ")
"@
  }
  Write-Host ''
}

# librime submodule: needed for librime\data\minimal\default.yaml, which we use
# as the template to synthesize a working output\data\default.yaml.
# get-rime.ps1 only fetches prebuilt headers/libs, NOT the source tree.
$librimeMarker = Join-Path $WeaselRepo 'librime\data\minimal\default.yaml'
if (-not (Test-Path -LiteralPath $librimeMarker)) {
  if ($weaselIsGitRepo) {
    [void](Require-Command 'git' 'Install Git for Windows: https://git-scm.com/download/win  (needed for submodules).')
    Write-Host 'Initializing librime submodule (one-time, needs network)...'
    Push-Location $WeaselRepo
    try {
      & git submodule update --init librime
      if ($LASTEXITCODE -ne 0) {
        throw "git submodule update --init librime failed. Check your network/GitHub access."
      }
    } finally { Pop-Location }
    Require-Path $librimeMarker 'librime\data\minimal\default.yaml (after submodule init)'
    Write-Host ''
  }
}
Require-Path $librimeMarker 'librime\data\minimal\default.yaml (in isolated work tree)'

$missingLibrime = Get-MissingLibrimeFiles $WeaselRepo
if ($missingLibrime.Count -gt 0) {
  Install-PackLibrimeLuaPlugin -WeaselRoot $WeaselRepo -CustomDataDir $CustomDataDir -LibrimeLuaRef $env:PACK_LIBRIME_LUA_REF -LibrimeLuaThirdpartyRef $env:PACK_LIBRIME_LUA_THIRDPARTY_REF -Force
  $localLibrimeBuild = Join-Path $WeaselRepo 'librime\build.bat'
  if (Test-Path -LiteralPath $localLibrimeBuild) {
    try {
      Write-Host 'Preparing librime from bundled weasel\librime source tree...'
      Write-WeaselEnvBat $WeaselRepo
      $oldCmakePolicyVersionMinimum = $env:CMAKE_POLICY_VERSION_MINIMUM
      $env:CMAKE_POLICY_VERSION_MINIMUM = '3.5'
      try {
        $cmd = "$VsDevCmdCall && set `"SDKVER=$SdkVer`" && set `"BOOST_ROOT=$BoostRoot`" && set `"PLATFORM_TOOLSET=$PlatformToolset`" && set `"BJAM_TOOLSET=$BjamToolset`" && cd /d `"$WeaselRepo`" && call build.bat librime"
        & cmd.exe /d /s /c $cmd
        if ($LASTEXITCODE -ne 0) {
          throw "local librime build failed with exit code $LASTEXITCODE. Expected weasel\include\rime_api.h / lib64\rime.lib / output\rime.dll after preparation."
        }
      } finally {
        $env:CMAKE_POLICY_VERSION_MINIMUM = $oldCmakePolicyVersionMinimum
      }
    } catch {
      Write-Warning $_.Exception.Message
    }

    $missingLibrime = Get-MissingLibrimeFiles $WeaselRepo
    if ($missingLibrime.Count -gt 0) {
      Write-Warning 'Local librime build did not produce required headers/libs; falling back to get-rime.ps1.'
      Invoke-LibrimePrebuiltFallback $WeaselRepo
    }
  } else {
    Invoke-LibrimePrebuiltFallback $WeaselRepo
  }

  $missingLibrime = Get-MissingLibrimeFiles $WeaselRepo
  if ($missingLibrime.Count -gt 0) {
    throw @"
librime preparation incomplete.
Expected weasel\include\rime_api.h / lib64\rime.lib / output\rime.dll and related Win32/x64 files under:
  $WeaselRepo

Missing:
  $($missingLibrime -join "`n  ")
"@
  }
  Write-Host ''
}

Assert-PackLibrimeLuaSupport -WeaselRoot $WeaselRepo -CustomDataDir $CustomDataDir -Force


# Weasel's build.bat depends on bare-name calls like `call env.bat` / `call build.bat deps`,
# which require cmd.exe to search the current directory. The user env var
# NoDefaultCurrentDirectoryInExePath=1 disables that search and must be cleared
# *before* launching cmd.exe (cmd reads it at startup, not per-invocation).
$env:NoDefaultCurrentDirectoryInExePath = $null

# build.bat unconditionally calls env.bat. Keep it as a guarded stub so values
# passed via `set` survive every build step.
Write-WeaselEnvBat $WeaselRepo

# In a portable package, plum/librime may come from the package-local sibling
# folders and bash may not be available. Prepare the data files that build.bat
# checks for so it can build Weasel itself without trying to regenerate upstream
# data.
Ensure-OutputDataBuildGuards $WeaselRepo
Ensure-OutputInstallerSupportFiles $WeaselRepo

Write-Host 'Patching Weasel project Boost link dependencies...'
foreach ($relativeProject in @(
  'WeaselTSF\WeaselTSF.vcxproj',
  'WeaselServer\WeaselServer.vcxproj',
  'WeaselDeployer\WeaselDeployer.vcxproj'
)) {
  $projectPath = Join-Path $WeaselRepo $relativeProject
  Require-Path $projectPath $relativeProject
  if (Add-BoostLinkLibrariesToProject $projectPath) {
    Write-Host "  patched $relativeProject"
  } else {
    Write-Host "  already patched $relativeProject"
  }
}
Write-Host ''

Write-Host 'Patching Weasel IPC archive compatibility...'
if (Repair-WeaselIpcArchiveCompatibility $WeaselRepo) {
  Write-Host '  removed non-versioned fork-only IPC archive fields'
} else {
  Write-Host '  already compatible'
}
Write-Host ''

$cmd = "$VsDevCmdCall && set `"SDKVER=$SdkVer`" && set `"BOOST_ROOT=$BoostRoot`" && set `"WEASEL_CUSTOM_DATA_DIR=$CustomDataDir`" && set `"PLATFORM_TOOLSET=$PlatformToolset`" && set `"BJAM_TOOLSET=$BjamToolset`" && cd /d `"$WeaselRepo`" && call build.bat weasel $BuildArch"
& cmd.exe /d /s /c $cmd
if ($LASTEXITCODE -ne 0) {
  throw "build.bat (weasel) failed with exit code $LASTEXITCODE"
}

# ---------------------------------------------------------------------------
# Inject custom-data into output\data before NSIS packages it.
# - copy custom-data tree verbatim (preserves lua/, opencc/, nested dirs)
# - write weasel-custom-data.txt: list of file paths shipped by this package
# - write weasel-visible-schemas.txt: schema ids from default.custom.yaml's schema_list
# - delete unrelated top-level *.schema.yaml / *.dict.yaml / *.custom.yaml
#   that are not in custom-data (keep core support files)
# ---------------------------------------------------------------------------

$outputData = Join-Path $WeaselRepo 'output\data'
if (-not (Test-Path -LiteralPath $outputData)) {
  New-Item -ItemType Directory -Path $outputData | Out-Null
}

Write-Host ''
Write-Host "Injecting custom-data into $outputData ..."

# Build a relative-path inventory of custom-data files (forward slashes for portability).
$customRoot = (Resolve-Path -LiteralPath $CustomDataDir).Path
$customFiles = Get-ChildItem -LiteralPath $customRoot -Recurse -File
$customRelList = New-Object System.Collections.Generic.List[string]
$customBasenameSet = New-Object System.Collections.Generic.HashSet[string]([StringComparer]::OrdinalIgnoreCase)
foreach ($f in $customFiles) {
  $relSlash = Copy-PackCustomDataFile -File $f -CustomRoot $customRoot -OutputData $outputData
  if (-not $relSlash) {
    continue
  }
  $customRelList.Add($relSlash)
  [void]$customBasenameSet.Add([System.IO.Path]::GetFileName($relSlash))
}
Write-Host ("  copied {0} file(s)" -f $customRelList.Count)

# weasel-custom-data.txt - one path per line, LF endings, no trailing blank.
$customListPath = Join-Path $outputData 'weasel-custom-data.txt'
[System.IO.File]::WriteAllText($customListPath, (($customRelList | Sort-Object) -join "`n"), [System.Text.UTF8Encoding]::new($false))
Write-Host "  wrote $customListPath"

# weasel-visible-schemas.txt - schema ids from default.custom.yaml's schema_list.
$visibleSchemas = New-Object System.Collections.Generic.List[string]
$defaultCustom = Join-Path $customRoot 'default.custom.yaml'
if (Test-Path -LiteralPath $defaultCustom) {
  $inSchemaList = $false
  foreach ($line in Get-Content -LiteralPath $defaultCustom -Encoding UTF8) {
    $stripped = $line -replace '#.*$',''  # drop inline comments
    if ($stripped -match '^\s*schema_list\s*:\s*$') { $inSchemaList = $true; continue }
    if ($inSchemaList) {
      if ($stripped -match '^\s*-\s*\{\s*schema\s*:\s*([A-Za-z0-9_./-]+)\s*\}') {
        $visibleSchemas.Add($Matches[1])
      } elseif ($stripped -match '^\s*-\s*schema\s*:\s*([A-Za-z0-9_./-]+)') {
        $visibleSchemas.Add($Matches[1])
      } elseif ($stripped -match '^\S' -and $stripped -notmatch '^\s*-') {
        # next top-level key reached
        $inSchemaList = $false
      }
    }
  }
}
$visiblePath = Join-Path $outputData 'weasel-visible-schemas.txt'
[System.IO.File]::WriteAllText($visiblePath, (($visibleSchemas) -join "`n"), [System.Text.UTF8Encoding]::new($false))
Write-Host ("  wrote $visiblePath ({0} schemas: {1})" -f $visibleSchemas.Count, ($visibleSchemas -join ', '))

# Synthesize a working default.yaml from librime's bundled minimal template.
#
# Why we need this: schemas reference sections like `default:recognizer`,
# `default:key_binder`, `default:punctuator` via __include. If default.yaml is
# missing those sections, librime's deployer fails with "failed to include
# section default:xxx -> error building config: tiger.schema" and aborts the
# whole deploy. No %AppData%\Rime\build is generated, so user-side patches
# (schema_list, color_scheme) never apply.
#
# A minimal hand-rolled default.yaml with just `schema_list:` is NOT enough.
# We take librime\data\minimal\default.yaml (canonical reference shipped in the
# librime tree) and replace its `schema_list:` block with ours.
$defaultYaml = Join-Path $outputData 'default.yaml'
$minimalDefault = Join-Path $WeaselRepo 'librime\data\minimal\default.yaml'
if (-not (Test-Path -LiteralPath $minimalDefault)) {
  throw @"
librime\data\minimal\default.yaml not found at $minimalDefault
This file is needed as the default.yaml template. Put a complete weasel source
tree under this package folder. If this is a git checkout, the script initializes
missing submodules inside the isolated .pack-work copy, not in the source folder.
"@
}
if ($visibleSchemas.Count -gt 0) {
  $tmplLines = [System.IO.File]::ReadAllLines($minimalDefault)
  $out = New-Object System.Collections.Generic.List[string]
  $inSchemaList = $false
  $replaced = $false
  foreach ($line in $tmplLines) {
    if (-not $replaced -and $line -match '^\s*schema_list\s*:\s*$') {
      $out.Add('schema_list:')
      foreach ($s in $visibleSchemas) {
        $out.Add("  - schema: $s")
      }
      $inSchemaList = $true
      $replaced = $true
      continue
    }
    if ($inSchemaList) {
      # Skip the original `  - schema: xxx` lines until we exit the block.
      if ($line -match '^\s*-\s') { continue }
      if ($line -match '^\s*$' -or $line -match '^\S') { $inSchemaList = $false }
      # fall through to add the non-schema_list line
    }
    $out.Add($line)
  }
  if (-not $replaced) {
    throw "Failed to locate schema_list: anchor in librime's minimal default.yaml"
  }
  [System.IO.File]::WriteAllLines($defaultYaml, $out, [System.Text.UTF8Encoding]::new($false))
  Write-Host ("  wrote $defaultYaml (from librime minimal template; schema_list: {0})" -f ($visibleSchemas -join ', '))
}

# Ensure librime's preset vocabulary resource is available when packaged
# dictionaries request it. Upstream build.bat normally gets this through plum,
# but local Windows builds may not have bash in PATH, so use librime's bundled
# minimal essay.txt as a deterministic fallback.
$usesPresetVocabulary = $false
foreach ($dict in Get-ChildItem -LiteralPath $outputData -Filter '*.dict.yaml' -File -ErrorAction SilentlyContinue) {
  $dictContent = Get-Content -LiteralPath $dict.FullName -Raw -Encoding UTF8
  if ($dictContent -match '(?m)^\s*use_preset_vocabulary\s*:\s*true\b') {
    $usesPresetVocabulary = $true
    break
  }
}
if ($usesPresetVocabulary) {
  $outputEssay = Join-Path $outputData 'essay.txt'
  if (-not (Test-Path -LiteralPath $outputEssay)) {
    $minimalEssay = Join-Path $WeaselRepo 'librime\data\minimal\essay.txt'
    if (-not (Test-Path -LiteralPath $minimalEssay)) {
      throw @"
librime\data\minimal\essay.txt not found at $minimalEssay
At least one packaged dictionary uses use_preset_vocabulary: true, so librime
must be able to load the preset vocabulary resource essay.txt.
"@
    }
    Copy-Item -LiteralPath $minimalEssay -Destination $outputEssay -Force
    Write-Host "  copied $outputEssay (required by use_preset_vocabulary: true)"
  }
}

# Drop top-level *.schema.yaml / *.dict.yaml / *.custom.yaml that are not part of
# this package. Keep core support files (default.yaml, weasel.yaml, essay.txt,
# etc.) untouched - they don't match these suffixes.
$dropPatterns = @('*.schema.yaml', '*.dict.yaml', '*.custom.yaml')
$dropped = 0
foreach ($pat in $dropPatterns) {
  Get-ChildItem -LiteralPath $outputData -Filter $pat -File -ErrorAction SilentlyContinue | ForEach-Object {
    if (-not $customBasenameSet.Contains($_.Name)) {
      Remove-Item -LiteralPath $_.FullName -Force
      $dropped++
    }
  }
}
Write-Host ("  dropped {0} unrelated schema/dict/custom yaml(s) from output\data" -f $dropped)

Merge-WeaselCustomThemePatch `
  (Join-Path $outputData 'weasel.yaml') `
  (Join-Path $customRoot 'weasel.custom.yaml')
Write-Host "  merged custom color schemes into output\data\weasel.yaml for the install-time theme dialog"

# Patch install.nsi:
#  1. Add top-level Lua entrypoints, nested custom-data dirs, and extra opencc extensions.
#  2. Default the MUI finish-page reboot prompt to "later" instead of "now".
#  3. After WeaselSetup writes RimeUserDir, copy every custom-data file into the
#     selected Rime user directory before WeaselDeployer opens its dialogs.
#
# Strategy: every run, first restore install.nsi from git, then unconditionally
# re-apply all patches. This avoids the "marker exists -> skip" trap, which silently
# drops new patches when only one block was applied in a previous run.
$installNsi = Join-Path $WeaselRepo 'output\install.nsi'
$nsiLines = [System.IO.File]::ReadAllLines($installNsi)
$nsiLines = Remove-PackNsiPatches $nsiLines
$nsiLines = Add-PackNsiOverwriteConfirmationPatch $nsiLines
$nsiLines = Add-PackNsiPostInstallTextServicesRefreshPatch $nsiLines
$nsiLines = Add-PackNsiUnregisterTextServicesRefreshPatch $nsiLines

$subdirs = Get-ChildItem -LiteralPath $outputData -Directory |
  Where-Object { $_.Name -notin @('opencc','preview') } |
  ForEach-Object { $_.Name }
$rootLuaFiles = Get-ChildItem -LiteralPath $outputData -Filter '*.lua' -File -ErrorAction SilentlyContinue

# Extra opencc file extensions (besides .json / .ocd*) that custom-data may ship.
$openccExtras = Get-ChildItem -LiteralPath (Join-Path $outputData 'opencc') -File -ErrorAction SilentlyContinue |
  Where-Object { $_.Extension -and $_.Extension -notin @('.json','.ocd','.ocd2','.ocd3') } |
  ForEach-Object { $_.Extension.TrimStart('.').ToLower() } |
  Sort-Object -Unique

$subdirInsertion = New-Object System.Collections.Generic.List[string]
if ($subdirs -or $rootLuaFiles) {
  $subdirInsertion.Add('; ---PACK_PS1_CUSTOM_DATA_DIRS---')
  if ($rootLuaFiles) {
    $subdirInsertion.Add('  File /nonfatal "data\*.lua"')
  }
  foreach ($d in $subdirs) {
    $subdirInsertion.Add("  File /r `"data\$d`"")
  }
  $subdirInsertion.Add('; ---END_PACK_PS1_CUSTOM_DATA_DIRS---')
}

$openccInsertion = New-Object System.Collections.Generic.List[string]
if ($openccExtras) {
  $openccInsertion.Add('; ---PACK_PS1_OPENCC_EXTRAS---')
  foreach ($ext in $openccExtras) {
    $openccInsertion.Add("  File /nonfatal `"data\opencc\*.$ext`"")
  }
  $openccInsertion.Add('; ---END_PACK_PS1_OPENCC_EXTRAS---')
}

# Block C: deploy all custom-data files to the Rime user directory selected by
# WeaselSetup. This must run after WeaselSetup writes
# HKCU\Software\Rime\Weasel\RimeUserDir and after the post-registration text
# services refresh, but before WeaselDeployer /install opens the schema/theme
# dialogs.
$userCustoms = @($customRelList | Sort-Object)
$deployInsertion = New-Object System.Collections.Generic.List[string]
if ($userCustoms) {
  $deployInsertion.Add('; ---PACK_PS1_DEPLOY_USER_CUSTOMS---')
  $deployInsertion.Add('  ; Deploy custom-data into the selected Rime user profile')
  $deployInsertion.Add('  ; so install-time dialogs and first deploy see the same files.')
  $deployInsertion.Add('  ReadRegStr $9 HKCU "Software\Rime\Weasel" "RimeUserDir"')
  $deployInsertion.Add('  StrCmp $9 "" 0 pack_ps1_have_user_dir')
  $deployInsertion.Add('  ExpandEnvStrings $9 "%APPDATA%\Rime"')
  $deployInsertion.Add('  pack_ps1_have_user_dir:')
  $deployInsertion.Add('  StrCmp $9 "" pack_ps1_skip_user_deploy 0')
  $deployInsertion.Add('  CreateDirectory "$9"')
  $deployInsertion.Add('  SetOverwrite on')
  $lastDeployDir = $null
  foreach ($relSlash in $userCustoms) {
    $rel = $relSlash -replace '/', '\'
    $dir = Split-Path -Parent $rel
    if ($dir -ne $lastDeployDir) {
      if ([string]::IsNullOrWhiteSpace($dir)) {
        $deployInsertion.Add('  SetOutPath "$9"')
      } else {
        $deployInsertion.Add("  SetOutPath `"`$9\$dir`"")
      }
      $lastDeployDir = $dir
    }
    # File source is relative to install.nsi (= output\).
    $deployInsertion.Add("  File `"data\$rel`"")
  }
  $deployInsertion.Add('  SetOutPath $INSTDIR')
  $deployInsertion.Add('  SetOverwrite try')
  $deployInsertion.Add('  pack_ps1_skip_user_deploy:')
  $deployInsertion.Add('; ---END_PACK_PS1_DEPLOY_USER_CUSTOMS---')
}

# Block R: default the finish-page reboot prompt to "later".
# Must be defined before !insertmacro MUI_PAGE_FINISH.
$rebootInsertion = @(
  '; ---PACK_PS1_REBOOT_LATER_DEFAULT---',
  '!define MUI_FINISHPAGE_REBOOTLATER_DEFAULT',
  '; ---END_PACK_PS1_REBOOT_LATER_DEFAULT---'
)

# Block S: skip the upstream "backup old INSTDIR\data and restore over new install"
# logic. Upstream weasel assumes upgrades layer on top of stock weasel data, so it
# preserves every old *.schema.yaml. For a custom installer that wants to REPLACE
# the schema set, that restore leaves the previous install's schemas hanging around
# under INSTDIR\data, and SwitcherSettings will list them all.
# We do this by injecting `Goto pack_ps1_skip_data_restore` right before the
# upstream `IfFileExists $TEMP\weasel-backup\*.*` check, and adding the label after
# the matching `RMDir /r` so jump targets resolve.
$skipRestoreInsertion = @(
  '; ---PACK_PS1_SKIP_DATA_RESTORE---',
  '  Goto pack_ps1_skip_data_restore',
  '; ---END_PACK_PS1_SKIP_DATA_RESTORE---'
)
$skipRestoreLabelInsertion = @(
  '; ---PACK_PS1_SKIP_DATA_RESTORE_LABEL---',
  '  pack_ps1_skip_data_restore:',
  '; ---END_PACK_PS1_SKIP_DATA_RESTORE_LABEL---'
)

# Block Q: make uninstall and upgrade release user-profile files reliably.
# WeaselServer.exe can keep librime userdb/build files open after the normal
# shutdown command returns. Preserve the upstream command (/quit or /stop), then
# clear stale manual-exit state left by newer Weasel variants and remove any
# residual process by image name.
$stopServerMacroInsertion = @(
  '; ---PACK_PS1_STOP_WEASEL_SERVER_MACRO---',
  '!macro PACK_PS1_STOP_WEASEL_SERVER SERVER_EXE SERVER_COMMAND',
  '  IfFileExists "${SERVER_EXE}" 0 +2',
  '  Exec ''"${SERVER_EXE}" ${SERVER_COMMAND}''',
  '  Sleep 1500',
  '  Delete "$TEMP\rime.weasel\weasel-service-manual-exit.flag"',
  '  nsExec::ExecToStack ''taskkill /IM WeaselServer.exe /F /T''',
  '  Pop $0',
  '  Pop $1',
  '  Delete "$TEMP\rime.weasel\weasel-service-manual-exit.flag"',
  '  Sleep 500',
  '!macroend',
  '; ---END_PACK_PS1_STOP_WEASEL_SERVER_MACRO---'
)

# Block T: after TSF unregister, refresh the current Windows input-method
# session cache. This cannot guarantee avoiding logout in every Windows build,
# but it handles the common stale ctfmon/TextInputHost state immediately.
$textServicesRefreshMacroInsertion = @(
  '; ---PACK_PS1_REFRESH_TEXT_SERVICES_MACRO---',
  '!macro PACK_PS1_REFRESH_TEXT_SERVICES',
  '  nsExec::ExecToStack ''taskkill /IM TextInputHost.exe /F''',
  '  Pop $0',
  '  Pop $1',
  '  nsExec::ExecToStack ''taskkill /IM ctfmon.exe /F''',
  '  Pop $0',
  '  Pop $1',
  '  Sleep 500',
  '  Exec ''ctfmon.exe''',
  '  Sleep 500',
  '!macroend',
  '; ---END_PACK_PS1_REFRESH_TEXT_SERVICES_MACRO---'
)

$patched = New-Object System.Collections.Generic.List[string]
$inserted1 = $false  # top-level lua and custom-data subdirs
$inserted2 = $false  # opencc extras
$inserted3 = $false  # user-dir deploy
$inserted4 = $false  # reboot later
$inserted5 = $false  # skip-restore goto
$inserted6 = $false  # skip-restore label
$inserted7 = $false  # stop-server macro
$inserted8 = $false  # text-services refresh macro
$stopServerReplacementCount = 0
$sawPostInstallWeaselSetup = $false
foreach ($line in $nsiLines) {
  if (-not $inserted7 -and $line -match '^Function\s+\.onInit\b') {
    foreach ($ins in $stopServerMacroInsertion) { $patched.Add($ins) }
    foreach ($ins in $textServicesRefreshMacroInsertion) { $patched.Add($ins) }
    $inserted7 = $true
    $inserted8 = $true
  }
  if (-not $inserted4 -and $line -match '!insertmacro\s+MUI_PAGE_FINISH') {
    foreach ($ins in $rebootInsertion) { $patched.Add($ins) }
    $inserted4 = $true
  }
  # Skip-restore: inject the Goto immediately BEFORE the IfFileExists line.
  if (-not $inserted5 -and $line -match 'IfFileExists\s+\$TEMP\\weasel-backup\\\*\.\*') {
    foreach ($ins in $skipRestoreInsertion) { $patched.Add($ins) }
    $inserted5 = $true
  }
  $stopServerReplacement = Get-PackNsiStopServerReplacement $line
  if ($stopServerReplacement) {
    $patched.Add($stopServerReplacement)
    $stopServerReplacementCount++
    continue
  }
  $patched.Add($line)

  if ($line.Trim() -like 'ExecWait ''"$INSTDIR\WeaselSetup.exe" $R2''*') {
    $sawPostInstallWeaselSetup = $true
  }

  # Skip-restore label: inject right AFTER the `RMDir /r $TEMP\weasel-backup` line.
  if ($inserted5 -and -not $inserted6 -and $line -match 'RMDir\s+/r\s+\$TEMP\\weasel-backup') {
    foreach ($ins in $skipRestoreLabelInsertion) { $patched.Add($ins) }
    $inserted6 = $true
  }
  if (-not $inserted1 -and $subdirInsertion.Count -gt 0 -and $line -match 'File\s+/nonfatal\s+"data\\\*\.gram"') {
    foreach ($ins in $subdirInsertion) { $patched.Add($ins) }
    $inserted1 = $true
  }
  if (-not $inserted2 -and $openccExtras -and $line -match 'File\s+"data\\opencc\\\*\.ocd\*"') {
    foreach ($ins in $openccInsertion) { $patched.Add($ins) }
    $inserted2 = $true
  }
  if (-not $inserted3 -and $userCustoms -and $sawPostInstallWeaselSetup -and $line.Trim() -eq '!insertmacro PACK_PS1_REFRESH_TEXT_SERVICES') {
    foreach ($ins in $deployInsertion) { $patched.Add($ins) }
    $inserted3 = $true
  }
}
if ($subdirInsertion.Count -gt 0 -and -not $inserted1) { throw "install.nsi patch anchor (File /nonfatal data\*.gram) not found" }
if ($openccExtras -and -not $inserted2) { throw "install.nsi opencc patch anchor (data\opencc\*.ocd*) not found" }
if ($userCustoms -and -not $inserted3)  { throw "install.nsi user-deploy patch anchor (WeaselSetup.exe) not found" }
if (-not $inserted4)                    { throw "install.nsi reboot patch anchor (MUI_PAGE_FINISH) not found" }
if (-not $inserted5)                    { throw "install.nsi skip-restore patch anchor (IfFileExists \$TEMP\weasel-backup) not found" }
if (-not $inserted6)                    { throw "install.nsi skip-restore label anchor (RMDir /r \$TEMP\weasel-backup) not found" }
if (-not $inserted7)                    { throw "install.nsi stop-server macro anchor (Function .onInit) not found" }
if (-not $inserted8)                    { throw "install.nsi text-services refresh macro anchor (Function .onInit) not found" }
if ($stopServerReplacementCount -lt 3)  { throw "install.nsi stop-server replacement anchors not found" }
[System.IO.File]::WriteAllLines($installNsi, $patched, [System.Text.UTF8Encoding]::new($true))
$msg = @()
if ($rootLuaFiles) { $msg += 'root lua: *.lua' }
if ($subdirs)      { $msg += ("subdirs: {0}" -f ($subdirs -join ', ')) }
if ($openccExtras) { $msg += ("opencc extras: *.{0}" -f ($openccExtras -join ', *.')) }
if ($userCustoms)  { $msg += ("user deploy: {0}" -f ($userCustoms -join ', ')) }
$msg += 'reboot default: later'
$msg += 'skip old data restore'
$msg += 'confirm overwrite before uninstall prompt'
$msg += 'stop residual WeaselServer and clear manual-exit flag on uninstall'
$msg += 'refresh text services after unregister/register'
Write-Host ("  patched install.nsi - " + ($msg -join '; '))
Write-Host ''

# Now run the installer step.
$cmd = "$VsDevCmdCall && set `"SDKVER=$SdkVer`" && set `"BOOST_ROOT=$BoostRoot`" && set `"PLATFORM_TOOLSET=$PlatformToolset`" && set `"BJAM_TOOLSET=$BjamToolset`" && cd /d `"$WeaselRepo`" && call build.bat installer $BuildArch"
& cmd.exe /d /s /c $cmd
if ($LASTEXITCODE -ne 0) {
  throw "build.bat (installer) failed with exit code $LASTEXITCODE"
}

Require-Path $archivesDir 'archives dir'
$freshInstallerCandidates = @(Get-ChildItem -LiteralPath $archivesDir -Filter '*installer.exe' -File |
  Where-Object { $_.LastWriteTime -ge $startedAt.AddSeconds(-5) } |
  Sort-Object LastWriteTime -Descending)

$zeroByteInstallers = @($freshInstallerCandidates | Where-Object { $_.Length -le 0 })
if ($zeroByteInstallers.Count -gt 0) {
  throw @"
Installer build produced zero-byte artifact(s):
  $(@($zeroByteInstallers | ForEach-Object { $_.FullName }) -join "`n  ")

This usually means makensis/build.bat reported success before the output file
was actually usable. Re-run pack.ps1 after any other build process has exited.
"@
}

$installers = @($freshInstallerCandidates | Where-Object { $_.Length -gt 0 })
if (-not $installers) {
  throw "No fresh non-empty installer found in $archivesDir"
}

foreach ($installer in @($installers)) {
  $dest = Join-Path $OutputDir $installer.Name
  # The freshly built .exe is often briefly locked by Windows Defender or the
  # user's previous double-click. Retry with backoff.
  $copied = $false
  for ($attempt = 1; $attempt -le 8; $attempt++) {
    try {
      Copy-Item -LiteralPath $installer.FullName -Destination $dest -Force -ErrorAction Stop
      $copied = $true
      break
    } catch {
      if ($attempt -eq 8) { throw }
      Write-Host ("  copy attempt {0} failed ({1}); retrying..." -f $attempt, $_.Exception.Message)
      Start-Sleep -Milliseconds (500 * $attempt)
    }
  }
  if ($copied) { Write-Host "Copied installer: $dest" }
}

Write-Host ''
Write-Host 'Done. Installer file(s) in:'
Write-Host $OutputDir
