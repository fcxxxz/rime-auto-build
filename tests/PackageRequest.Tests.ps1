BeforeAll {
  $PackageRequestModulePath = Join-Path $PSScriptRoot '..\scripts\lib\PackageRequest.psm1'
  $YamlModulePath = Join-Path $PSScriptRoot '..\scripts\lib\Yaml.psm1'
  Import-Module $PackageRequestModulePath -Force
  Import-Module $YamlModulePath -Force
}

Describe 'ConvertFrom-PackageRequestIssueBody' {
  It 'parses package request fields from a GitHub Issue Form body' {
    $body = @'
### Data short name

moran-test

### Display name

魔然测试

### Repository

https://github.com/rimeinn/rime-moran

### Ref

main

### Weasel

rime

### Confirmation

- [X] I confirm this is a public Rime data repository.
'@

    $request = ConvertFrom-PackageRequestIssueBody -Body $body

    $request.data_name | Should -Be 'moran-test'
    $request.data_display | Should -Be '魔然测试'
    $request.data_url | Should -Be 'https://github.com/rimeinn/rime-moran.git'
    $request.data_ref | Should -Be 'main'
    $request.weasel_name | Should -Be 'rime'
  }

  It 'leaves ref blank when the field is blank so the workflow can use the repository default branch' {
    $body = @'
### Data short name

sample

### Display name

Sample

### Repository

https://github.com/example/rime-sample.git

### Ref


### Weasel

qing
'@

    $request = ConvertFrom-PackageRequestIssueBody -Body $body

    $request.data_ref | Should -Be ''
  }

  It 'parses the simplified Chinese issue form and derives names from the repository' {
    $body = @'
### 公开 GitHub 仓库

https://github.com/a810439322/rime-tiger

### 分支、标签或 commit

_No response_

### 小狼毫版本

晴版小狼毫（qing）

### 确认

- [X] 我确认这是公开 Rime 方案仓库，并知道安装包会作为临时 GitHub Actions Artifact 上传。
'@

    $request = ConvertFrom-PackageRequestIssueBody -Body $body

    $request.data_name | Should -Be 'tiger'
    $request.data_display | Should -Be 'tiger'
    $request.data_url | Should -Be 'https://github.com/a810439322/rime-tiger.git'
    $request.data_ref | Should -Be ''
    $request.weasel_name | Should -Be 'qing'
  }

  It 'falls back to derived names when a legacy issue used an invalid short name' {
    $body = @'
### Data short name

1

### Display name

1

### Repository

https://github.com/a810439322/rime-tiger

### Ref

_No response_

### Weasel

qing
'@

    $request = ConvertFrom-PackageRequestIssueBody -Body $body

    $request.data_name | Should -Be 'tiger'
    $request.data_display | Should -Be 'tiger'
    $request.data_ref | Should -Be ''
  }

  It 'throws when a required field is missing' {
    $body = @'
### Data short name

sample
'@

    { ConvertFrom-PackageRequestIssueBody -Body $body } |
      Should -Throw -ExpectedMessage '*missing required issue field*Repository*'
  }
}

Describe 'Normalize-PackageRequestGitHubUrl' {
  It 'normalizes public GitHub HTTPS repository URLs to git URLs' {
    Resolve-PackageRequestGitHubUrl 'https://github.com/User-Name/repo.name' |
      Should -Be 'https://github.com/User-Name/repo.name.git'
    Resolve-PackageRequestGitHubUrl 'https://github.com/User-Name/repo.name.git' |
      Should -Be 'https://github.com/User-Name/repo.name.git'
  }

  It 'rejects non-GitHub, SSH, ownerless, or path-like URLs' {
    { Resolve-PackageRequestGitHubUrl 'https://gitlab.com/user/repo' } |
      Should -Throw -ExpectedMessage '*only public GitHub HTTPS repositories are supported*'
    { Resolve-PackageRequestGitHubUrl 'git@github.com:user/repo.git' } |
      Should -Throw -ExpectedMessage '*only public GitHub HTTPS repositories are supported*'
    { Resolve-PackageRequestGitHubUrl 'https://github.com/user' } |
      Should -Throw -ExpectedMessage '*only public GitHub HTTPS repositories are supported*'
    { Resolve-PackageRequestGitHubUrl 'https://github.com/user/repo/tree/main' } |
      Should -Throw -ExpectedMessage '*only public GitHub HTTPS repositories are supported*'
  }
}

Describe 'Assert-PackageRequest' {
  BeforeEach {
    $BuildsPath = Join-Path $TestDrive 'builds.yaml'
    @'
weasels:
  - { name: rime, display: 官方小狼毫, url: https://github.com/rime/weasel.git, ref: master }
  - { name: qing, display: 晴版小狼毫, url: https://github.com/a810439322/weasel.git, ref: master }
datas:
  - { name: tiger, display: 虎码, url: https://github.com/a810439322/rime-tiger.git, ref: main }
excludes: []
'@ | Set-Content -LiteralPath $BuildsPath
    $script:Config = Read-BuildsYaml -Path $BuildsPath
  }

  It 'returns a single sanitized build matrix item for a valid request' {
    $request = [pscustomobject]@{
      data_name = 'sample-data'
      data_display = '示例方案'
      data_url = 'https://github.com/example/rime-sample.git'
      data_ref = 'main'
      weasel_name = 'qing'
    }

    $validated = Resolve-PackageRequest -Request $request -Config $Config

    $validated.data_name | Should -Be 'sample-data'
    $validated.data_display | Should -Be '示例方案'
    $validated.data_url | Should -Be 'https://github.com/example/rime-sample.git'
    $validated.data_ref | Should -Be 'main'
    $validated.github_owner | Should -Be 'example'
    $validated.github_repo | Should -Be 'rime-sample'
    $validated.weasel_name | Should -Be 'qing'
    $validated.weasel_display | Should -Be '晴版小狼毫'
    $validated.weasel_url | Should -Be 'https://github.com/a810439322/weasel.git'
    $validated.weasel_ref | Should -Be 'master'
  }

  It 'rejects invalid data names' {
    $request = [pscustomobject]@{
      data_name = 'Bad_Name'
      data_display = 'Bad'
      data_url = 'https://github.com/example/bad.git'
      data_ref = 'main'
      weasel_name = 'rime'
    }

    { Resolve-PackageRequest -Request $request -Config $Config } |
      Should -Throw -ExpectedMessage '*data_name must match*'
  }

  It 'rejects unsafe display names and refs' {
    $base = @{
      data_name = 'sample'
      data_url = 'https://github.com/example/sample.git'
      weasel_name = 'rime'
    }

    { Resolve-PackageRequest -Request ([pscustomobject]($base + @{ data_display = "bad`nname"; data_ref = 'main' })) -Config $Config } |
      Should -Throw -ExpectedMessage '*data_display must be a single line*'
    { Resolve-PackageRequest -Request ([pscustomobject]($base + @{ data_display = 'Sample'; data_ref = "bad ref'" })) -Config $Config } |
      Should -Throw -ExpectedMessage '*data_ref contains unsupported characters*'
    { Resolve-PackageRequest -Request ([pscustomobject]($base + @{ data_display = 'Sample'; data_ref = '../main' })) -Config $Config } |
      Should -Throw -ExpectedMessage '*data_ref contains unsupported characters*'
    { Resolve-PackageRequest -Request ([pscustomobject]($base + @{ data_display = 'Sample'; data_ref = '--tags' })) -Config $Config } |
      Should -Throw -ExpectedMessage '*data_ref contains unsupported characters*'
    { Resolve-PackageRequest -Request ([pscustomobject]($base + @{ data_display = 'Sample'; data_ref = '-cfoo.bar=baz' })) -Config $Config } |
      Should -Throw -ExpectedMessage '*data_ref contains unsupported characters*'
    { Resolve-PackageRequest -Request ([pscustomobject]($base + @{ data_display = 'Sample'; data_ref = 'abc1234' })) -Config $Config } |
      Should -Throw -ExpectedMessage '*commit refs must be full 40-character SHA values*'
  }

  It 'accepts branch, tag-like, and full SHA refs' {
    $base = @{
      data_name = 'sample'
      data_display = 'Sample'
      data_url = 'https://github.com/example/sample.git'
      weasel_name = 'rime'
    }

    (Resolve-PackageRequest -Request ([pscustomobject]($base + @{ data_ref = 'feature/test-branch' })) -Config $Config).data_ref |
      Should -Be 'feature/test-branch'
    (Resolve-PackageRequest -Request ([pscustomobject]($base + @{ data_ref = 'v1.2.3' })) -Config $Config).data_ref |
      Should -Be 'v1.2.3'
    (Resolve-PackageRequest -Request ([pscustomobject]($base + @{ data_ref = '0123456789abcdef0123456789abcdef01234567' })) -Config $Config).data_ref |
      Should -Be '0123456789abcdef0123456789abcdef01234567'
  }

  It 'allows configured data names for one-off package requests' {
    $request = [pscustomobject]@{
      data_name = 'tiger'
      data_display = '虎码'
      data_url = 'https://github.com/other/rime-tiger.git'
      data_ref = 'main'
      weasel_name = 'rime'
    }

    { Resolve-PackageRequest -Request $request -Config $Config } |
      Should -Not -Throw
  }

  It 'rejects unknown or multi-selected weasel values' {
    $base = @{
      data_name = 'sample'
      data_display = 'Sample'
      data_url = 'https://github.com/example/sample.git'
      data_ref = 'main'
    }

    { Resolve-PackageRequest -Request ([pscustomobject]($base + @{ weasel_name = 'unknown' })) -Config $Config } |
      Should -Throw -ExpectedMessage '*unknown weasel*'
    { Resolve-PackageRequest -Request ([pscustomobject]($base + @{ weasel_name = 'rime, qing' })) -Config $Config } |
      Should -Throw -ExpectedMessage '*select exactly one weasel*'
  }

  It 'does not infer a weasel from mixed free-form text' {
    $body = @'
### 公开 GitHub 仓库

https://github.com/example/rime-sample

### 小狼毫版本

rime qing
'@

    $request = ConvertFrom-PackageRequestIssueBody -Body $body

    $request.weasel_name | Should -Be 'rime qing'
  }
}

Describe 'Test-PackageRequestRimeDataShape' {
  It 'accepts repositories with schema files or default.custom.yaml' {
    $schemaRoot = Join-Path $TestDrive 'schema-root'
    New-Item -ItemType Directory -Path $schemaRoot | Out-Null
    Set-Content -LiteralPath (Join-Path $schemaRoot 'sample.schema.yaml') -Value 'schema:'

    Test-PackageRequestRimeDataShape -Path $schemaRoot | Should -BeTrue

    $defaultRoot = Join-Path $TestDrive 'default-root'
    New-Item -ItemType Directory -Path $defaultRoot | Out-Null
    Set-Content -LiteralPath (Join-Path $defaultRoot 'default.custom.yaml') -Value 'patch:'

    Test-PackageRequestRimeDataShape -Path $defaultRoot | Should -BeTrue
  }

  It 'rejects repositories without visible Rime data files' {
    $root = Join-Path $TestDrive 'plain-root'
    New-Item -ItemType Directory -Path $root | Out-Null
    Set-Content -LiteralPath (Join-Path $root 'README.md') -Value '# readme'

    Test-PackageRequestRimeDataShape -Path $root | Should -BeFalse
  }

  It 'rejects repositories with only nested fixture schema files' {
    $root = Join-Path $TestDrive 'nested-only'
    $nested = Join-Path $root 'docs'
    New-Item -ItemType Directory -Path $nested | Out-Null
    Set-Content -LiteralPath (Join-Path $nested 'example.schema.yaml') -Value 'schema:'

    Test-PackageRequestRimeDataShape -Path $root | Should -BeFalse
  }
}

Describe 'package request scripts' {
  It 'prepare-package-request.ps1 emits normalized request JSON and GitHub outputs' {
    $buildsPath = Join-Path $TestDrive 'builds.yaml'
    $bodyPath = Join-Path $TestDrive 'issue-body.md'
    $outputPath = Join-Path $TestDrive 'github-output.txt'
    @'
weasels:
  - { name: rime, display: 官方小狼毫, url: https://github.com/rime/weasel.git, ref: master }
datas:
  - { name: tiger, display: 虎码, url: https://github.com/a810439322/rime-tiger.git, ref: main }
excludes: []
'@ | Set-Content -LiteralPath $buildsPath
    @'
### Data short name

sample

### Display name

示例

### Repository

https://github.com/example/sample

### Ref

main

### Weasel

rime
'@ | Set-Content -LiteralPath $bodyPath

    $oldOutput = $env:GITHUB_OUTPUT
    try {
      $env:GITHUB_OUTPUT = $outputPath
      & (Join-Path $PSScriptRoot '..\scripts\prepare-package-request.ps1') `
        -IssueBodyPath $bodyPath `
        -BuildsPath $buildsPath
    } finally {
      $env:GITHUB_OUTPUT = $oldOutput
    }

    $outputs = Get-Content -LiteralPath $outputPath -Raw
    $outputs | Should -Match 'valid=true'
    $outputs | Should -Match 'data_name=sample'
    $outputs | Should -Match 'github_owner=example'
    $outputs | Should -Match 'github_repo=sample'
    $outputs | Should -Match 'weasel_name=rime'
    $outputs | Should -Match 'request_json<<'
    $outputs | Should -Match '"data_url":"https://github.com/example/sample.git"'
  }

  It 'check-rime-data-shape.ps1 writes valid=false before failing on non-Rime data' {
    $root = Join-Path $TestDrive 'not-rime'
    $outputPath = Join-Path $TestDrive 'shape-output.txt'
    New-Item -ItemType Directory -Path $root | Out-Null
    Set-Content -LiteralPath (Join-Path $root 'README.md') -Value '# readme'

    $oldOutput = $env:GITHUB_OUTPUT
    try {
      $env:GITHUB_OUTPUT = $outputPath
      { & (Join-Path $PSScriptRoot '..\scripts\check-rime-data-shape.ps1') -Path $root } |
        Should -Throw -ExpectedMessage '*does not look like a Rime data repository*'
    } finally {
      $env:GITHUB_OUTPUT = $oldOutput
    }

    Get-Content -LiteralPath $outputPath -Raw | Should -Match 'valid=false'
  }

  It 'validate-package-ref.ps1 rejects option-like or shell-like refs' {
    { & (Join-Path $PSScriptRoot '..\scripts\validate-package-ref.ps1') -Ref '--upload-pack=bad' } |
      Should -Throw -ExpectedMessage '*data_ref contains unsupported characters*'
    { & (Join-Path $PSScriptRoot '..\scripts\validate-package-ref.ps1') -Ref 'main$(whoami)' } |
      Should -Throw -ExpectedMessage '*data_ref contains unsupported characters*'
  }
}
