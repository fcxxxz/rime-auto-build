$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $PSCommandPath
$RepoRoot = Split-Path -Parent $ScriptDir
Import-Module (Join-Path $ScriptDir 'lib\LibrimeCache.psm1') -Force

$source = Join-Path $RepoRoot '.pack-work\weasel'
$destination = Join-Path $RepoRoot '.\weasel'

$copied = @(Copy-LibrimeCacheOutputs -SourceWeaselRoot $source -DestinationWeaselRoot $destination)
Write-Host ("Synced {0} librime cache file(s)." -f $copied.Count)
foreach ($relativePath in $copied) {
  Write-Host "  $relativePath"
}
