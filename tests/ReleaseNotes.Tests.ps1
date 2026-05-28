BeforeAll {
  $ModulePath = Join-Path $PSScriptRoot '..\scripts\lib\ReleaseNotes.psm1'
  Import-Module $ModulePath -Force
}

Describe 'New-InstallerManifest' {
  It 'records the installer file and exact source repositories' {
    $manifest = New-InstallerManifest `
      -InstallerName 'weasel-moran-official-0.17.4-installer.exe' `
      -DataName 'moran' `
      -DataUrl 'https://github.com/rimeinn/rime-moran.git' `
      -DataRef 'main' `
      -DataSha '1111111111111111111111111111111111111111' `
      -WeaselName 'official' `
      -WeaselUrl 'https://github.com/rime/weasel.git' `
      -WeaselRef 'master' `
      -WeaselSha '2222222222222222222222222222222222222222'

    $manifest.installer | Should -Be 'weasel-moran-official-0.17.4-installer.exe'
    $manifest.data.name | Should -Be 'moran'
    $manifest.data.sha | Should -Be '1111111111111111111111111111111111111111'
    $manifest.weasel.name | Should -Be 'official'
    $manifest.weasel.sha | Should -Be '2222222222222222222222222222222222222222'
  }
}

Describe 'New-ReleaseNotes' {
  It 'lists each installer with data and Weasel source details' {
    $manifests = @(
      [pscustomobject]@{
        installer = 'weasel-moran-official-0.17.4-installer.exe'
        data = [pscustomobject]@{
          name = 'moran'
          url = 'https://github.com/rimeinn/rime-moran.git'
          ref = 'main'
          sha = '1111111111111111111111111111111111111111'
        }
        weasel = [pscustomobject]@{
          name = 'official'
          url = 'https://github.com/rime/weasel.git'
          ref = 'master'
          sha = '2222222222222222222222222222222222222222'
        }
      }
    )

    $notes = New-ReleaseNotes -EventName 'workflow_dispatch' -StatePath 'state/last-seen.json' -BuildsPath 'builds.yaml' -Manifests $manifests

    $notes | Should -Match '## 安装包说明'
    $notes | Should -Match 'weasel-moran-official-0\.17\.4-installer\.exe'
    $notes | Should -Match '方案：`moran` \(`main` @ `1111111`\) https://github\.com/rimeinn/rime-moran\.git'
    $notes | Should -Match '小狼毫：`official` \(`master` @ `2222222`\) https://github\.com/rime/weasel\.git'
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
      -DataUrl 'https://github.com/rimeinn/rime-moran.git' `
      -DataRef 'main' `
      -DataSha '1111111111111111111111111111111111111111' `
      -WeaselName 'fxliang' `
      -WeaselUrl 'https://github.com/fxliang/weasel.git' `
      -WeaselRef 'pb' `
      -WeaselSha '2222222222222222222222222222222222222222' `
      -OutputPath $manifestPath

    & (Join-Path $PSScriptRoot '..\scripts\write-release-notes.ps1') `
      -ManifestRoot $root `
      -OutputPath $notesPath `
      -EventName 'workflow_dispatch'

    $notes = Get-Content -LiteralPath $notesPath -Raw
    $notes | Should -Match 'weasel-moran-fxliang-0\.17\.4-installer\.exe'
    $notes | Should -Match '小狼毫：`fxliang` \(`pb` @ `2222222`\) https://github\.com/fxliang/weasel\.git'
  }
}
