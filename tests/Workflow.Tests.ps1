BeforeAll {
  $WorkflowPath = Join-Path $PSScriptRoot '..\.github\workflows\build.yml'
  $WatchWorkflowPath = Join-Path $PSScriptRoot '..\.github\workflows\watch.yml'
  $PackageRequestWorkflowPath = Join-Path $PSScriptRoot '..\.github\workflows\package-request.yml'
  $PackageRequestIssueTemplatePath = Join-Path $PSScriptRoot '..\.github\ISSUE_TEMPLATE\package-data.yml'
  $PackPath = Join-Path $PSScriptRoot '..\pack.ps1'
  $PrepareBoostPath = Join-Path $PSScriptRoot '..\scripts\prepare-boost.ps1'
  $SaveLibrimeCachePath = Join-Path $PSScriptRoot '..\scripts\save-librime-cache.ps1'
  $MergeReleaseAssetsPath = Join-Path $PSScriptRoot '..\scripts\merge-release-assets.ps1'
  $RestorePreviousReleaseAssetsPath = Join-Path $PSScriptRoot '..\scripts\restore-previous-release-assets.ps1'
  $WriteInstallerManifestPath = Join-Path $PSScriptRoot '..\scripts\write-installer-manifest.ps1'
  $WriteReleaseNotesPath = Join-Path $PSScriptRoot '..\scripts\write-release-notes.ps1'
}

Describe 'package request issue template' {
  It 'collects a public GitHub data repository and exactly one Weasel variant' {
    Test-Path -LiteralPath $PackageRequestIssueTemplatePath | Should -BeTrue
    $content = Get-Content -LiteralPath $PackageRequestIssueTemplatePath -Raw

    $content | Should -Match '(?s)labels:\s+\-\s+package request'
    $content | Should -Match 'id:\s*repository'
    $content | Should -Match 'id:\s*ref'
    $content | Should -Match 'id:\s*weasel'
    $content | Should -Not -Match 'id:\s*data_name'
    $content | Should -Not -Match 'id:\s*data_display'
    $content | Should -Match 'type:\s*dropdown'
    $content | Should -Match '官方小狼毫（rime）'
    $content | Should -Match '晴版小狼毫（qing）'
    $content | Should -Match 'fxliang 小狼毫（fxliang）'
    $content | Should -Match 'https://github\.com/'
  }
}

Describe 'package request workflow' {
  It 'runs only for package request issues and uses issue-scoped concurrency' {
    Test-Path -LiteralPath $PackageRequestWorkflowPath | Should -BeTrue
    $content = Get-Content -LiteralPath $PackageRequestWorkflowPath -Raw

    $content | Should -Match '(?m)^on:\s*$'
    $content | Should -Match '(?s)issues:\s+types:\s+\-\s+opened'
    $content | Should -Not -Match '(?m)^\s*-\s+labeled\s*$'
    $content | Should -Not -Match "github\.event\.label\.name == 'package request'"
    $content | Should -Match "github\.event\.action == 'opened'"
    $content | Should -Not -Match "github\.event\.action == 'labeled'"
    $content | Should -Match "startsWith\(github\.event\.issue\.title, 'Package: '\)"
    $content | Should -Match "contains\(github\.event\.issue\.body, '### 公开 GitHub 仓库'\)"
    $content | Should -Match "contains\(github\.event\.issue\.body, '### Repository'\)"
    $content | Should -Match 'package-request-\$\{\{ github\.event\.issue\.number \}\}'
  }

  It 'keeps permissions limited to issue comments, artifacts, and cache needs' {
    $content = Get-Content -LiteralPath $PackageRequestWorkflowPath -Raw

    $content | Should -Match '(?s)permissions:\s+contents:\s*read\s+issues:\s*write\s+actions:\s*write'
    $content | Should -Match 'persist-credentials:\s*false'
    $content | Should -Not -Match 'contents:\s*write'
    $content | Should -Not -Match 'pull-requests:\s*write'
  }

  It 'validates issue fields before any Windows build starts' {
    $content = Get-Content -LiteralPath $PackageRequestWorkflowPath -Raw

    $content | Should -Match 'id:\s*prepare'
    $content | Should -Match '\$env:GITHUB_EVENT_PATH'
    $content | Should -Match '\./scripts/prepare-package-request\.ps1'
    $content | Should -Match 'gh api repos/\$\{\{ steps\.prepare\.outputs\.github_owner \}\}/\$\{\{ steps\.prepare\.outputs\.github_repo \}\}'
    $content | Should -Match 'default_branch'
    $content | Should -Match 'data_resolved_ref'
    $content | Should -Match '\./scripts/validate-package-ref\.ps1'
    $content | Should -Match 'REQUESTED_DATA_REF:\s*\$\{\{ steps\.prepare\.outputs\.data_ref \}\}'
    $content | Should -Match 'git init request-data-check'
    $content | Should -Match 'REQUEST_DATA_URL:\s*\$\{\{ steps\.prepare\.outputs\.data_url \}\}'
    $content | Should -Match 'REQUEST_DATA_REF:\s*\$\{\{ steps\.repository\.outputs\.data_resolved_ref \}\}'
    $content | Should -Match 'git -C request-data-check remote add origin "\$REQUEST_DATA_URL"'
    $content | Should -Match 'git -C request-data-check fetch --depth 1 origin -- "\$REQUEST_DATA_REF"'
    $content | Should -Match 'pwsh \./scripts/check-rime-data-shape\.ps1 -Path request-data-check'
    $content | Should -Match 'if:\s*\$\{\{ needs\.validate\.outputs\.valid == ''true'' \}\}'
    $content | Should -Not -Match '\$\{\{\s*github\.event\.issue\.body\s*\}\}'
  }

  It 'builds a single requested data/weasel pair without changing long-term config or releases' {
    $content = Get-Content -LiteralPath $PackageRequestWorkflowPath -Raw

    $content | Should -Match 'Clone weasel \(recursive\)'
    $content | Should -Match 'Clone data -> custom-data'
    $content | Should -Match 'DATA_REF:\s*\$\{\{ needs\.validate\.outputs\.data_resolved_ref \}\}'
    $content | Should -Match 'git -C custom-data fetch --depth 1 origin -- \$env:DATA_REF'
    $content | Should -Match 'git -C custom-data checkout --detach FETCH_HEAD'
    $content | Should -Match '\./scripts/check-rime-data-shape\.ps1 -Path custom-data'
    $content | Should -Match 'Resolve librime revision'
    $content | Should -Match 'Resolve librime-lua revision'
    $content | Should -Match 'Run pack\.ps1'
    $content | Should -Match 'Write installer manifest'
    $content | Should -Match 'name:\s*package-request-\$\{\{ github\.event\.issue\.number \}\}'
    $content | Should -Not -Match 'softprops/action-gh-release'
    $content | Should -Not -Match 'restore-previous-release-assets'
    $content | Should -Not -Match 'git add builds\.yaml'
    $content | Should -Not -Match 'state/last-seen\.json'
  }

  It 'comments success and failure details back to the issue' {
    $content = Get-Content -LiteralPath $PackageRequestWorkflowPath -Raw

    $content | Should -Match 'gh issue comment \$\{\{ github\.event\.issue\.number \}\} --repo \$\{\{ github\.repository \}\}'
    $content | Should -Match 'gh issue edit \$\{\{ github\.event\.issue\.number \}\} --repo \$\{\{ github\.repository \}\}'
    $content | Should -Match 'gh issue close \$\{\{ github\.event\.issue\.number \}\} --repo \$\{\{ github\.repository \}\}'
    $content | Should -Match 'gh label create "package succeeded" --repo \$\{\{ github\.repository \}\}'
    $content | Should -Match 'gh label create "package failure" --repo \$\{\{ github\.repository \}\}'
    $content | Should -Match '--body-file'
    $content | Should -Match '校验通过，开始打包'
    $content | Should -Match '打包完成'
    $content | Should -Match 'steps\.upload-package\.outputs\.artifact-url'
    $content | Should -Match 'needs\.build\.outputs\.artifact_url'
    $content | Should -Match '打包失败'
    $content | Should -Match 'package succeeded'
    $content | Should -Match 'package failure'
    $content | Should -Not -Match 'gh issue comment \$\{\{ github\.event\.issue\.number \}\} --body ".*`'
  }
}

Describe 'workflow YAML parsing' {
  It 'does not install powershell-yaml from PSGallery during CI planning' {
    $content = @(
      Get-Content -LiteralPath $WorkflowPath -Raw
      Get-Content -LiteralPath $WatchWorkflowPath -Raw
    ) -join "`n"

    $content | Should -Not -Match 'Install powershell-yaml'
    $content | Should -Not -Match 'Install-Module -Name powershell-yaml'
  }
}

Describe 'watch workflow schedule' {
  It 'runs on every Beijing hour zero using the equivalent UTC cron' {
    $content = Get-Content -LiteralPath $WatchWorkflowPath -Raw

    $content | Should -Match "cron:\s*'0 \* \* \* \*'"
    $content | Should -Not -Match "cron:\s*'17 \* \* \* \*'"
  }
}

Describe 'build workflow Boost cache' {
  It 'saves prepared Boost cache before installer-only dependencies and pack.ps1' {
    $content = Get-Content -LiteralPath $WorkflowPath -Raw

    $restore = $content.IndexOf('uses: actions/cache/restore@v4', [StringComparison]::Ordinal)
    $prepare = $content.IndexOf('name: Prepare Boost static libraries', [StringComparison]::Ordinal)
    $save = $content.IndexOf('uses: actions/cache/save@v4', [StringComparison]::Ordinal)
    $nsis = $content.IndexOf('name: Install NSIS', [StringComparison]::Ordinal)
    $pack = $content.IndexOf('name: Run pack.ps1', [StringComparison]::Ordinal)

    $restore | Should -BeGreaterOrEqual 0
    $prepare | Should -BeGreaterThan $restore
    $save | Should -BeGreaterThan $prepare
    $nsis | Should -BeGreaterThan $save
    $pack | Should -BeGreaterThan $save
  }

  It 'can restore the previous source-only Boost cache as a fallback' {
    $content = Get-Content -LiteralPath $WorkflowPath -Raw

    $content | Should -Match 'restore-keys:'
    $content | Should -Match 'boost-1\.84\.0-source-only-v1'
  }

  It 'uses a dedicated Boost preparation script for cacheable static libraries' {
    Test-Path -LiteralPath $PrepareBoostPath | Should -BeTrue
    $content = Get-Content -LiteralPath $PrepareBoostPath -Raw

    $content | Should -Match 'Get-MissingBoostLibraries'
    $content | Should -Match 'Get-BoostBuildArchitectures'
    $content | Should -Match 'Get-BoostBjamOptions'
    $content | Should -Not -Match 'build\.bat boost'
    $content | Should -Match 'bin\.v2'
  }

  It 'keeps missing-library checks as arrays when no library is missing' {
    $content = Get-Content -LiteralPath $PrepareBoostPath -Raw

    ([regex]::Matches($content, '\$missingBoost\s*=\s*@\(Get-MissingBoostLibraries \$BoostRoot\)')).Count |
      Should -Be 2
  }

  It 'uses a new prepared Boost cache generation after toolchain alignment changes' {
    $content = Get-Content -LiteralPath $WorkflowPath -Raw

    $content | Should -Match 'static-v3'
  }
}

Describe 'build workflow librime cache' {
  It 'restores librime outputs before pack.ps1 and saves them after a successful pack' {
    $content = Get-Content -LiteralPath $WorkflowPath -Raw

    $restore = $content.IndexOf('name: Restore librime cache', [StringComparison]::Ordinal)
    $pack = $content.IndexOf('name: Run pack.ps1', [StringComparison]::Ordinal)
    $sync = $content.IndexOf('name: Sync librime outputs for cache', [StringComparison]::Ordinal)
    $save = $content.IndexOf('name: Save librime cache', [StringComparison]::Ordinal)

    $restore | Should -BeGreaterOrEqual 0
    $pack | Should -BeGreaterThan $restore
    $sync | Should -BeGreaterThan $pack
    $save | Should -BeGreaterThan $sync
  }

  It 'keys librime cache by source revisions and selected MSVC toolset' {
    $content = Get-Content -LiteralPath $WorkflowPath -Raw

    $content | Should -Match 'id:\s*librime-rev'
    $content | Should -Match 'id:\s*librime-lua-rev'
    $content | Should -Match 'git ls-remote https://github\.com/hchunhui/librime-lua\.git refs/heads/master'
    $content | Should -Match 'git ls-remote https://github\.com/hchunhui/librime-lua\.git refs/heads/thirdparty'
    $content | Should -Match 'Test-Path -LiteralPath weasel/librime'
    $content | Should -Match 'git -C weasel/librime rev-parse HEAD'
    $content | Should -Match 'git ls-remote https://github\.com/rime/librime\.git refs/heads/master'
    $content | Should -Match 'git clone --depth 1 -b master https://github\.com/rime/librime\.git librime'
    $content | Should -Match 'librime HEAD \(external fallback\)'
    $content | Should -Match 'sdk_version='
    $content | Should -Match 'weasel/librime/bin/opencc_dict\.exe'
    $content | Should -Match 'librime-\$\{\{ runner\.os \}\}-weasel-\$\{\{ steps\.weasel-rev\.outputs\.sha \}\}-librime-\$\{\{ steps\.librime-rev\.outputs\.sha \}\}-librime-lua-\$\{\{ steps\.librime-lua-rev\.outputs\.lua_sha \}\}-lua-thirdparty-\$\{\{ steps\.librime-lua-rev\.outputs\.thirdparty_sha \}\}-msvc-\$\{\{ steps\.msvc\.outputs\.msvc_tools_version \}\}-sdk-\$\{\{ steps\.msvc\.outputs\.sdk_version \}\}-boost-static-v3-lua-v6'
    $content | Should -Not -Match '(?m)^\s+weasel/output/data/opencc\s*$'
  }

  It 'caches simplified-to-traditional OpenCC configs needed by Moran simplified packages' {
    foreach ($path in @($WorkflowPath, $PackageRequestWorkflowPath)) {
      $content = Get-Content -LiteralPath $path -Raw

      $content | Should -Match 'weasel/output/data/opencc/STCharacters\.ocd2'
      $content | Should -Match 'weasel/output/data/opencc/STPhrases\.ocd2'
      $content | Should -Match 'weasel/output/data/opencc/s2t\.json'
    }
  }

  It 'uses a dedicated script to sync only cacheable librime outputs' {
    Test-Path -LiteralPath $SaveLibrimeCachePath | Should -BeTrue
    $content = Get-Content -LiteralPath $SaveLibrimeCachePath -Raw

    $content | Should -Match 'Copy-LibrimeCacheOutputs'
    $content | Should -Match '\.pack-work\\weasel'
    $content | Should -Match '\.\\weasel'
  }

  It 'validates cached or built rime.dll files when custom-data needs lua' {
    $content = Get-Content -LiteralPath $PackPath -Raw

    $content | Should -Match 'LibrimeValidation\.psm1'
    $content | Should -Match 'Assert-PackLibrimeLuaSupport'
    $content.IndexOf('Assert-PackLibrimeLuaSupport', [StringComparison]::Ordinal) |
      Should -BeGreaterThan $content.IndexOf('librime preparation incomplete', [StringComparison]::Ordinal)
  }

  It 'installs librime-lua before building librime when custom-data needs lua' {
    $content = Get-Content -LiteralPath $PackPath -Raw

    $content | Should -Match 'Install-PackLibrimeLuaPlugin .* -Force'
    $content | Should -Match 'Install-PackLibrimeLuaPlugin .* -LibrimeLuaRef \$env:PACK_LIBRIME_LUA_REF'
    $content | Should -Match 'Install-PackLibrimeLuaPlugin .* -LibrimeLuaThirdpartyRef \$env:PACK_LIBRIME_LUA_THIRDPARTY_REF'
    $content | Should -Match 'Assert-PackLibrimeLuaSupport .* -Force'
    $content.IndexOf('Install-PackLibrimeLuaPlugin', [StringComparison]::Ordinal) |
      Should -BeGreaterThan $content.IndexOf('$missingLibrime = Get-MissingLibrimeFiles $WeaselRepo', [StringComparison]::Ordinal)
    $content.IndexOf('Install-PackLibrimeLuaPlugin', [StringComparison]::Ordinal) |
      Should -BeLessThan $content.IndexOf('call build.bat librime', [StringComparison]::Ordinal)
  }

  It 'treats missing OpenCC tools as incomplete librime preparation' {
    $content = Get-Content -LiteralPath $PackPath -Raw

    $content | Should -Match '(?s)function Get-MissingLibrimeFiles.*foreach \(\$tool in @\(''opencc\.exe'', ''opencc_dict\.exe'', ''opencc_phrase_extract\.exe''\)'
    $content | Should -Match '(?s)function Get-MissingLibrimeFiles.*Resolve-PackLibrimeToolPath.*librime\\bin\\\$tool'
    $content | Should -Match 'Sync-PackLibrimeOpenCcTools'
  }

  It 'passes GitHub token to pack.ps1 for authenticated librime release fallback' {
    $buildContent = Get-Content -LiteralPath $WorkflowPath -Raw
    $requestContent = Get-Content -LiteralPath $PackageRequestWorkflowPath -Raw

    foreach ($content in @($buildContent, $requestContent)) {
      $content | Should -Match '(?s)name:\s*Run pack\.ps1\s+shell:\s*pwsh\s+env:\s+GH_TOKEN:\s*\$\{\{ github\.token \}\}\s+run:\s*\./pack\.ps1'
    }
  }
}

Describe 'build workflow Windows toolchain' {
  It 'pins the build job to Windows Server 2022 for VS 2022 and Boost vc143 compatibility' {
    $content = Get-Content -LiteralPath $WorkflowPath -Raw

    $content | Should -Match '(?s)build:\s+needs: plan.*?runs-on:\s*windows-2022'
  }
}

Describe 'build workflow release notes' {
  It 'uploads one manifest per installer and renders release notes from manifests' {
    $content = Get-Content -LiteralPath $WorkflowPath -Raw

    $restorePrevious = $content.IndexOf('name: Restore previous release assets', [StringComparison]::Ordinal)
    $downloadInstallers = $content.IndexOf('name: Download current installer artifacts', [StringComparison]::Ordinal)
    $downloadManifests = $content.IndexOf('name: Download current installer manifests', [StringComparison]::Ordinal)
    $mergeAssets = $content.IndexOf('name: Merge release assets', [StringComparison]::Ordinal)
    $rename = $content.IndexOf('name: Rename installer', [StringComparison]::Ordinal)
    $manifest = $content.IndexOf('name: Write installer manifest', [StringComparison]::Ordinal)
    $uploadManifest = $content.IndexOf('name: Upload installer manifest', [StringComparison]::Ordinal)
    $writeNotes = $content.IndexOf('name: Write release notes', [StringComparison]::Ordinal)
    $release = $content.IndexOf('name: Release', [StringComparison]::Ordinal)

    $manifest | Should -BeGreaterThan $rename
    $uploadManifest | Should -BeGreaterThan $manifest
    $restorePrevious | Should -BeGreaterOrEqual 0
    $downloadInstallers | Should -BeGreaterThan $restorePrevious
    $downloadManifests | Should -BeGreaterThan $downloadInstallers
    $mergeAssets | Should -BeGreaterThan $downloadManifests
    $writeNotes | Should -BeGreaterThan $mergeAssets
    $release | Should -BeGreaterThan $writeNotes
    $content | Should -Match 'body_path:\s*out/release-notes\.md'
    $content | Should -Match "-ReleaseTag '\$\{\{ needs\.plan\.outputs\.tag \}\}'"
    $content | Should -Match "-Repository '\$\{\{ github\.repository \}\}'"
    $content | Should -Match 'files:\s*\|\s*out/packages/\*\.exe\s*out/release-manifests\.zip'
    $content | Should -Match 'GH_TOKEN:\s*\$\{\{ github\.token \}\}'
  }

  It 'restores previous assets only from a complete release baseline' {
    Test-Path -LiteralPath $RestorePreviousReleaseAssetsPath | Should -BeTrue
    $content = Get-Content -LiteralPath $RestorePreviousReleaseAssetsPath -Raw

    $content | Should -Match 'expectedInstallerCount'
    $content | Should -Match "release-manifests\.zip"
    $content | Should -Match 'Skipping incomplete previous release'
    $content | Should -Match 'installerCount -ge \$expectedInstallerCount'
  }

  It 'downloads previous release installers one by one and validates file sizes' {
    $content = Get-Content -LiteralPath $RestorePreviousReleaseAssetsPath -Raw

    $content | Should -Match 'Download-ReleaseAsset'
    $content | Should -Match 'application/octet-stream'
    $content | Should -Match 'Size mismatch'
    $content | Should -Not -Match "gh release download \$tag --repo \$Repository --pattern '\\*\.exe'"
  }

  It 'records display names and commit times in installer manifests' {
    $content = Get-Content -LiteralPath $WorkflowPath -Raw

    $content | Should -Match 'data_commit_time='
    $content | Should -Match 'weasel_commit_time='
    $content | Should -Match "-DataDisplay '\$\{\{ matrix\.data_display \}\}'"
    $content | Should -Match "-DataCommitTime '\$\{\{ steps\.data-rev\.outputs\.data_commit_time \}\}'"
    $content | Should -Match "-WeaselDisplay '\$\{\{ matrix\.weasel_display \}\}'"
    $content | Should -Match "-WeaselCommitTime '\$\{\{ steps\.weasel-rev\.outputs\.weasel_commit_time \}\}'"
  }

  It 'uses dedicated scripts for installer manifests and release notes' {
    Test-Path -LiteralPath $MergeReleaseAssetsPath | Should -BeTrue
    Test-Path -LiteralPath $RestorePreviousReleaseAssetsPath | Should -BeTrue
    Test-Path -LiteralPath $WriteInstallerManifestPath | Should -BeTrue
    Test-Path -LiteralPath $WriteReleaseNotesPath | Should -BeTrue
  }
}

Describe 'build workflow data checkout' {
  It 'enables symlink checkout for data repositories on Windows' {
    $content = Get-Content -LiteralPath $WorkflowPath -Raw

    $content | Should -Match 'git -c core\.symlinks=true clone --depth 1 -b \$\{\{ matrix\.data_ref \}\} \$\{\{ matrix\.data_url \}\} custom-data'
  }
}

Describe 'pack script Boost preparation' {
  It 'builds Boost libraries with target-matching Visual Studio prompts' {
    $content = Get-Content -LiteralPath $PackPath -Raw

    $content | Should -Match 'Get-BoostBuildArchitectures'
    $content | Should -Match 'Get-BoostBjamOptions'
    $content | Should -Not -Match '(?s)\$boostVsDevCmdCall\s*=\s*New-VsDevCmdCall.*?-Architecture x86\s*`.*?-HostArchitecture x86'
  }

  It 'keeps librime release downloads in a stable cache outside the mirrored work tree' {
    $content = Get-Content -LiteralPath $PackPath -Raw
    $stableCachePattern = [regex]::Escape(".pack-rime-cache\downloads")

    $content | Should -Match $stableCachePattern
    $content | Should -Match '\$asset\.size'
    $content | Should -Match 'incomplete librime asset'
  }

  It 'preserves each upstream WeaselServer shutdown command before taskkill fallback' {
    $content = Get-Content -LiteralPath $PackPath -Raw

    $content | Should -Match '!macro PACK_PS1_STOP_WEASEL_SERVER SERVER_EXE SERVER_COMMAND'
    $content | Should -Match 'Exec ''''"\$\{SERVER_EXE\}" \$\{SERVER_COMMAND\}'''''
    $content | Should -Match 'taskkill /IM WeaselServer\.exe /F /T'
    $content | Should -Not -Match 'Exec ''''\$\{SERVER_EXE\}'''' /stop'
  }

  It 'clears stale Weasel manual-exit state after installer-driven shutdown' {
    $content = Get-Content -LiteralPath $PackPath -Raw

    $content | Should -Match ([regex]::Escape('Delete "$TEMP\rime.weasel\weasel-service-manual-exit.flag"'))
  }

  It 'refreshes text services after new TSF registration before deploying user data' {
    $content = Get-Content -LiteralPath $PackPath -Raw

    $content | Should -Match 'Add-PackNsiPostInstallTextServicesRefreshPatch'
    $content | Should -Match 'Add-PackNsiUnregisterTextServicesRefreshPatch'
    $content | Should -Match ([regex]::Escape('$sawPostInstallWeaselSetup = $true'))
    $content | Should -Match ([regex]::Escape('$line.Trim() -eq ''!insertmacro PACK_PS1_REFRESH_TEXT_SERVICES'''))
  }
}
