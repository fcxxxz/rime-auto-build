$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $PSCommandPath
$RepoRoot = Split-Path -Parent $ScriptDir
Import-Module (Join-Path $ScriptDir 'lib\LibrimeCache.psm1') -Force

$source = Join-Path $RepoRoot '.librime-cache\weasel'
$destination = Join-Path $RepoRoot '.\weasel'

$restored = @(Restore-LibrimeCacheOutputs -SourceWeaselRoot $source -DestinationWeaselRoot $destination)
Write-Host ("Restored {0} librime cache file(s)." -f $restored.Count)
foreach ($relativePath in $restored) {
  Write-Host "  $relativePath"
}
