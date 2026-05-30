function Get-LibrimeCacheRelativePaths {
  return @(
    'include\rime_api.h',
    'include\rime_api_deprecated.h',
    'include\rime_api_stdbool.h',
    'include\rime_levers_api.h',
    'lib64\rime.lib',
    'lib\rime.lib',
    'librime\bin\opencc.exe',
    'librime\bin\opencc_dict.exe',
    'librime\bin\opencc_phrase_extract.exe',
    'output\rime.dll',
    'output\rime.pdb',
    'output\Win32\rime.dll',
    'output\Win32\rime.pdb'
  )
}

function Copy-LibrimeCacheFile(
  [string]$SourcePath,
  [string]$DestinationPath,
  [string]$RelativePath,
  [System.Collections.Generic.List[string]]$Copied
) {
  if (-not (Test-Path -LiteralPath $SourcePath -PathType Leaf)) {
    return
  }

  $destinationDir = Split-Path -Parent $DestinationPath
  if (-not (Test-Path -LiteralPath $destinationDir)) {
    New-Item -ItemType Directory -Path $destinationDir -Force | Out-Null
  }

  Copy-Item -LiteralPath $SourcePath -Destination $DestinationPath -Force
  $Copied.Add($RelativePath)
}

function Copy-LibrimeCacheOutputs(
  [string]$SourceWeaselRoot,
  [string]$DestinationWeaselRoot
) {
  if (-not (Test-Path -LiteralPath $SourceWeaselRoot)) {
    throw "Source weasel root not found: $SourceWeaselRoot"
  }

  if (-not (Test-Path -LiteralPath $DestinationWeaselRoot)) {
    New-Item -ItemType Directory -Path $DestinationWeaselRoot -Force | Out-Null
  }

  $copied = New-Object System.Collections.Generic.List[string]
  foreach ($relativePath in Get-LibrimeCacheRelativePaths) {
    $source = Join-Path $SourceWeaselRoot $relativePath
    $destination = Join-Path $DestinationWeaselRoot $relativePath
    Copy-LibrimeCacheFile -SourcePath $source -DestinationPath $destination -RelativePath $relativePath -Copied $copied
  }

  $openCcRuntimeRoot = Join-Path $SourceWeaselRoot 'librime\share\opencc'
  if (Test-Path -LiteralPath $openCcRuntimeRoot -PathType Container) {
    Get-ChildItem -LiteralPath $openCcRuntimeRoot -Recurse -File |
      Sort-Object FullName |
      ForEach-Object {
        $openCcRelative = [System.IO.Path]::GetRelativePath($openCcRuntimeRoot, $_.FullName).Replace('/', '\')
        $relativePath = Join-Path 'output\data\opencc' $openCcRelative
        $destination = Join-Path $DestinationWeaselRoot $relativePath

        Copy-LibrimeCacheFile -SourcePath $_.FullName -DestinationPath $destination -RelativePath $relativePath -Copied $copied
      }
  }

  return [string[]]$copied
}

function Restore-LibrimeCacheOutputs(
  [string]$SourceWeaselRoot,
  [string]$DestinationWeaselRoot
) {
  if (-not (Test-Path -LiteralPath $SourceWeaselRoot)) {
    throw "Source cache weasel root not found: $SourceWeaselRoot"
  }

  if (-not (Test-Path -LiteralPath $DestinationWeaselRoot)) {
    New-Item -ItemType Directory -Path $DestinationWeaselRoot -Force | Out-Null
  }

  $restored = New-Object System.Collections.Generic.List[string]
  Get-ChildItem -LiteralPath $SourceWeaselRoot -Recurse -File |
    Sort-Object FullName |
    ForEach-Object {
      $relativePath = [System.IO.Path]::GetRelativePath($SourceWeaselRoot, $_.FullName).Replace('/', '\')
      $destination = Join-Path $DestinationWeaselRoot $relativePath
      Copy-LibrimeCacheFile -SourcePath $_.FullName -DestinationPath $destination -RelativePath $relativePath -Copied $restored
    }

  return [string[]]$restored
}

Export-ModuleMember -Function Get-LibrimeCacheRelativePaths,Copy-LibrimeCacheOutputs,Restore-LibrimeCacheOutputs
