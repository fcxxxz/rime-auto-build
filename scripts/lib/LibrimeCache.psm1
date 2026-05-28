function Get-LibrimeCacheRelativePaths {
  return @(
    'include\rime_api.h',
    'include\rime_api_deprecated.h',
    'include\rime_api_stdbool.h',
    'include\rime_levers_api.h',
    'lib64\rime.lib',
    'lib\rime.lib',
    'output\rime.dll',
    'output\rime.pdb',
    'output\Win32\rime.dll',
    'output\Win32\rime.pdb',
    'output\data\opencc\HKVariants.ocd2',
    'output\data\opencc\HKVariantsPhrases.ocd2',
    'output\data\opencc\HKVariantsRev.ocd2',
    'output\data\opencc\JPShinjitaiCharacters.ocd2',
    'output\data\opencc\JPShinjitaiPhrases.ocd2',
    'output\data\opencc\JPVariants.ocd2',
    'output\data\opencc\JPVariantsRev.ocd2',
    'output\data\opencc\STCharacters.ocd2',
    'output\data\opencc\STPhrases.ocd2',
    'output\data\opencc\TSCharacters.ocd2',
    'output\data\opencc\TSPhrases.ocd2',
    'output\data\opencc\TWVariants.ocd2',
    'output\data\opencc\TWVariantsPhrases.ocd2',
    'output\data\opencc\TWVariantsRev.ocd2',
    'output\data\opencc\t2hk.json',
    'output\data\opencc\t2jp.json',
    'output\data\opencc\t2s.json',
    'output\data\opencc\t2tw.json',
    'output\data\opencc\tw2s.json'
  )
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
    if (-not (Test-Path -LiteralPath $source)) {
      continue
    }

    $destination = Join-Path $DestinationWeaselRoot $relativePath
    $destinationDir = Split-Path -Parent $destination
    if (-not (Test-Path -LiteralPath $destinationDir)) {
      New-Item -ItemType Directory -Path $destinationDir -Force | Out-Null
    }

    Copy-Item -LiteralPath $source -Destination $destination -Force
    $copied.Add($relativePath)
  }

  return [string[]]$copied
}

Export-ModuleMember -Function Get-LibrimeCacheRelativePaths,Copy-LibrimeCacheOutputs
