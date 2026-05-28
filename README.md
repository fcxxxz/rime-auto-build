# rime-auto-build

自动构建 Weasel（小狼毫）Windows x64 安装包。

每个 `data` 仓库（一套 Rime 方案 / 词库 / Lua / OpenCC）和每个 `weasel` 仓库（小狼毫源码）组合，会在 GitHub Releases 出一份 `.exe`。上游有 commit 才构建，没动就不动。

## 工作机制

- `builds.yaml`：单一配置，列 weasel 仓库和 data 仓库。
- `watch.yml`：每小时 Linux runner，对每个上游仓库跑 `git ls-remote`，对比 `state/last-seen.json`。SHA 变了就 commit 新 state、`repository_dispatch` 触发构建。
- `build.yml`：Windows runner 矩阵，`pack.ps1` 出 `weasel-{data}-{weasel}-{version}-installer.exe`，全部聚合到一个 Release。

## 安装包

到 [Releases](../../releases) 下载对应 data + weasel 的 `.exe`。第一次运行 Windows SmartScreen 可能拦截，点 **更多信息 → 仍要运行**。

文件名格式：

`weasel-{方案名}-{小狼毫版本名}-{小狼毫版本号}-installer.exe`

其中：

- `方案名` 来自 `builds.yaml` 的 `datas`，表示打进安装包的 Rime 方案、词库、Lua、OpenCC 等数据。
- `小狼毫版本名` 来自 `builds.yaml` 的 `weasels`，表示用于编译安装器的小狼毫源码仓库。
- Release 正文会列出每个 `.exe` 对应的方案仓库、方案提交、小狼毫仓库、小狼毫提交。

当前自动构建的方案仓库：

- `tiger`: `https://github.com/a810439322/rime-tiger.git` (`main`)
- `moran`: `https://github.com/rimeinn/rime-moran.git` (`main`)

当前自动构建的小狼毫仓库：

- `official`: `https://github.com/rime/weasel.git` (`master`)
- `mine`: `https://github.com/a810439322/weasel.git` (`master`)
- `fxliang`: `https://github.com/fxliang/weasel.git` (`pb`)

## 添加新的 data 或 weasel 仓库

改 `builds.yaml`，提 commit，push。push 本身会触发一次全量构建。

## 本地构建（不走 CI）

如果想在本机直接打包，看 `custom-weasel-installer.md`。需要 VS 2022 + NSIS + boost_1_84_0 等。

## 设计文档

`docs/superpowers/specs/2026-05-27-rime-auto-build-design.md`
