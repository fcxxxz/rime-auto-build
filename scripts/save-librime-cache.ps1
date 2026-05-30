$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $PSCommandPath
$RepoRoot = Split-Path -Parent $ScriptDir
Import-Module (Join-Path $ScriptDir 'lib\LibrimeCache.psm1') -Force

$source = Join-Path $RepoRoot '.pack-work\weasel'
$cacheRoot = Join-Path $RepoRoot '.librime-cache'
$destination = Join-Path $cacheRoot 'weasel'

$repoFullPath = [System.IO.Path]::GetFullPath($RepoRoot)
$cacheFullPath = [System.IO.Path]::GetFullPath($cacheRoot)
$repoPrefix = $repoFullPath.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
if (-not $cacheFullPath.StartsWith($repoPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
  throw "Refusing to clear cache path outside repository: $cacheFullPath"
}

if (Test-Path -LiteralPath $cacheRoot) {
  Remove-Item -LiteralPath $cacheRoot -Recurse -Force
}

$copied = @(Copy-LibrimeCacheOutputs -SourceWeaselRoot $source -DestinationWeaselRoot $destination)
Write-Host ("Synced {0} librime cache file(s)." -f $copied.Count)
foreach ($relativePath in $copied) {
  Write-Host "  $relativePath"
}
