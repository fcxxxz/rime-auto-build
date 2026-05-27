# rime-auto-build 设计文档

日期：2026-05-27
范围：Windows 平台 Weasel 安装包自动化构建（不含 macOS / Linux）

## 1. 目标

把当前 `E:\nas同步\打字\自定义小狼毫打包\` 这套手工打包流程搬到 GitHub Actions：

- 维护一个 public GitHub 仓 `rime-auto-build`，只装打包脚本和 CI，不含源码、配置、Boost、产物。
- weasel 源码 / custom-data 配置在 CI 时从多个外部 GitHub 仓 clone 进来。
- 笛卡尔积：每个 data 仓库 × 每个 weasel 仓库 = 一个独立 `.exe` 安装包。
- 触发条件：上游有 SHA 变化才构建（无 daily cron）；也支持手动触发和改 builds.yaml 时自动构建。
- 产物发布到 GitHub Releases。

## 2. 非目标

- 不打 macOS（Squirrel）/ Linux（ibus-rime, fcitx5-rime）/ 安卓（Trime）包。
- 不打 Win32 / arm64，仅 x64。
- 不做 daily cron（已确认上游不变就不构建）。
- 不在 CI 里改 weasel 源码或 data 仓库内容；只 clone-then-build。
- 不签名 `.exe`，不做 SmartScreen 申诉，第一次运行用户会看到未签名警告（可接受，与当前本地打出的包一致）。

## 3. 仓库与本地路径

- 本地：`E:\nas同步\项目代码\SynologyDrive\rime-auto-build\`
- 远程：GitHub public 仓 `<user>/rime-auto-build`

必须 public：private 仓的 Windows runner 在免费额度里按 2× 倍率扣分钟，按 6 个 job × ~20 min × 多次触发会迅速耗尽 2000 min/月；public 仓 unlimited。

## 4. 仓库结构

```
rime-auto-build/
├── .github/
│   └── workflows/
│       ├── watch.yml          # 每小时探活 + 触发 build
│       └── build.yml          # 矩阵构建 + 发 Release
├── pack.ps1                   # 从当前项目复制，零改动
├── pack.bat                   # 从当前项目复制，零改动
├── custom-weasel-installer.md # 复制，作为构建说明
├── builds.yaml                # 中央配置：weasel 列表 + data 列表
├── state/
│   └── last-seen.json         # watcher 维护，提交回仓
├── scripts/
│   ├── probe-upstream.ps1     # watch.yml 用：git ls-remote 各仓库
│   ├── diff-state.ps1         # watch.yml 用：算 changed_targets
│   └── plan-matrix.ps1        # build.yml 用：生成 matrix include JSON
├── .gitignore
└── README.md
```

`scripts/*.ps1` 单独拆出来，让 workflow yaml 保持薄；本地也能直接跑这几个脚本调试。

## 5. .gitignore

```gitignore
# CI 时才克隆/下载的输入
/weasel/
/custom-data/
/librime/
/plum/
/boost_*/

# 旧打包文件夹里的测试目录如果不需要也排除
/Tests/

# 打包产物与中间物
/.pack-work/
/output/
weasel-*-installer.exe
pack.log

# 编辑器 / OS
.vscode/
.idea/
*.swp
.DS_Store
Thumbs.db
```

注：当前本地项目根目录还有 `Rime-虎码覆盖直装0.17.4.1晴优化版.exe`、`虎码覆盖直装0.17.4.1晴优化版.exe` 这种历史产物，迁仓时不带过去即可。

## 6. builds.yaml

```yaml
# rime-auto-build/builds.yaml
# 每次改动此文件 push 都会触发一次全量构建

weasels:
  - name: official              # 用于产物文件名与 tag，不能重名
    url: https://github.com/rime/weasel.git
    ref: master                 # 跟踪的分支或 tag
  - name: mine
    url: https://github.com/<user>/weasel.git
    ref: main

datas:
  - name: tiger
    url: https://github.com/<user>/rime-tiger.git
    ref: main
  # 之后再加：
  # - name: moqi
  #   url: ...
  #   ref: main

# 可选：从笛卡尔积里剔除部分组合
# excludes:
#   - data: tiger
#     weasel: official
```

**笛卡尔积**：`matrix = datas × weasels`。3 data × 2 weasel = 6 job。

**产物命名**：`weasel-{data}-{weasel}-{version}-installer.exe`，例 `weasel-tiger-mine-0.17.4-installer.exe`。其中 `{version}` 取 weasel 源码里 `weasel.iss` 或同等位置的版本号（沿用 `pack.ps1` 现有产物名规则）。

## 7. 触发模型

| 触发源 | 用途 | Release tag |
|---|---|---|
| `schedule` cron 每小时 | watcher 探活，**SHA 未变则早退**，不进 Windows runner | — |
| `repository_dispatch (upstream-change)` | watcher 探到变化后触发 build | `build-YYYYMMDD-HHMM` |
| `workflow_dispatch` | 仓库页手工 Run workflow，可填只构建某个 data/weasel | `build-YYYYMMDD-HHMM-manual` |
| `push paths: [builds.yaml]` | 改了配置立刻全量构建 | `build-YYYYMMDD-HHMM-config` |

时间用 UTC，避免本地时区漂移；tag 内嵌的时分秒便于排序。

## 8. watch.yml（Linux，每小时）

职责：对 builds.yaml 列出的所有 weasel + data 仓库跑 `git ls-remote`，与 `state/last-seen.json` 对比，有变化就 commit 新 state 并触发 build。

骨架：

```yaml
name: watch-upstream
on:
  schedule:
    - cron: '17 * * * *'
  workflow_dispatch:

permissions:
  contents: write
  actions: write

jobs:
  check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - id: probe
        shell: pwsh
        run: ./scripts/probe-upstream.ps1
      - id: diff
        shell: pwsh
        run: ./scripts/diff-state.ps1
      - name: 写回 state 并提交
        if: steps.diff.outputs.changed == 'true'
        run: |
          git config user.name  "rime-auto-build-bot"
          git config user.email "bot@users.noreply.github.com"
          git add state/last-seen.json
          git commit -m "watch: ${{ steps.diff.outputs.summary }}"
          git push
      - name: 触发 build
        if: steps.diff.outputs.changed == 'true'
        uses: peter-evans/repository-dispatch@v3
        with:
          event-type: upstream-change
          client-payload: |
            { "changed_targets": ${{ steps.diff.outputs.changed_targets }} }
```

`state/last-seen.json` 结构：

```json
{
  "weasels": {
    "official": { "url": "...", "ref": "master", "sha": "abc123...", "checked_at": "2026-05-27T03:17:00Z" },
    "mine":     { "url": "...", "ref": "main",   "sha": "def456...", "checked_at": "..." }
  },
  "datas": {
    "tiger": { "url": "...", "ref": "main", "sha": "789abc...", "checked_at": "..." }
  }
}
```

**部分构建逻辑**：`changed_targets` 形如 `{ "weasels": ["mine"], "datas": [] }`。`build.yml` 的 plan 阶段据此过滤 matrix：

- weasel `mine` 变了 → 跑 `datas × [mine]`
- data `tiger` 变了 → 跑 `[tiger] × weasels`
- 两者都变 → 各自集合的并集

避免一次小改动重跑全部 6 个 job。

## 9. build.yml（Windows 矩阵）

```yaml
name: build
on:
  repository_dispatch:
    types: [upstream-change]
  workflow_dispatch:
    inputs:
      only_data:   { description: '只构建该 data（留空=全部）', required: false }
      only_weasel: { description: '只构建该 weasel（留空=全部）', required: false }
  push:
    paths: ['builds.yaml']

permissions:
  contents: write

jobs:
  plan:
    runs-on: ubuntu-latest
    outputs:
      include: ${{ steps.gen.outputs.include }}
      tag:     ${{ steps.gen.outputs.tag }}
    steps:
      - uses: actions/checkout@v4
      - id: gen
        shell: pwsh
        run: ./scripts/plan-matrix.ps1
        env:
          EVENT_NAME:      ${{ github.event_name }}
          DISPATCH_PAYLOAD: ${{ toJSON(github.event.client_payload) }}
          INPUT_ONLY_DATA:   ${{ inputs.only_data }}
          INPUT_ONLY_WEASEL: ${{ inputs.only_weasel }}

  build:
    needs: plan
    runs-on: windows-latest
    strategy:
      fail-fast: false
      matrix:
        include: ${{ fromJSON(needs.plan.outputs.include) }}
    steps:
      - uses: actions/checkout@v4
      - name: Clone weasel（含子模块）
        run: git clone --recursive --depth 1 -b ${{ matrix.weasel_ref }} ${{ matrix.weasel_url }} weasel
      - name: Clone data → custom-data
        run: git clone --depth 1 -b ${{ matrix.data_ref }} ${{ matrix.data_url }} custom-data
      - name: 缓存 Boost
        id: boost-cache
        uses: actions/cache@v4
        with:
          path: boost_1_84_0
          key: boost-1.84.0-source-only
      - name: 下载 Boost（缓存未命中）
        if: steps.boost-cache.outputs.cache-hit != 'true'
        shell: pwsh
        run: ./scripts/fetch-boost.ps1
      - name: 安装 NSIS
        run: choco install nsis -y
      - name: 跑 pack.ps1
        shell: pwsh
        run: ./pack.ps1
      - name: 重命名 exe
        shell: pwsh
        run: |
          $f = Get-ChildItem weasel-*-installer.exe | Select-Object -First 1
          $new = "weasel-${{ matrix.data_name }}-${{ matrix.weasel_name }}-installer.exe"
          Rename-Item $f.FullName $new
      - uses: actions/upload-artifact@v4
        with:
          name: ${{ matrix.data_name }}-${{ matrix.weasel_name }}
          path: weasel-*-installer.exe

  release:
    needs: [plan, build]
    runs-on: ubuntu-latest
    permissions:
      contents: write
    steps:
      - uses: actions/download-artifact@v4
        with:
          path: out
          merge-multiple: true
      - uses: softprops/action-gh-release@v2
        with:
          tag_name: ${{ needs.plan.outputs.tag }}
          name:     ${{ needs.plan.outputs.tag }}
          files:    out/*.exe
          body: |
            自动构建。
            触发：${{ github.event_name }}
            上游 SHA 与 commit 信息见 state/last-seen.json。
```

## 10. Boost 缓存策略

- key = `boost-1.84.0-source-only`（与 Boost 版本号绑定，版本不变则永久命中）
- path = `boost_1_84_0/`
- 首次 miss：`scripts/fetch-boost.ps1` 下载 boost_1_84_0.zip（~140MB）+ 解压。后续命中节省 ~3-5 分钟。
- 不缓存 librime / b2 编译产物：依赖 weasel 子模块 SHA，缓存命中率低、收益小，先不做。后续若构建时间成瓶颈再加。

## 11. pack.ps1 改动

**零改动**。当前 `pack.ps1` 顶部的 `$BuildArch = 'x64'` 和其他相对路径常量在 CI 工作目录下表现与本地一致，CI 工作目录排布也按同样的相对结构准备（`./weasel`、`./custom-data`、`./boost_1_84_0`、`./pack.ps1`），开箱可用。

## 12. 错误处理与可观察性

- `fail-fast: false`：矩阵里某一个组合失败不影响其余；Release 仍按已成功的 artifact 发出，方便逐个排查。
- `pack.log` 由 `pack.ps1` 写在工作目录根，单 job 失败时把 `pack.log` + `.pack-work/**/*.log` 上传为 artifact，便于事后查看。具体步骤：`if: failure()` 触发 `actions/upload-artifact@v4` 上传日志包。
- watcher 失败（如 `git ls-remote` 网络抖动）不写回 state、不触发 build；下一小时自动重试。

## 13. 安全与权限

- 全部源码仓库假定 public，无需 secrets。
- `GITHUB_TOKEN` 默认权限够用（写仓 + 发 Release）。
- watcher commit 用 `peter-evans/repository-dispatch@v3` 时使用 `GITHUB_TOKEN`；不需要 PAT。
- 不签名 `.exe`，README 里写一句"首次运行点更多信息→仍要运行"提示。

## 14. 一次性 setup 步骤（用户做）

1. 在 GitHub 上新建空 public 仓 `rime-auto-build`。
2. 本地新建 `E:\nas同步\项目代码\SynologyDrive\rime-auto-build\`。
3. 由本计划生成所有文件后 `git init && push`。
4. 填 `builds.yaml` 的实际 url。
5. 仓库 Settings → Actions → 允许 Actions 写仓库（默认就是允许）。
6. 第一次手动 Run `build.yml`（不等 watcher），验证 6 个 job 都过。

## 15. 风险与开放问题

- **GitHub Actions 单次 workflow run 时长上限 6 小时**：6 个 job 并行各 ~20 min，远低于上限，安全。
- **boost_1_84_0 是当前本地路径写死的**：未来 weasel 升级要求新版本 Boost 时，要同步改 `scripts/fetch-boost.ps1` 和 `pack.ps1` 顶部常量。
- **weasel 子模块 librime/plum 在 `--recursive` 后版本由 weasel 自己锁定**，与本地 `./librime`、`./plum` fallback 路径无冲突；CI 不需要单独准备 librime/plum。
- **watcher 写仓产生大量 commit**：限制 commit message 简洁；仓库历史会有较多 `watch: ...` commit，可接受（也可后续改为存 GitHub Actions cache 而非仓内文件，但 cache 无法跨 workflow 共享，需要 artifact 中转，复杂度上升）。

## 16. 后续可扩展

- macOS / Squirrel：另起一套 `squirrel-auto-build` 或并入同仓 `squirrel.yml`，data 仓里补一份 `squirrel.custom.yaml`。
- 加 Linux ibus-rime / fcitx5-rime 包。
- exe 代码签名（需要购买证书）。
- 给 Release 加 release notes 自动汇总各上游 commit。
