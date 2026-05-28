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
}
