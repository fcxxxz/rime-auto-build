BeforeAll {
  $ModulePath = Join-Path $PSScriptRoot '..\scripts\lib\ReleaseNotes.psm1'
  Import-Module $ModulePath -Force
}

Describe 'New-InstallerManifest' {
  It 'records the installer file and exact source repositories' {
    $manifest = New-InstallerManifest `
      -InstallerName 'weasel-moran-rime-0.17.4-installer.exe' `
      -DataName 'moran' `
      -DataDisplay '魔然' `
      -DataUrl 'https://github.com/rimeinn/rime-moran.git' `
      -DataRef 'main' `
      -DataSha '1111111111111111111111111111111111111111' `
      -DataCommitTime '2026-05-27T10:11:12+00:00' `
      -WeaselName 'rime' `
      -WeaselDisplay '官方小狼毫' `
      -WeaselUrl 'https://github.com/rime/weasel.git' `
      -WeaselRef 'master' `
      -WeaselSha '2222222222222222222222222222222222222222' `
      -WeaselCommitTime '2026-05-28T01:02:03+00:00'

    $manifest.installer | Should -Be 'weasel-moran-rime-0.17.4-installer.exe'
    $manifest.data.name | Should -Be 'moran'
    $manifest.data.display | Should -Be '魔然'
    $manifest.data.sha | Should -Be '1111111111111111111111111111111111111111'
    $manifest.data.commit_time | Should -Be '2026-05-27T10:11:12+00:00'
    $manifest.weasel.name | Should -Be 'rime'
    $manifest.weasel.display | Should -Be '官方小狼毫'
    $manifest.weasel.sha | Should -Be '2222222222222222222222222222222222222222'
    $manifest.weasel.commit_time | Should -Be '2026-05-28T01:02:03+00:00'
  }
}

Describe 'New-ReleaseNotes' {
  It 'lists each installer by data, weasel, and a downloadable installer link' {
    $manifests = @(
      [pscustomobject]@{
        installer = 'weasel-moran-rime-0.17.4-installer.exe'
        data = [pscustomobject]@{
          name = 'moran'
          display = '魔然'
          url = 'https://github.com/rimeinn/rime-moran.git'
          ref = 'main'
          sha = '1111111111111111111111111111111111111111'
          commit_time = '2026-05-27T10:11:12+00:00'
        }
        weasel = [pscustomobject]@{
          name = 'rime'
          display = '官方小狼毫'
          url = 'https://github.com/rime/weasel.git'
          ref = 'master'
          sha = '2222222222222222222222222222222222222222'
          commit_time = '2026-05-28T01:02:03+00:00'
        }
      }
    )

    $notes = New-ReleaseNotes `
      -EventName 'workflow_dispatch' `
      -StatePath 'state/last-seen.json' `
      -BuildsPath 'builds.yaml' `
      -ReleaseTag 'build-20260528-1838-upstream' `
      -Repository 'a810439322/rime-auto-build' `
      -Manifests $manifests

    $notes | Should -Match '## 安装包说明'
    $notes | Should -Match '\| 方案 \| 小狼毫 \| 安装包 \|'
    $notes | Should -Match '\| 魔然<br>2026-05-27 18:11:12 \| 官方小狼毫<br>2026-05-28 09:02:03 \| \[weasel-moran-rime-0\.17\.4-installer\.exe\]\(https://github\.com/a810439322/rime-auto-build/releases/download/build-20260528-1838-upstream/weasel-moran-rime-0\.17\.4-installer\.exe\) \|'
    $notes | Should -Not -Match '`main` @ `1111111`'
    $notes | Should -Not -Match '\[仓库\]'
  }
}

Describe 'release notes scripts' {
  It 'writes manifests and release notes when invoked as scripts with parameters' {
    $root = Join-Path $TestDrive 'release-notes'
    New-Item -ItemType Directory -Path $root | Out-Null

    $manifestPath = Join-Path $root 'manifest-moran-fxliang.json'
    $notesPath = Join-Path $root 'release-notes.md'

    & (Join-Path $PSScriptRoot '..\scripts\write-installer-manifest.ps1') `
      -InstallerName 'weasel-moran-fxliang-0.17.4-installer.exe' `
      -DataName 'moran' `
      -DataDisplay '魔然' `
      -DataUrl 'https://github.com/rimeinn/rime-moran.git' `
      -DataRef 'main' `
      -DataSha '1111111111111111111111111111111111111111' `
      -DataCommitTime '2026-05-27T10:11:12+00:00' `
      -WeaselName 'fxliang' `
      -WeaselDisplay 'fxliang 小狼毫' `
      -WeaselUrl 'https://github.com/fxliang/weasel.git' `
      -WeaselRef 'pb' `
      -WeaselSha '2222222222222222222222222222222222222222' `
      -WeaselCommitTime '2026-05-28T01:02:03+00:00' `
      -OutputPath $manifestPath

    & (Join-Path $PSScriptRoot '..\scripts\write-release-notes.ps1') `
      -ManifestRoot $root `
      -OutputPath $notesPath `
      -EventName 'workflow_dispatch' `
      -ReleaseTag 'build-20260528-1838-upstream' `
      -Repository 'a810439322/rime-auto-build'

    $notes = Get-Content -LiteralPath $notesPath -Raw
    $notes | Should -Match '\| 方案 \| 小狼毫 \| 安装包 \|'
    $notes | Should -Match '\| 魔然<br>2026-05-27 18:11:12 \| fxliang 小狼毫<br>2026-05-28 09:02:03 \| \[weasel-moran-fxliang-0\.17\.4-installer\.exe\]\(https://github\.com/a810439322/rime-auto-build/releases/download/build-20260528-1838-upstream/weasel-moran-fxliang-0\.17\.4-installer\.exe\) \|'
  }
}
