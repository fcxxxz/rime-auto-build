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

Export-ModuleMember -Function Copy-PackCustomDataFile
