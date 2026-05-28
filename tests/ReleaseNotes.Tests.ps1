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
  It 'groups installer tables by Weasel variant in the requested order' {
    $manifests = @(
      [pscustomobject]@{
        installer = 'weasel-moran-qing-0.17.4-installer.exe'
        data = [pscustomobject]@{
          name = 'moran'
          display = '魔然'
          url = 'https://github.com/rimeinn/rime-moran.git'
          ref = 'main'
          sha = '1111111111111111111111111111111111111111'
          commit_time = '2026-05-27T10:11:12+00:00'
        }
        weasel = [pscustomobject]@{
          name = 'qing'
          display = '晴版小狼毫'
          url = 'https://github.com/a810439322/weasel.git'
          ref = 'master'
          sha = '3333333333333333333333333333333333333333'
          commit_time = '2026-05-22T03:59:40+00:00'
        }
      }
      [pscustomobject]@{
        installer = 'weasel-moran-fxliang-0.17.4-installer.exe'
        data = [pscustomobject]@{
          name = 'moran'
          display = '魔然'
          url = 'https://github.com/rimeinn/rime-moran.git'
          ref = 'main'
          sha = '1111111111111111111111111111111111111111'
          commit_time = '2026-05-27T10:11:12+00:00'
        }
        weasel = [pscustomobject]@{
          name = 'fxliang'
          display = 'fxliang 小狼毫'
          url = 'https://github.com/fxliang/weasel.git'
          ref = 'pb'
          sha = '2222222222222222222222222222222222222222'
          commit_time = '2026-05-07T05:54:33+00:00'
        }
      }
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
          sha = '4444444444444444444444444444444444444444'
          commit_time = '2026-03-06T09:26:08+00:00'
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
    $officialIndex = $notes.IndexOf('### 官方小狼毫', [StringComparison]::Ordinal)
    $fxliangIndex = $notes.IndexOf('### fxliang 小狼毫', [StringComparison]::Ordinal)
    $qingIndex = $notes.IndexOf('### 晴版小狼毫', [StringComparison]::Ordinal)

    $officialIndex | Should -BeGreaterOrEqual 0
    $fxliangIndex | Should -BeGreaterThan $officialIndex
    $qingIndex | Should -BeGreaterThan $fxliangIndex
    ([regex]::Matches($notes, '\| 方案 \| 提交时间 \| 安装包 \|')).Count | Should -Be 3
    $notes | Should -Match '\| 魔然 \| 2026-05-27 18:11:12 \| \[weasel-moran-rime-0\.17\.4-installer\.exe\]\(https://github\.com/a810439322/rime-auto-build/releases/download/build-20260528-1838-upstream/weasel-moran-rime-0\.17\.4-installer\.exe\) \|'
    $notes | Should -Match '\| 魔然 \| 2026-05-27 18:11:12 \| \[weasel-moran-fxliang-0\.17\.4-installer\.exe\]\(https://github\.com/a810439322/rime-auto-build/releases/download/build-20260528-1838-upstream/weasel-moran-fxliang-0\.17\.4-installer\.exe\) \|'
    $notes | Should -Match '\| 魔然 \| 2026-05-27 18:11:12 \| \[weasel-moran-qing-0\.17\.4-installer\.exe\]\(https://github\.com/a810439322/rime-auto-build/releases/download/build-20260528-1838-upstream/weasel-moran-qing-0\.17\.4-installer\.exe\) \|'
    $notes | Should -Not -Match '\| 方案 \| 小狼毫 \| 安装包 \|'
    $notes | Should -Not -Match '`main` @ `1111111`'
    $notes | Should -Not -Match '\[仓库\]'
  }

  It 'can recover installer manifests from the old detailed release table' {
    $oldNotes = @'
自动构建。

## 安装包说明

| 安装包 | 方案 | 小狼毫 |
| --- | --- | --- |
| `weasel-092wb-rime-0.17.4.0.93eec2d-installer.exe` | 092五笔 (`092wb`)<br>`main` @ `9b1d953`<br>2026-04-28T20:11:51Z<br>https://github.com/092wb/092wb.git | 官方小狼毫 (`rime`)<br>`master` @ `93eec2d`<br>2026-03-06T09:26:08Z<br>https://github.com/rime/weasel.git |
'@

    $manifests = @(ConvertFrom-ReleaseNotes -Markdown $oldNotes)

    $manifests.Count | Should -Be 1
    $manifests[0].installer | Should -Be 'weasel-092wb-rime-0.17.4.0.93eec2d-installer.exe'
    $manifests[0].data.name | Should -Be '092wb'
    $manifests[0].data.display | Should -Be '092五笔'
    $manifests[0].data.ref | Should -Be 'main'
    $manifests[0].data.sha | Should -Be '9b1d953'
    $manifests[0].data.commit_time | Should -Be '2026-04-28T20:11:51Z'
    $manifests[0].weasel.name | Should -Be 'rime'
    $manifests[0].weasel.display | Should -Be '官方小狼毫'
    $manifests[0].weasel.url | Should -Be 'https://github.com/rime/weasel.git'
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
    $notes | Should -Match '### fxliang 小狼毫'
    $notes | Should -Match '\| 方案 \| 提交时间 \| 安装包 \|'
    $notes | Should -Match '\| 魔然 \| 2026-05-27 18:11:12 \| \[weasel-moran-fxliang-0\.17\.4-installer\.exe\]\(https://github\.com/a810439322/rime-auto-build/releases/download/build-20260528-1838-upstream/weasel-moran-fxliang-0\.17\.4-installer\.exe\) \|'
  }
}
