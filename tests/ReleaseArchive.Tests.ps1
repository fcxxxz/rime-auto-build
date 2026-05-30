Describe 'merge-release-assets.ps1' {
  It 'merges previous release packages with current packages overriding the same data-weasel combination' {
    $root = Join-Path $TestDrive 'release-archive'
    $previousPackages = Join-Path $root 'previous-packages'
    $previousManifests = Join-Path $root 'previous-manifests'
    $currentPackages = Join-Path $root 'current-packages'
    $currentManifests = Join-Path $root 'current-manifests'
    $outPackages = Join-Path $root 'out-packages'
    $outManifests = Join-Path $root 'out-manifests'
    $archive = Join-Path $root 'release-manifests.zip'
    $buildsPath = Join-Path $root 'builds.yaml'

    @($previousPackages, $previousManifests, $currentPackages, $currentManifests) |
      ForEach-Object { New-Item -ItemType Directory -Path $_ -Force | Out-Null }
    Set-Content -LiteralPath $buildsPath -Encoding UTF8 -Value @'
weasels:
  - name: rime
    display: 官方小狼毫
    url: https://github.com/rime/weasel.git
    ref: master
datas:
  - name: moran
    display: 魔然
    url: https://github.com/rimeinn/rime-moran.git
    ref: main
  - name: tiger
    display: 虎码
    url: https://github.com/a810439322/rime-tiger.git
    ref: main
excludes: []
'@

    Set-Content -LiteralPath (Join-Path $previousPackages 'weasel-moran-rime-old-installer.exe') -Value 'old moran'
    Set-Content -LiteralPath (Join-Path $previousPackages 'weasel-tiger-rime-old-installer.exe') -Value 'old tiger'
    Set-Content -LiteralPath (Join-Path $currentPackages 'weasel-tiger-rime-new-installer.exe') -Value 'new tiger'

    @{
      installer = 'weasel-moran-rime-old-installer.exe'
      data = @{ name = 'moran'; display = '魔然'; url = 'https://github.com/rimeinn/rime-moran.git'; ref = 'main'; sha = 'old-data'; commit_time = '2026-05-27T10:11:12Z' }
      weasel = @{ name = 'rime'; display = '官方小狼毫'; url = 'https://github.com/rime/weasel.git'; ref = 'master'; sha = 'old-weasel'; commit_time = '2026-03-06T09:26:08Z' }
    } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $previousManifests 'manifest-moran-rime.json')

    @{
      installer = 'weasel-tiger-rime-old-installer.exe'
      data = @{ name = 'tiger'; display = '虎码'; url = 'https://github.com/a810439322/rime-tiger.git'; ref = 'main'; sha = 'old-tiger'; commit_time = '2026-05-27T09:53:46Z' }
      weasel = @{ name = 'rime'; display = '官方小狼毫'; url = 'https://github.com/rime/weasel.git'; ref = 'master'; sha = 'old-weasel'; commit_time = '2026-03-06T09:26:08Z' }
    } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $previousManifests 'manifest-tiger-rime.json')

    @{
      installer = 'weasel-tiger-rime-new-installer.exe'
      data = @{ name = 'tiger'; display = '虎码'; url = 'https://github.com/a810439322/rime-tiger.git'; ref = 'main'; sha = 'new-tiger'; commit_time = '2026-05-28T10:29:55Z' }
      weasel = @{ name = 'rime'; display = '官方小狼毫'; url = 'https://github.com/rime/weasel.git'; ref = 'master'; sha = 'old-weasel'; commit_time = '2026-03-06T09:26:08Z' }
    } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $currentManifests 'manifest-tiger-rime.json')

    & (Join-Path $PSScriptRoot '..\scripts\merge-release-assets.ps1') `
      -PreviousPackageRoot $previousPackages `
      -PreviousManifestRoot $previousManifests `
      -CurrentPackageRoot $currentPackages `
      -CurrentManifestRoot $currentManifests `
      -OutputPackageRoot $outPackages `
      -OutputManifestRoot $outManifests `
      -ManifestArchivePath $archive `
      -BuildsPath $buildsPath

    Test-Path -LiteralPath (Join-Path $outPackages 'weasel-moran-rime-old-installer.exe') | Should -BeTrue
    Test-Path -LiteralPath (Join-Path $outPackages 'weasel-tiger-rime-new-installer.exe') | Should -BeTrue
    Test-Path -LiteralPath (Join-Path $outPackages 'weasel-tiger-rime-old-installer.exe') | Should -BeFalse
    Test-Path -LiteralPath $archive | Should -BeTrue

    $mergedTiger = Get-Content -LiteralPath (Join-Path $outManifests 'manifest-tiger-rime.json') -Raw | ConvertFrom-Json
    $mergedTiger.installer | Should -Be 'weasel-tiger-rime-new-installer.exe'
    $mergedTiger.data.sha | Should -Be 'new-tiger'
  }

  It 'drops previous release packages for data-weasel combinations no longer configured' {
    $root = Join-Path $TestDrive 'release-archive-filter'
    $previousPackages = Join-Path $root 'previous-packages'
    $previousManifests = Join-Path $root 'previous-manifests'
    $currentPackages = Join-Path $root 'current-packages'
    $currentManifests = Join-Path $root 'current-manifests'
    $outPackages = Join-Path $root 'out-packages'
    $outManifests = Join-Path $root 'out-manifests'
    $archive = Join-Path $root 'release-manifests.zip'
    $buildsPath = Join-Path $root 'builds.yaml'

    @($previousPackages, $previousManifests, $currentPackages, $currentManifests) |
      ForEach-Object { New-Item -ItemType Directory -Path $_ -Force | Out-Null }
    Set-Content -LiteralPath $buildsPath -Encoding UTF8 -Value @'
weasels:
  - name: rime
    display: 官方小狼毫
    url: https://github.com/rime/weasel.git
    ref: master
datas:
  - name: tiger
    display: 虎码
    url: https://github.com/a810439322/rime-tiger.git
    ref: main
excludes: []
'@

    Set-Content -LiteralPath (Join-Path $previousPackages 'weasel-moran-rime-old-installer.exe') -Value 'old moran'
    Set-Content -LiteralPath (Join-Path $previousPackages 'weasel-tiger-rime-old-installer.exe') -Value 'old tiger'

    @{
      installer = 'weasel-moran-rime-old-installer.exe'
      data = @{ name = 'moran'; display = '魔然'; url = 'https://github.com/rimeinn/rime-moran.git'; ref = 'main'; sha = 'old-data'; commit_time = '2026-05-27T10:11:12Z' }
      weasel = @{ name = 'rime'; display = '官方小狼毫'; url = 'https://github.com/rime/weasel.git'; ref = 'master'; sha = 'old-weasel'; commit_time = '2026-03-06T09:26:08Z' }
    } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $previousManifests 'manifest-moran-rime.json')

    @{
      installer = 'weasel-tiger-rime-old-installer.exe'
      data = @{ name = 'tiger'; display = '虎码'; url = 'https://github.com/a810439322/rime-tiger.git'; ref = 'main'; sha = 'old-tiger'; commit_time = '2026-05-27T09:53:46Z' }
      weasel = @{ name = 'rime'; display = '官方小狼毫'; url = 'https://github.com/rime/weasel.git'; ref = 'master'; sha = 'old-weasel'; commit_time = '2026-03-06T09:26:08Z' }
    } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $previousManifests 'manifest-tiger-rime.json')

    & (Join-Path $PSScriptRoot '..\scripts\merge-release-assets.ps1') `
      -PreviousPackageRoot $previousPackages `
      -PreviousManifestRoot $previousManifests `
      -CurrentPackageRoot $currentPackages `
      -CurrentManifestRoot $currentManifests `
      -OutputPackageRoot $outPackages `
      -OutputManifestRoot $outManifests `
      -ManifestArchivePath $archive `
      -BuildsPath $buildsPath

    Test-Path -LiteralPath (Join-Path $outPackages 'weasel-moran-rime-old-installer.exe') | Should -BeFalse
    Test-Path -LiteralPath (Join-Path $outManifests 'manifest-moran-rime.json') | Should -BeFalse
    Test-Path -LiteralPath (Join-Path $outPackages 'weasel-tiger-rime-old-installer.exe') | Should -BeTrue
    Test-Path -LiteralPath (Join-Path $outManifests 'manifest-tiger-rime.json') | Should -BeTrue
  }
}
