# rime-auto-build

自动构建 Weasel（小狼毫）Windows x64 安装包。

每个 `data` 仓库（一套 Rime 方案 / 词库 / Lua / OpenCC）和每个 `weasel` 仓库（小狼毫源码）组合，会在 GitHub Releases 出一份 `.exe`。上游有 commit 才构建，没动就不动。

## 工作机制

简单说：它每小时整点检查一次上游仓库，发现更新后只打包受影响的方案和小狼毫组合，并发布到 Release。

- `builds.yaml`：单一配置，列 weasel 仓库和 data 仓库。
- `watch.yml`：每小时整点检查一次（按北京时间理解；GitHub Actions 可能延迟几分钟实际启动），对每个上游仓库跑 `git ls-remote`，对比 `state/last-seen.json`。SHA 变了就 commit 新 state、`repository_dispatch` 触发构建。
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
| `tiger` | 虎码 | [a810439322/rime-tiger](https://github.com/a810439322/rime-tiger.git) | `main` |
| `moran` | 魔然 | [rimeinn/rime-moran](https://github.com/rimeinn/rime-moran.git) | `main` |
| `092wb` | 092五笔 | [092wb/092wb](https://github.com/092wb/092wb.git) | `main` |
| `lutai` | 露台码 | [Flauver/lutai](https://github.com/Flauver/lutai.git) | `dev` |
| `openfly` | 小鹤音形 | [amorphobia/openfly](https://github.com/amorphobia/openfly.git) | `main` |
| `crane` | 凇鹤拼音 | [kchen0x/rime-crane](https://github.com/kchen0x/rime-crane.git) | `main` |
| `snow-pinyin` | 冰雪拼音 | [rimeinn/rime-snow-pinyin](https://github.com/rimeinn/rime-snow-pinyin.git) | `main` |
| `jdhe` | 简单鹤 | [rimeinn/rime-JDhe](https://github.com/rimeinn/rime-JDhe.git) | `main` |
| `kagiroi` | 日语 | [rimeinn/rime-kagiroi](https://github.com/rimeinn/rime-kagiroi.git) | `main` |
| `mungyeong` | 韩语 | [rimeinn/rime-mungyeong](https://github.com/rimeinn/rime-mungyeong.git) | `main` |
| `zrlong` | 龙码双拼 | [rimeinn/rime-zrlong](https://github.com/rimeinn/rime-zrlong.git) | `main` |

### 小狼毫版本名

| 短名 | 说明 | 仓库 | 分支 |
| --- | --- | --- | --- |
| `rime` | 官方小狼毫 | [rime/weasel](https://github.com/rime/weasel.git) | `master` |
| `qing` | 晴版小狼毫 | [a810439322/weasel](https://github.com/a810439322/weasel.git) | `master` |
| `fxliang` | fxliang 小狼毫 | [fxliang/weasel](https://github.com/fxliang/weasel.git) | `pb` |

### Release 正文怎么看

每次 Release 的 **安装包说明** 会按表格列出每个 `.exe` 的来源：

| 方案 | 小狼毫 | 安装包 |
| --- | --- | --- |
| 中文名、最后提交时间（北京时间） | 中文名、最后提交时间（北京时间） | 可点击下载链接 |

README 里只列当前配置；具体某个安装包来自哪个提交、最后提交时间是多少，以对应 Release 正文为准。

Release tag 使用 `build-YYYYMMDD-HHMM-类型` 格式，`HHMM` 是北京时间。

## 一次性打包新的方案

如果只是想临时打包一个没有收录进 `builds.yaml` 的 Rime 方案，可以直接 [提交一次性打包 Issue](https://github.com/a810439322/rime-auto-build/issues/new?template=package-data.yml)。

需要填写：

- `公开 GitHub 仓库`：只支持公开 GitHub HTTPS 仓库，例如 `https://github.com/user/rime-data`。方案短名和显示名会自动从仓库名推导。
- `分支、标签或 commit`：可选；分支、tag 或完整 40 位 commit SHA，不填就用仓库默认分支。
- `小狼毫版本`：一次只能选择一个小狼毫版本：官方小狼毫（`rime`）、晴版小狼毫（`qing`）或 fxliang 小狼毫（`fxliang`）。

机器人会先校验仓库是否公开、ref 是否存在、根目录是否像 Rime data 仓库，然后只打包这一组 data + weasel。成功后在 Issue 里直接评论下载链接，安装包在本次 workflow 的 Artifacts 里，artifact 名为 `package-request-{issue_number}`。下载需要登录 GitHub；Artifacts 有 GitHub 保留期限，不会进入正式 Releases。

想长期加入自动构建的方案，仍然需要人工审核后再改 `builds.yaml`。

## 添加新的 data 或 weasel 仓库

改 `builds.yaml`，提 commit，push。push 本身会触发一次全量构建。

## 本地构建（不走 CI）

如果想在本机直接打包，看 `custom-weasel-installer.md`。需要 VS 2022 + NSIS + boost_1_84_0 等。

## 设计文档

`docs/superpowers/specs/2026-05-27-rime-auto-build-design.md`
