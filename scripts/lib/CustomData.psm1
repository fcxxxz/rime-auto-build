function Test-PackPathUnderRoot([string]$Path, [string]$Root) {
  $trimChars = [char[]]@([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
  $full = [System.IO.Path]::GetFullPath($Path).TrimEnd($trimChars)
  $rootFull = [System.IO.Path]::GetFullPath($Root).TrimEnd($trimChars)
  return $full.Equals($rootFull, [StringComparison]::OrdinalIgnoreCase) -or
    $full.StartsWith($rootFull + [System.IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)
}

function Get-PackCustomDataRelativePath([string]$FullName, [string]$CustomRoot) {
  $root = [System.IO.Path]::GetFullPath($CustomRoot)
  $path = [System.IO.Path]::GetFullPath($FullName)
  return ($path.Substring($root.Length).TrimStart('\','/') -replace '\\','/')
}

function Get-PackFileTarget([object]$File) {
  $targetProperty = $File.PSObject.Properties['Target']
  if ($targetProperty -and $targetProperty.Value) {
    $target = $targetProperty.Value
    if ($target -is [array]) {
      return [string]$target[0]
    }
    return [string]$target
  }
  return $null
}

function Resolve-PackCustomDataCopySource([object]$File, [string]$CustomRoot) {
  $isReparsePoint = (($File.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)
  if (-not $isReparsePoint) {
    return $File.FullName
  }

  $relPath = Get-PackCustomDataRelativePath $File.FullName $CustomRoot
  $target = Get-PackFileTarget $File
  if ([string]::IsNullOrWhiteSpace($target)) {
    Write-Warning "Skipping custom-data symlink with no target: $relPath"
    return $null
  }

  if ([System.IO.Path]::IsPathRooted($target)) {
    $targetPath = [System.IO.Path]::GetFullPath($target)
  } else {
    $targetPath = [System.IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $File.FullName) $target))
  }

  if (-not (Test-PackPathUnderRoot $targetPath $CustomRoot)) {
    Write-Warning "Skipping custom-data symlink outside custom-data: $relPath -> $target"
    return $null
  }
  if (-not (Test-Path -LiteralPath $targetPath -PathType Leaf)) {
    Write-Warning "Skipping unresolved custom-data symlink: $relPath -> $target"
    return $null
  }

  return $targetPath
}

function Copy-PackCustomDataFile([object]$File, [string]$CustomRoot, [string]$OutputData) {
  $relSlash = Get-PackCustomDataRelativePath $File.FullName $CustomRoot
  $source = Resolve-PackCustomDataCopySource $File $CustomRoot
  if (-not $source) {
    return $null
  }

  $rel = $relSlash -replace '/', '\'
  $dst = Join-Path $OutputData $rel
  $dstDir = Split-Path -Parent $dst
  if (-not (Test-Path -LiteralPath $dstDir)) {
    New-Item -ItemType Directory -Path $dstDir -Force | Out-Null
  }
  Copy-Item -LiteralPath $source -Destination $dst -Force
  return $relSlash
}

function Add-PackOpenCcOcd2References([object]$Node, [System.Collections.Generic.HashSet[string]]$References) {
  if ($null -eq $Node) {
    return
  }

  if ($Node -is [string] -or $Node.GetType().IsPrimitive) {
    return
  }

  if ($Node -is [System.Collections.IDictionary]) {
    foreach ($value in $Node.Values) {
      Add-PackOpenCcOcd2References $value $References
    }
    return
  }

  if ($Node -is [System.Collections.IEnumerable] -and $Node -isnot [pscustomobject]) {
    foreach ($item in $Node) {
      Add-PackOpenCcOcd2References $item $References
    }
    return
  }

  $properties = @($Node.PSObject.Properties)
  if ($properties.Count -eq 0) {
    return
  }

  $typeProperty = $Node.PSObject.Properties['type']
  $fileProperty = $Node.PSObject.Properties['file']
  if ($typeProperty -and $fileProperty -and
      [string]::Equals([string]$typeProperty.Value, 'ocd2', [StringComparison]::OrdinalIgnoreCase)) {
    $file = [string]$fileProperty.Value
    if ([System.IO.Path]::GetExtension($file) -ieq '.ocd2') {
      [void]$References.Add($file)
    }
  }

  foreach ($property in $properties) {
    Add-PackOpenCcOcd2References $property.Value $References
  }
}

function Get-PackOpenCcOcd2References([string]$ConfigPath) {
  try {
    $config = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
  } catch {
    throw "Failed to parse OpenCC config '$ConfigPath': $($_.Exception.Message)"
  }

  $references = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
  Add-PackOpenCcOcd2References $config $references
  return @($references | Sort-Object)
}

function Convert-PackCustomOpenCcTextDictionaries([string]$OutputData, [string]$OpenCcDictPath) {
  $openccRoot = Join-Path $OutputData 'opencc'
  if (-not (Test-Path -LiteralPath $openccRoot -PathType Container)) {
    return @()
  }

  $references = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
  Get-ChildItem -LiteralPath $openccRoot -Filter '*.json' -File -ErrorAction SilentlyContinue | ForEach-Object {
    foreach ($reference in Get-PackOpenCcOcd2References $_.FullName) {
      [void]$references.Add($reference)
    }
  }

  $generated = New-Object System.Collections.Generic.List[string]
  foreach ($reference in ($references | Sort-Object)) {
    if ([System.IO.Path]::IsPathRooted($reference)) {
      throw "OpenCC dictionary reference must be relative: $reference"
    }

    $relativeParts = @($reference -split '[\\/]')
    $relativeNative = [System.IO.Path]::Combine([string[]]$relativeParts)
    $target = [System.IO.Path]::GetFullPath((Join-Path $openccRoot $relativeNative))
    if (-not (Test-PackPathUnderRoot $target $openccRoot)) {
      throw "OpenCC dictionary reference escapes opencc directory: $reference"
    }
    if (Test-Path -LiteralPath $target -PathType Leaf) {
      continue
    }

    $source = [System.IO.Path]::ChangeExtension($target, '.txt')
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
      Write-Warning "Skipping OpenCC dictionary build: $reference has no matching text source '$([System.IO.Path]::GetFileName($source))'."
      continue
    }
    if (-not (Test-Path -LiteralPath $OpenCcDictPath -PathType Leaf)) {
      throw "opencc_dict not found: $OpenCcDictPath"
    }

    & $OpenCcDictPath -i $source -o $target -f text -t ocd2
    if ($LASTEXITCODE -ne 0) {
      throw "opencc_dict failed while building $reference (exit code $LASTEXITCODE)."
    }
    if (-not (Test-Path -LiteralPath $target -PathType Leaf)) {
      throw "opencc_dict did not create expected output: $target"
    }

    $generated.Add((Get-PackCustomDataRelativePath $target $OutputData))
  }

  return @($generated)
}

function Get-PackLibrimeToolCandidateRoots([string]$WeaselRoot) {
  $roots = New-Object System.Collections.Generic.List[string]
  foreach ($relative in @(
    'librime\bin',
    'librime\deps\opencc\build_x64\src\tools\Release',
    'librime\deps\opencc\build\src\tools\Release',
    'librime\deps\opencc\build_Win32\src\tools\Release',
    'librime\deps\opencc\build_arm64\src\tools\Release',
    'librime\dist\bin'
  )) {
    $roots.Add((Join-Path $WeaselRoot $relative))
  }

  $openccDepsRoot = Join-Path $WeaselRoot 'librime\deps\opencc'
  if (Test-Path -LiteralPath $openccDepsRoot -PathType Container) {
    Get-ChildItem -LiteralPath $openccDepsRoot -Directory -Filter 'build*' -ErrorAction SilentlyContinue |
      Sort-Object Name |
      ForEach-Object {
        $roots.Add((Join-Path $_.FullName 'src\tools\Release'))
      }
  }

  $extractedRoot = Join-Path $WeaselRoot '.pack-rime\extracted'
  if (Test-Path -LiteralPath $extractedRoot -PathType Container) {
    Get-ChildItem -LiteralPath $extractedRoot -Directory -ErrorAction SilentlyContinue |
      Sort-Object @{ Expression = {
          if ($_.Name -match 'x64') { 0 }
          elseif ($_.Name -match 'x86') { 1 }
          else { 2 }
        }
      }, Name |
      ForEach-Object {
        $roots.Add((Join-Path $_.FullName 'bin'))
        $roots.Add((Join-Path $_.FullName 'dist\bin'))
      }
  }

  return @($roots)
}

function Resolve-PackLibrimeToolPath([string]$WeaselRoot, [string]$ToolName) {
  foreach ($root in Get-PackLibrimeToolCandidateRoots $WeaselRoot) {
    $candidate = Join-Path $root $ToolName
    if (Test-Path -LiteralPath $candidate -PathType Leaf) {
      return [System.IO.Path]::GetFullPath($candidate)
    }
  }
  return $null
}

function Sync-PackLibrimeOpenCcTools([string]$WeaselRoot) {
  $canonicalRoot = Join-Path $WeaselRoot 'librime\bin'
  if (-not (Test-Path -LiteralPath $canonicalRoot)) {
    New-Item -ItemType Directory -Path $canonicalRoot -Force | Out-Null
  }

  $synced = New-Object System.Collections.Generic.List[string]
  foreach ($tool in @('opencc.exe', 'opencc_dict.exe', 'opencc_phrase_extract.exe')) {
    $source = Resolve-PackLibrimeToolPath -WeaselRoot $WeaselRoot -ToolName $tool
    if (-not $source) {
      continue
    }

    $destination = Join-Path $canonicalRoot $tool
    if (-not ([System.IO.Path]::GetFullPath($source).Equals(
        [System.IO.Path]::GetFullPath($destination),
        [StringComparison]::OrdinalIgnoreCase))) {
      Copy-Item -LiteralPath $source -Destination $destination -Force
    }
    $synced.Add("librime/bin/$tool")
  }

  return @($synced)
}

function Invoke-PackGeneratorRule([string]$OutputData, [string]$PythonPath, [string]$ScriptRel, [string]$OutputRel) {
  $scriptPath = Join-Path $OutputData $ScriptRel
  if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
    return $null
  }

  $outputPath = [System.IO.Path]::GetFullPath((Join-Path $OutputData $OutputRel))
  if (-not (Test-PackPathUnderRoot $outputPath $OutputData)) {
    throw "custom-data generator output escapes output data directory: $OutputRel"
  }
  if (Test-Path -LiteralPath $outputPath -PathType Leaf) {
    return $null
  }
  if (-not (Test-Path -LiteralPath $PythonPath -PathType Leaf)) {
    throw "python not found for custom-data generator '$ScriptRel': $PythonPath"
  }

  $outputDir = Split-Path -Parent $outputPath
  if (-not (Test-Path -LiteralPath $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
  }
  $tempOutput = Join-Path $outputDir ([System.IO.Path]::GetFileName($outputPath) + '.tmp')
  if (Test-Path -LiteralPath $tempOutput) {
    Remove-Item -LiteralPath $tempOutput -Force
  }

  Push-Location $OutputData
  $oldPythonUtf8 = $env:PYTHONUTF8
  try {
    $env:PYTHONUTF8 = '1'
    & $PythonPath $ScriptRel > $tempOutput
    if ($LASTEXITCODE -ne 0) {
      throw "custom-data generator '$ScriptRel' failed with exit code $LASTEXITCODE."
    }
  } finally {
    if ($null -eq $oldPythonUtf8) {
      Remove-Item Env:\PYTHONUTF8 -ErrorAction SilentlyContinue
    } else {
      $env:PYTHONUTF8 = $oldPythonUtf8
    }
    Pop-Location
  }

  if (-not (Test-Path -LiteralPath $tempOutput -PathType Leaf)) {
    throw "custom-data generator '$ScriptRel' did not create output: $OutputRel"
  }
  Move-Item -LiteralPath $tempOutput -Destination $outputPath -Force
  return ($OutputRel -replace '\\','/')
}

function Invoke-PackCustomDataGenerators([string]$OutputData, [string]$PythonPath) {
  $rules = @(
    @{ Script = 'tools\gen_chars.py'; Output = 'moran.chars.dict.yaml' },
    @{ Script = 'tools\gen_zrmdb.py'; Output = 'lua\zrmdb.txt' },
    @{ Script = 'tools\gen_chaifen_filter.py'; Output = 'opencc\moran_chaifen.txt' }
  )

  $generated = New-Object System.Collections.Generic.List[string]
  foreach ($rule in $rules) {
    $rel = Invoke-PackGeneratorRule -OutputData $OutputData -PythonPath $PythonPath -ScriptRel $rule.Script -OutputRel $rule.Output
    if ($rel) {
      $generated.Add($rel)
    }
  }
  return @($generated)
}

function ConvertTo-PackRimeReferenceName([string]$Value) {
  $name = ($Value -replace '#.*$','').Trim().Trim('"', "'")
  if ($name -match '^[A-Za-z0-9_.-]+$') {
    return $name
  }
  return $null
}

function Add-PackExistingDataBasename(
  [System.Collections.Generic.HashSet[string]]$Set,
  [string]$OutputData,
  [string]$Basename
) {
  if ([string]::IsNullOrWhiteSpace($Basename)) {
    return $false
  }
  if (Test-Path -LiteralPath (Join-Path $OutputData $Basename) -PathType Leaf) {
    return $Set.Add($Basename)
  }
  return $false
}

function Get-PackReferencedTopLevelDataBasenames([string]$Path, [string]$OutputData) {
  $refs = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
  $inDependencies = $false
  $inImportTables = $false

  foreach ($line in Get-Content -LiteralPath $Path -Encoding UTF8) {
    $stripped = $line -replace '#.*$',''

    if ($stripped -match '^\s*dependencies\s*:\s*$') {
      $inDependencies = $true
      $inImportTables = $false
      continue
    }
    if ($stripped -match '^\s*import_tables\s*:\s*$') {
      $inImportTables = $true
      $inDependencies = $false
      continue
    }
    if ($stripped -match '^\S' -and $stripped -notmatch '^\s*-') {
      $inDependencies = $false
      $inImportTables = $false
    }

    if ($inDependencies -and $stripped -match '^\s*-\s*([A-Za-z0-9_.-]+)\s*$') {
      $name = ConvertTo-PackRimeReferenceName $Matches[1]
      if ($name) {
        [void](Add-PackExistingDataBasename $refs $OutputData "$name.schema.yaml")
        [void](Add-PackExistingDataBasename $refs $OutputData "$name.dict.yaml")
      }
      continue
    }

    if ($inImportTables -and $stripped -match '^\s*-\s*([A-Za-z0-9_.-]+)\s*$') {
      $name = ConvertTo-PackRimeReferenceName $Matches[1]
      if ($name) {
        [void](Add-PackExistingDataBasename $refs $OutputData "$name.dict.yaml")
      }
      continue
    }

    if ($stripped -match '^\s*dictionary\s*:\s*(.+?)\s*$') {
      $name = ConvertTo-PackRimeReferenceName $Matches[1]
      if ($name) {
        [void](Add-PackExistingDataBasename $refs $OutputData "$name.dict.yaml")
      }
    }
  }

  return @($refs | Sort-Object)
}

function Get-PackRequiredTopLevelDataBasenames([string]$OutputData, [string[]]$SeedBasenames) {
  $keep = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
  $queue = [System.Collections.Generic.Queue[string]]::new()

  foreach ($basename in $SeedBasenames) {
    if (Add-PackExistingDataBasename $keep $OutputData $basename) {
      $queue.Enqueue($basename)
    }
  }

  while ($queue.Count -gt 0) {
    $basename = $queue.Dequeue()
    $path = Join-Path $OutputData $basename
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
      continue
    }

    foreach ($ref in Get-PackReferencedTopLevelDataBasenames -Path $path -OutputData $OutputData) {
      if ($keep.Add($ref)) {
        $queue.Enqueue($ref)
      }
    }
  }

  return @($keep | Sort-Object)
}

Export-ModuleMember -Function Copy-PackCustomDataFile, Convert-PackCustomOpenCcTextDictionaries, Resolve-PackLibrimeToolPath, Sync-PackLibrimeOpenCcTools, Invoke-PackCustomDataGenerators, Get-PackRequiredTopLevelDataBasenames
