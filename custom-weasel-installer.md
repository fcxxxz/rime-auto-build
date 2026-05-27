# 自定义小狼毫安装包打包说明

这份说明只讲当前这个打包文件夹的用法。目标是：除了系统工具链以外，Weasel 源代码、配置、词库、主题、Boost 和输出安装包都放在本文件夹里。

## 目录布局

把 Weasel 源码放进本文件夹下的 `weasel\`：

```text
<任意盘任意位置>\
  自定义小狼毫打包\          ← 本文件夹
    pack.bat
    pack.ps1
    weasel\                  ← 小狼毫代码  git clone --recursive https://github.com/rime/weasel
    librime\                 ← 当 weasel\librime 缺失/不完整时使用  想用新版也可以  git clone --recursive https://github.com/rime/librime
    plum\                    ← 当 weasel\plum 缺失/不完整时使用  想用新版也可以  git clone --recursivehttps://github.com/rime/plum
    custom-data\      ← 自定义数据文件夹，里面放自定义的rime配置 示例放的是虎码秃包
    boost_1_84_0\
    custom-weasel-installer.md
    weasel-*-installer.exe    ← 每次打包后输出在这里
```

`pack.ps1` 默认只按 `.\weasel` 找源码，但不会改这个源码目录。每次打包都会先把当前目录的 `.\weasel` 重新镜像到 `.pack-work\weasel`，所有 `env.bat`、`output\data`、`install.nsi` patch 和编译产物都只发生在工作副本里。脚本会拒绝指向当前打包文件夹之外的源码、数据、Boost、工作目录或输出目录。

## 系统依赖（一次性）

打包脚本会自动检测以下工具。如果缺，会给出清晰的报错和官方下载链接。

- **Visual Studio 2022 Build Tools** 或 **Community 版**，勾选「Desktop development with C++」工作负载（含 MSVC v143、ATL、MFC、Windows SDK）
- **Windows 10/11 SDK**（VS Installer 里勾上即可）
- **NSIS**：<https://nsis.sourceforge.io/Download>，默认装到 `C:\Program Files (x86)\NSIS\`
- **Git for Windows**：<https://git-scm.com/download/win>。如果你已经把完整的 `weasel\`、`librime\`、`plum\` 放在本目录，打包阶段通常不会再用到 Git。
- **7-Zip 或 Bandizip 命令行**：只有在脚本需要下载并解压预编译 librime 兜底包时才用到。
- **GitHub CLI (`gh`)**：可选；当上游 `get-rime.ps1` 遇到 GitHub API 限流时，脚本会优先尝试用已登录的 `gh` 下载 librime release 资产。

VS / SDK / 平台工具集 / Boost 路径都是脚本自动探测的，不用手动改。

## 首次打包流程

1. clone Weasel（推荐 `--recursive`）：

   ```cmd
   git clone --recursive https://github.com/rime/weasel
   ```

2. 把 clone 出来的 `weasel` 文件夹放进本打包文件夹（见上面的目录布局）。
3. 如果 `weasel\librime` 或 `weasel\plum` 缺失/不完整，把你下载好的 `librime\`、`plum\` 放在本打包文件夹根目录。
4. 把你的方案、词典、主题、Lua、OpenCC 文件放进 `custom-data\`。
5. 在 `custom-data\default.custom.yaml` 写默认勾选的方案。
6. 在 `custom-data\weasel.custom.yaml` 写默认主题。
7. 双击 `pack.bat`。

每次打包的源码来源顺序固定：

- 先把当前目录的 `.\weasel` 镜像成 `.pack-work\weasel`。
- 如果工作副本里的 `librime` 不完整，复制当前目录的 `.\librime` 到 `.pack-work\weasel\librime`。
- 如果工作副本里的 `plum` 不完整，复制当前目录的 `.\plum` 到 `.pack-work\weasel\plum`。

如果本地依赖也缺失，而 `.pack-work\weasel` 是 git 工作树，脚本才会尝试在工作副本里补 submodule 或预编译 librime；这也不会写回 `.\weasel`。

如果 `get-rime.ps1` 被 GitHub API 限流，而当前机器装了已登录的 GitHub CLI，脚本会把 librime release 资产下载到 `.pack-work\weasel\.pack-rime` 并在工作副本里解压复制。这个目录是生成物，删掉不会影响 `.\weasel`。

之后每次打包都直接编译，不需要联网。

打好的 `weasel-*-installer.exe` 会复制到本文件夹根目录。

## 脚本顶部可调变量

`pack.ps1` 顶部只有这些常用变量：

```powershell
$WeaselRepoPath    = '.\weasel'
$WorkRootPath      = '.\.pack-work'
$LibrimeSourcePath = '.\librime'
$PlumSourcePath    = '.\plum'
$CustomDataDirPath = '.\custom-data'
$BoostRootPath     = '.\boost_1_84_0'
$OutputDirPath     = '.'
$BuildArch         = 'x64'   # x64 | Win32 | arm64

# 留 $null 自动探测；只在自动探测选错时才覆盖。
$VsDevCmdPath      = $null
$SdkVer            = $null
$PlatformToolset   = $null
$BjamToolset       = $null
```

相对路径都按 `pack.ps1` 所在文件夹解析；源码、custom-data、Boost、输出目录都必须留在这个文件夹内部。

## 默认方案怎么决定

安装后默认勾选哪些方案，完全取决于 `custom-data\default.custom.yaml` 里的 `schema_list`。

例如只默认启用虎码单字和虎码官方词库：

```yaml
patch:
  schema_list:
    - {schema: tiger}
    - {schema: tigress}
```

你打别的方案包时，把这里换成你自己的方案 ID。构建脚本会根据这个 `schema_list` 生成 `output\data\weasel-visible-schemas.txt`，方案设定窗口只显示这里列出的主方案。依赖用的 schema 文件可以留在包里，但不会作为主方案显示。

## 默认主题怎么决定

安装后默认主题，完全取决于 `custom-data\weasel.custom.yaml` 里的 `style/color_scheme`。

例如默认使用某个配色 ID：

```yaml
patch:
  style/color_scheme: win11light
```

你打别的主题时，把 `win11light` 换成自己的配色 ID，并确保同一个 `weasel.custom.yaml` 里有对应的 `preset_color_schemes/<id>` 定义。

## 自己加其他方案

1. 把对应的 `*.schema.yaml` 和 `*.dict.yaml` 放进 `custom-data`。
2. 如果方案要默认显示，把它加进 `custom-data\default.custom.yaml` 的 `schema_list`。
3. 如果方案依赖 Lua，把脚本放进 `custom-data\lua`。
4. 如果方案依赖 OpenCC，把文件放进 `custom-data\opencc`。
5. 运行 `pack.bat`。

如果某个词典里写了：

```yaml
use_preset_vocabulary: true
```

构建脚本会确保安装包的 shared data 里带上 `essay.txt`，用于 librime 读取预置词频。这个文件属于程序共享数据，安装后在 `weasel-0.17.4\data`，不是用户目录顶层配置。

构建时会自动生成：

```text
output\data\weasel-custom-data.txt
```

这份清单记录本次从 `custom-data` 打进去的所有文件。安装时，小狼毫会按清单把这些文件复制到安装选项里选定的 Rime 用户文件夹；如果没有另选，默认是 `%AppData%\Rime`。

## 怎么排除原来的方案

分两种情况：

- 不想默认出现：从 `default.custom.yaml` 的 `schema_list` 里删掉。
- 连安装包里都不想带：不要把对应 `*.schema.yaml`、`*.dict.yaml` 放进 `custom-data`。

构建脚本会按 `custom-data` 清单自动删除 `output\data` 里不属于本包的顶层 `*.schema.yaml`、`*.dict.yaml`、`*.custom.yaml`。`default.yaml`、`weasel.yaml`、`punctuation.yaml`、`key_bindings.yaml` 这类基础支持文件会保留，不影响默认勾选。

## 安装后文件在哪里

安装包里的自定义文件会部署到用户可编辑目录。这个目录由安装选项决定；默认是：

```text
%AppData%\Rime
```

普通方案文件、词典、Lua、OpenCC 文件会按 `weasel-custom-data.txt` 清单复制到这个目录。当前安装包会用包里的文件覆盖同名文件。

两个入口文件会刷新：

```text
%AppData%\Rime\default.custom.yaml
%AppData%\Rime\weasel.custom.yaml
```

刷新前会保留备份：

```text
%AppData%\Rime\default.custom.yaml.before-tiger-installer
%AppData%\Rime\weasel.custom.yaml.before-tiger-installer
```

所以安装后用户仍然可以直接编辑所选 Rime 用户文件夹里的配置。

## 打包后检查什么

先看 Weasel 源码目录里的这些文件是否已生成：

- `output\data\default.custom.yaml`
- `output\data\weasel.custom.yaml`
- `output\data\weasel-custom-data.txt`
- `output\data\weasel-visible-schemas.txt`
- `output\data\essay.txt`（如果词典启用了 `use_preset_vocabulary: true`）
- 你的 `*.schema.yaml`
- 你的 `*.dict.yaml`
- `output\data\lua`
- `output\data\opencc`

再安装一次，确认：

1. 默认勾选的方案和 `custom-data\default.custom.yaml` 一致。
2. 默认主题和 `custom-data\weasel.custom.yaml` 里的 `style/color_scheme` 一致。
3. `%AppData%\Rime` 里有你打包进去的配置、词库、Lua、OpenCC 文件。
4. 方案设定窗口只显示 `schema_list` 里的主方案。
5. 安装完成页有重启选项，但默认选中稍后重启。

## 脚本对 weasel 源码的改动

`pack.ps1` 不修改本文件夹下的 `weasel\` 源码。每次运行会重新准备 `.pack-work\weasel` 工作副本，然后只在工作副本里做这些幂等改动：

- `.pack-work\weasel\env.bat`：每次重写为 pack 内部的 stub，让脚本能注入 `BOOST_ROOT` 等环境变量。
- `.pack-work\weasel\output\install.nsi`：先清掉上次由 `PACK_PS1` marker 生成的补丁块，再重新插入 NSIS 行，把 `lua\`、`opencc\*.txt` 等额外文件打进安装包。
- `.pack-work\weasel\output\data\`：注入 `custom-data`，生成清单和默认配置，合并自定义主题。

如果要升级 Weasel 源码，直接更新或替换本文件夹下的 `weasel\`。下一次运行会从新的源码重新生成 `.pack-work\weasel`。

## 一句话记法

换方案就改 `custom-data`，默认方案看 `default.custom.yaml`，默认主题看 `weasel.custom.yaml`，打包只运行 `pack.bat`，安装包输出仍在当前文件夹。

## 默认方案怎么决定

安装后默认勾选哪些方案，完全取决于 `custom-data\default.custom.yaml` 里的 `schema_list`。

例如只默认启用虎码单字和虎码官方词库：

```yaml
patch:
  schema_list:
    - {schema: tiger}
    - {schema: tigress}
```

你打别的方案包时，把这里换成你自己的方案 ID。构建脚本会根据这个 `schema_list` 生成 `output\data\weasel-visible-schemas.txt`，方案设定窗口只显示这里列出的主方案。依赖用的 schema 文件可以留在包里，但不会作为主方案显示。

## 默认主题怎么决定

安装后默认主题，完全取决于 `custom-data\weasel.custom.yaml` 里的 `style/color_scheme`。

例如默认使用某个配色 ID：

```yaml
patch:
  style/color_scheme: win11light
```

你打别的主题时，把 `win11light` 换成自己的配色 ID，并确保同一个 `weasel.custom.yaml` 里有对应的 `preset_color_schemes/<id>` 定义。

## 自己加其他方案

1. 把对应的 `*.schema.yaml` 和 `*.dict.yaml` 放进 `custom-data`。
2. 如果方案要默认显示，把它加进 `custom-data\default.custom.yaml` 的 `schema_list`。
3. 如果方案依赖 Lua，把脚本放进 `custom-data\lua`。
4. 如果方案依赖 OpenCC，把文件放进 `custom-data\opencc`。
5. 运行 `pack.bat`。

构建时会自动生成：

```text
output\data\weasel-custom-data.txt
```

这份清单记录本次从 `custom-data` 打进去的所有文件。安装时，小狼毫会按清单把这些文件复制到安装选项里选定的 Rime 用户文件夹；如果没有另选，默认是 `%AppData%\Rime`。

## 怎么排除原来的方案

分两种情况：

- 不想默认出现：从 `default.custom.yaml` 的 `schema_list` 里删掉。
- 连安装包里都不想带：不要把对应 `*.schema.yaml`、`*.dict.yaml` 放进 `custom-data`。

构建脚本会按 `custom-data` 清单自动删除 `output\data` 里不属于本包的顶层 `*.schema.yaml`、`*.dict.yaml`、`*.custom.yaml`。`default.yaml`、`weasel.yaml`、`punctuation.yaml`、`key_bindings.yaml` 这类基础支持文件会保留，不影响默认勾选。

## 安装后文件在哪里

安装包里的自定义文件会部署到用户可编辑目录。这个目录由安装选项决定；默认是：

```text
%AppData%\Rime
```

普通方案文件、词典、Lua、OpenCC 文件会按 `weasel-custom-data.txt` 清单复制到这个目录。当前安装包会用包里的文件覆盖同名文件。

两个入口文件会刷新：

```text
%AppData%\Rime\default.custom.yaml
%AppData%\Rime\weasel.custom.yaml
```

刷新前会保留备份：

```text
%AppData%\Rime\default.custom.yaml.before-tiger-installer
%AppData%\Rime\weasel.custom.yaml.before-tiger-installer
```

所以安装后用户仍然可以直接编辑所选 Rime 用户文件夹里的配置。

## 打包后检查什么

先看 Weasel 源码目录里的这些文件是否已生成：

- `output\data\default.custom.yaml`
- `output\data\weasel.custom.yaml`
- `output\data\weasel-custom-data.txt`
- `output\data\weasel-visible-schemas.txt`
- 你的 `*.schema.yaml`
- 你的 `*.dict.yaml`
- `output\data\lua`
- `output\data\opencc`

再安装一次，确认：

1. 默认勾选的方案和 `custom-data\default.custom.yaml` 一致。
2. 默认主题和 `custom-data\weasel.custom.yaml` 里的 `style/color_scheme` 一致。
3. `%AppData%\Rime` 里有你打包进去的配置、词库、Lua、OpenCC 文件。
4. 方案设定窗口只显示 `schema_list` 里的主方案。
5. 安装完成页有重启选项，但默认选中稍后重启。

## 一句话记法

换方案就改 `custom-data`，默认方案看 `default.custom.yaml`，默认主题看 `weasel.custom.yaml`，打包只运行 `pack.bat`，安装包输出仍在当前文件夹。
