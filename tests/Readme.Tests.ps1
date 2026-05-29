BeforeAll {
  $ReadmePath = Join-Path $PSScriptRoot '..\README.md'
}

Describe 'README update workflow explanation' {
  It 'starts the work mechanism section with one concise plain Chinese sentence' {
    $content = Get-Content -LiteralPath $ReadmePath -Raw
    $match = [regex]::Match($content, '(?s)## 工作机制\s+([^\r\n]+)')

    $match.Success | Should -BeTrue
    $firstLine = $match.Groups[1].Value
    $firstLine | Should -Match '^简单说：'
    $firstLine | Should -Not -Match '`[^`]+`'
  }

  It 'renders configured repository URLs as Markdown hyperlinks' {
    $content = Get-Content -LiteralPath $ReadmePath -Raw

    $content | Should -Match '\[rime/weasel\]\(https://github\.com/rime/weasel\.git\)'
    $content | Should -Match '\[a810439322/weasel\]\(https://github\.com/a810439322/weasel\.git\)'
    $content | Should -Match '\[fxliang/weasel\]\(https://github\.com/fxliang/weasel\.git\)'
    $content | Should -Match '\[a810439322/rime-tiger\]\(https://github\.com/a810439322/rime-tiger\.git\)'
    $content | Should -Match '\[rimeinn/rime-moran\]\(https://github\.com/rimeinn/rime-moran\.git\)'
    $content | Should -Not -Match '\| `https://github\.com/'
  }

  It 'documents one-off issue packaging with a direct issue template link' {
    $content = Get-Content -LiteralPath $ReadmePath -Raw

    $content | Should -Match '## 一次性打包新的方案'
    $content | Should -Match '\[提交一次性打包 Issue\]\(https://github\.com/a810439322/rime-auto-build/issues/new\?template=package-data\.yml\)'
    $content | Should -Match '只支持公开 GitHub HTTPS 仓库'
    $content | Should -Match '方案短名和显示名会自动从仓库名推导'
    $content | Should -Match '不填就用仓库默认分支'
    $content | Should -Match '一次只能选择一个小狼毫版本'
    $content | Should -Match '下载链接'
    $content | Should -Match '需要登录 GitHub'
    $content | Should -Match 'package-request-\{issue_number\}'
    $content | Should -Match 'Artifacts'
    $content | Should -Match '长期加入'
    $content | Should -Match '人工审核'
  }
}
