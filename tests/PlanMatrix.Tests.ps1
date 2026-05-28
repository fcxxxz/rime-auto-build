BeforeAll {
  $ScriptPath = Join-Path $PSScriptRoot '..\scripts\plan-matrix.ps1'
  $BuildsPath = Join-Path $PSScriptRoot 'fixtures\builds.yaml'

  function Invoke-PlanMatrix {
    param(
      [string]$EventName,
      [string]$Payload = '',
      [string]$OnlyData = '',
      [string]$OnlyWeasel = '',
      [string]$NowUtc = ''
    )
    $outFile = New-TemporaryFile
    $env:GITHUB_OUTPUT      = $outFile.FullName
    $env:BUILDS_YAML_PATH   = $BuildsPath
    $env:EVENT_NAME         = $EventName
    $env:DISPATCH_PAYLOAD   = $Payload
    $env:INPUT_ONLY_DATA    = $OnlyData
    $env:INPUT_ONLY_WEASEL  = $OnlyWeasel
    $env:PLAN_NOW_UTC       = $NowUtc
    & pwsh -NoProfile -File $ScriptPath
    if ($LASTEXITCODE -ne 0) { throw "plan-matrix.ps1 exited $LASTEXITCODE" }
    $content = Get-Content $outFile.FullName -Raw
    Remove-Item $outFile.FullName -Force
    $include = ($content -split "`n" | Where-Object { $_ -like 'include=*' }) -replace '^include=',''
    $tag     = ($content -split "`n" | Where-Object { $_ -like 'tag=*' })     -replace '^tag=',''
    return [pscustomobject]@{
      include = $include | ConvertFrom-Json
      tag     = $tag.Trim()
    }
  }
}

Describe 'plan-matrix.ps1' {
  Context 'push event (full build)' {
    It 'returns full matrix minus excludes' {
      $r = Invoke-PlanMatrix -EventName 'push'
      $r.include.Count | Should -Be 3
    }
    It 'tag has -config suffix' {
      $r = Invoke-PlanMatrix -EventName 'push'
      $r.tag | Should -Match '^build-\d{8}-\d{4}-config$'
    }
    It 'uses Beijing time in generated tags' {
      $r = Invoke-PlanMatrix -EventName 'push' -NowUtc '2026-05-28T08:34:00Z'
      $r.tag | Should -Be 'build-20260528-1634-config'
    }
  }

  Context 'workflow_dispatch with no filter' {
    It 'full matrix, tag has -manual suffix' {
      $r = Invoke-PlanMatrix -EventName 'workflow_dispatch'
      $r.include.Count | Should -Be 3
      $r.tag | Should -Match '^build-\d{8}-\d{4}-manual$'
    }
  }

  Context 'workflow_dispatch with only_data filter' {
    It 'filters by data name' {
      $r = Invoke-PlanMatrix -EventName 'workflow_dispatch' -OnlyData 'tiger'
      $r.include.Count | Should -Be 2
      $r.include | ForEach-Object { $_.data_name | Should -Be 'tiger' }
    }
  }

  Context 'workflow_dispatch with both filters' {
    It 'filters by data and weasel' {
      $r = Invoke-PlanMatrix -EventName 'workflow_dispatch' -OnlyData 'tiger' -OnlyWeasel 'mine'
      $r.include.Count | Should -Be 1
      $r.include[0].data_name   | Should -Be 'tiger'
      $r.include[0].weasel_name | Should -Be 'mine'
    }
  }

  Context 'repository_dispatch with changed_targets' {
    It 'only weasels changed -> filters to those weasels x all datas' {
      $payload = '{"changed_targets": {"weasels": ["mine"], "datas": []}}'
      $r = Invoke-PlanMatrix -EventName 'repository_dispatch' -Payload $payload
      $r.include.Count | Should -Be 2
      $r.include | ForEach-Object { $_.weasel_name | Should -Be 'mine' }
      $r.tag | Should -Match '^build-\d{8}-\d{4}$'
    }
    It 'only datas changed -> all weasels x those datas' {
      $payload = '{"changed_targets": {"weasels": [], "datas": ["tiger"]}}'
      $r = Invoke-PlanMatrix -EventName 'repository_dispatch' -Payload $payload
      $r.include.Count | Should -Be 2
      $r.include | ForEach-Object { $_.data_name | Should -Be 'tiger' }
    }
    It 'both changed -> union' {
      $payload = '{"changed_targets": {"weasels": ["mine"], "datas": ["moqi"]}}'
      $r = Invoke-PlanMatrix -EventName 'repository_dispatch' -Payload $payload
      # weasel mine x all datas (2) + all weasels x moqi (1, official x moqi excluded), dedup
      # mine x tiger, mine x moqi, official x moqi(excluded). After exclude: mine-tiger, mine-moqi
      # Plus from datas side: all weasels x moqi = official x moqi(excl), mine x moqi(dup)
      # = mine-tiger, mine-moqi
      $r.include.Count | Should -Be 2
    }
  }
}
