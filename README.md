# rime-auto-build

自动构建 Weasel（小狼毫）Windows x64 安装包。

每个 `data` 仓库（一套 Rime 方案 / 词库 / Lua / OpenCC）和每个 `weasel` 仓库（小狼毫源码）组合，会在 GitHub Releases 出一份 `.exe`。上游有 commit 才构建，没动就不动。

## 工作机制

- `builds.yaml`：单一配置，列 weasel 仓库和 data 仓库。
- `watch.yml`：每小时 Linux runner，对每个上游仓库跑 `git ls-remote`，对比 `state/last-seen.json`。SHA 变了就 commit 新 state、`repository_dispatch` 触发构建。
- `build.yml`：Windows runner 矩阵，`pack.ps1` 出 `weasel-{data}-{weasel}-{version}-installer.exe`，全部聚合到一个 Release。

## 安装包

到 [Releases](../../releases) 下载对应 data + weasel 的 `.exe`。第一次运行 Windows SmartScreen 可能拦截，点 **更多信息 → 仍要运行**。

### 文件名

`weasel-{方案名}-{小狼毫版本名}-{小狼毫版本号}-installer.exe`

示例：

- `weasel-tiger-rime-0.17.4-installer.exe`：虎码 + 官方小狼毫。
- `weasel-tiger-qing-0.17.4-installer.exe`：虎码 + 晴版小狼毫。

### 方案名

| 短名 | 中文名 | 仓库 | 分支 |
| --- | --- | --- | --- |
| `tiger` | 虎码 | `https://github.com/a810439322/rime-tiger.git` | `main` |
| `moran` | 魔然 | `https://github.com/rimeinn/rime-moran.git` | `main` |
| `092wb` | 092五笔 | `https://github.com/092wb/092wb.git` | `main` |
| `lutai` | 露台码 | `https://github.com/Flauver/lutai.git` | `dev` |
| `openfly` | 小鹤音形 | `https://github.com/amorphobia/openfly.git` | `main` |
| `crane` | 凇鹤拼音 | `https://github.com/kchen0x/rime-crane.git` | `main` |
| `snow-pinyin` | 冰雪拼音 | `https://github.com/rimeinn/rime-snow-pinyin.git` | `main` |
| `jdhe` | 简单鹤 | `https://github.com/rimeinn/rime-JDhe.git` | `main` |
| `kagiroi` | 日语 | `https://github.com/rimeinn/rime-kagiroi.git` | `main` |
| `mungyeong` | 韩语 | `https://github.com/rimeinn/rime-mungyeong.git` | `main` |
| `zrlong` | 龙码双拼 | `https://github.com/rimeinn/rime-zrlong.git` | `main` |

### 小狼毫版本名

| 短名 | 说明 | 仓库 | 分支 |
| --- | --- | --- | --- |
| `rime` | 官方小狼毫 | `https://github.com/rime/weasel.git` | `master` |
| `qing` | 晴版小狼毫 | `https://github.com/a810439322/weasel.git` | `master` |
| `fxliang` | fxliang 小狼毫 | `https://github.com/fxliang/weasel.git` | `pb` |

### Release 正文怎么看

每次 Release 的 **安装包说明** 会按表格列出每个 `.exe` 的来源：

| 安装包 | 方案 | 小狼毫 |
| --- | --- | --- |
| 文件名 | 中文名、短名、分支、commit、最后提交时间、仓库 | 中文名、短名、分支、commit、最后提交时间、仓库 |

README 里只列当前配置；具体某个安装包来自哪个提交、最后提交时间是多少，以对应 Release 正文为准。

## 添加新的 data 或 weasel 仓库

改 `builds.yaml`，提 commit，push。push 本身会触发一次全量构建。

## 本地构建（不走 CI）

如果想在本机直接打包，看 `custom-weasel-installer.md`。需要 VS 2022 + NSIS + boost_1_84_0 等。

## 设计文档

`docs/superpowers/specs/2026-05-27-rime-auto-build-design.md`
