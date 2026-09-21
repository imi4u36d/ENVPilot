[![Release](https://img.shields.io/github/v/release/imi4u36d/ENVPilot?sort=semver)](https://github.com/imi4u36d/ENVPilot/releases)
[![Release macOS app](https://github.com/imi4u36d/ENVPilot/actions/workflows/release.yml/badge.svg)](https://github.com/imi4u36d/ENVPilot/actions/workflows/release.yml)
[![macOS](https://img.shields.io/badge/macOS-14%2B-111111?logo=apple)](https://github.com/imi4u36d/ENVPilot)
[![Swift](https://img.shields.io/badge/Swift-6.2-F05138?logo=swift&logoColor=white)](https://www.swift.org/)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)

# ENVPilot

ENVPilot 是一款原生 macOS 开发环境管理工具。它统一管理 Node.js、JDK 和 Python 运行时，并按你在应用里选定的版本为终端生成对应的环境。

- 运行时由 ENVPilot 自主管理，不依赖 Homebrew、SDKMAN、nvm、fnm 或 pyenv
- 同时提供图形界面、`envpilot-helper` CLI 和简写命令 `ep`
- 菜单栏常驻入口，随时查看和切换当前生效版本；可选开机自启动、关窗后是否继续留在菜单栏

## 应用界面

### 菜单栏面板

点击菜单栏图标即可查看三类运行时的当前生效版本，并直接切换：

| 收起 | 展开版本列表 |
| --- | --- |
| ![菜单栏面板](docs/screenshots/menubar.png) | ![展开版本列表](docs/screenshots/menubar-expanded.png) |

- 每行显示运行时与当前生效版本，点击整行展开已安装版本列表
- 已安装版本标注来源（ENVPilot 管理 / 系统安装），当前版本打勾，选中即切换并收起面板
- 未安装时给出明确的「未安装」状态，展开后可跳转到运行时页处理
- 底部是窗口级操作：主窗口、设置、退出

### 主窗口

主窗口分为两个页面，左侧栏切换：

| 页面 | 作用 |
| --- | --- |
| 概览 | 当前生效的 Node / JDK / Python、一键切换版本、终端将执行的导出语句 |
| 运行时 | 一个页面内切换 Node / JDK / Python；已安装版本与可安装版本分区展示，支持搜索、仅 LTS 过滤与安装进度 |

侧边栏底部只留设置按钮。重新读取本机运行时放在「显示」菜单里，快捷键仍是 ⌘R。

![概览页](docs/screenshots/overview.png)

应用设置在 **ENVPilot ▸ 设置…** 或 ⌘, 的独立窗口中，不占用主窗口页面。里面有四个开关：菜单栏入口、关闭主窗口后是否保留菜单栏图标、开机自启动（走 macOS 登录项）、以及每天自动检查更新。

## 功能

### 运行时管理

- **Node.js**：从 Node 官方分发查询版本，支持 LTS 过滤、安装、切换和卸载。
- **JDK**：从 Adoptium Temurin 与 Azul Zulu 查询版本，支持 LTS 过滤，保留完整的 macOS `.jdk` 目录结构，并通过 `JAVA_HOME` 和 `PATH` 激活。
- **Python**：从 Python 官方分发查询 Python 3.8+，安装 ENVPilot 管理的 CPython，并通过 `ENVPILOT_PYTHON_HOME` 和 `PATH` 激活。
- 已安装运行时默认保存在 `~/.envpilot/runtimes`。下载带进度显示；安装前校验归档路径，并使用暂存目录完成安全替换，替换失败会恢复原安装。

### 终端环境

版本只由全局选择决定：终端环境不随所在目录变化，也没有「预设」这层间接。`envpilot-helper activate` 仍然接受 `--cwd`（已安装用户的 `~/.zshrc` 片段带着它跑），但那个参数只用于显示当前目录，不再参与选版本。

### 软件更新

- 从 GitHub Releases 查询最新版本（优先 Releases API，被限流或不可达时退回 `releases/latest` 的跳转地址），并按语义化版本比较——`0.6.10` 比 `0.6.9` 新，预发布版小于同号正式版。
- **一键更新**：下载 `ENVPilot.zip` → `ditto` 解压 → 校验 bundle id、`CFBundleShortVersionString` 与 `codesign --verify --deep --strict` → 退出应用后由一个脱离进程的脚本替换 `.app`、清掉隔离属性、顺手刷新 `~/.local/bin/envpilot-helper`，再重新启动。校验任何一步不过都不会动现有安装。
- 当前运行位置无法替换时（`swift run` 的非打包进程、DMG 或 App Translocation 的只读路径），退回到下载 dmg 并打开，不做危险操作。
- 入口有四个：应用菜单 **检查更新…**、菜单栏面板的 **检查更新…**（已发现新版本时直接显示 **更新到 vX.Y.Z…**）、设置窗口的「软件更新」卡片，以及侧边栏底部的新版本角标。
- 默认每天启动后自动查一次（可关）。更新说明直接取 Release 正文，在卡片里滚动查看。

## 安装

### 下载应用

从 [Releases](https://github.com/imi4u36d/ENVPilot/releases) 下载 `ENVPilot.dmg`，打开后把 ENVPilot 拖到「应用程序」目录。

装好之后不必再手动下载：**ENVPilot ▸ 检查更新…**（或设置里的「软件更新」卡片）会查询最新发布并一键更新到新版本。

要求 macOS 14 或更高版本、Apple Silicon（arm64）。

> 发布构建为 ad-hoc 签名、未经 Apple 公证。首次打开若提示「已损坏」或「无法验证开发者」，请执行
> `xattr -dr com.apple.quarantine /Applications/ENVPilot.app`，或在「系统设置 ▸ 隐私与安全性」中允许打开。

### 从源码安装

需要 macOS 14+ 与支持 Swift 6.2 的工具链：

```bash
git clone https://github.com/imi4u36d/ENVPilot.git
cd ENVPilot
./scripts/install_local.sh
```

脚本会安装：

- `~/Applications/ENVPilot.app`
- `~/.local/bin/envpilot-helper`
- `~/.local/bin/ep`
- `~/.zshrc` 中带有 ENVPilot 标记的自动激活片段

安装完成后重新打开终端，或执行：

```bash
source ~/.zshrc
open ~/Applications/ENVPilot.app
```

## 常用命令

```bash
# 查看当前环境与诊断结果
ep status
ep doctor

# 查询和安装运行时
ep available node --lts
ep available jdk --lts
ep available python
ep install-node 22.17.0
ep install-jdk 21
ep install-python 3.13.7

# 输出完整帮助
ep help
```

多数查询命令支持 `--format json`，修改命令支持 `--dry-run`。完整命令以 `ep help` 输出为准。

## 构建与开发

```bash
# 构建全部目标
swift build

# 运行测试
swift test

# 构建、打包并验证本地应用进程
./script/build_and_run.sh --verify

# 生成发布版 app 与 dmg
./scripts/package_app.sh release
```

打包产物位于 `dist/ENVPilot.app` 与 `dist/ENVPilot.dmg`。版本号可通过环境变量注入，发布流水线即以此覆盖 tag 版本：

```bash
APP_VERSION=0.6.1 APP_BUILD=4 ./scripts/package_app.sh release
```

### 图标

应用图标由脚本几何绘制生成（`scripts/generate_app_icon.py`，需要 Pillow），不是手绘素材；改配色或几何参数后重新生成即可：

```bash
python3 scripts/generate_app_icon.py
```

脚本会输出 1024 主稿、10 档 iconset 尺寸，并调用 `iconutil` 生成 `Resources/AppIcon.icns`。

### 界面快照

菜单栏弹层不在窗口系统里：`screencapture` 抓不到它，自动化脚本也无法点开。项目内置离屏快照工具，用 `ImageRenderer` 渲染真实的 `MenuBarView`（读取真实运行时状态），便于设计评审与回归比对：

```bash
# 同时输出浅色与深色
ENVPILOT_MENUBAR_SNAPSHOT=/tmp/menubar.png dist/ENVPilot.app/Contents/MacOS/ENVPilotApp

# 指定展开某一类运行时的版本列表
ENVPILOT_MENUBAR_SNAPSHOT=/tmp/expanded.png ENVPILOT_MENUBAR_SNAPSHOT_PICK=node \
  dist/ENVPilot.app/Contents/MacOS/ENVPilotApp
```

未设置该环境变量时，快照工具完全不参与启动流程。

设置窗口的「软件更新」卡片同样可以离屏渲染（用真实的 `NSWindow` + `cacheDisplay`，因为 `ImageRenderer` 画不出滚动区与按钮）：

```bash
# UPDATE 取 available / downloading / latest / failed，纯状态注入、不联网
ENVPILOT_WINDOW_SNAPSHOT=/tmp/settings.png ENVPILOT_WINDOW_SNAPSHOT_SETTINGS=1 \
  ENVPILOT_WINDOW_SNAPSHOT_UPDATE=available dist/ENVPilot.app/Contents/MacOS/ENVPilotApp
```

### 更新流程探针

检查与更新这条链路自带探针（`Sources/NodePilotApp/UpdateProbe.swift`），平时完全不参与运行：

```bash
APP=dist/ENVPilot.app/Contents/MacOS/ENVPilotApp

# 只查最新版本，打印安装方式与结果
ENVPILOT_UPDATE_PROBE=check $APP

# 下载 + 解压 + 校验，打印暂存路径（不动当前安装）
ENVPILOT_UPDATE_PROBE=stage $APP

# 完整走一遍替换；RELAUNCH=0 时不重启，便于自动验证
ENVPILOT_UPDATE_PROBE=apply ENVPILOT_UPDATE_RELAUNCH=0 $APP
```

`ENVPILOT_UPDATE_STAGING_ROOT` 可以改写暂存目录（沙箱或 CI 里指到临时目录）。

## 持续集成与发布

`.github/workflows/release.yml` 在推送 `v*` tag 时自动在 `macos-26` 运行器上构建并发布：

1. `swift test`（当前 46 个用例）
2. `./scripts/package_app.sh release`，用 tag 覆盖 `CFBundleShortVersionString`
3. 校验 bundle 签名，产出 `ENVPilot.dmg` 与 `ENVPilot.zip`
4. 创建对应的 GitHub Release 并附上产物

手动触发（Actions ▸ Release macOS app ▸ Run workflow）时只上传 workflow artifact，不创建 Release。需要正式发布时打 tag 即可：

```bash
git tag v0.6.1
git push origin v0.6.1
```

## 项目结构

项目包含三个 SwiftPM 产品：

- `ENVPilotApp`：SwiftUI macOS 应用（`Sources/NodePilotApp`）
- `ENVPilotCore`：运行时检测、安装、配置与 shell 集成（`Sources/NodePilotCore`）
- `envpilot-helper`：终端 CLI，安装后同时提供 `ep` 符号链接（`Sources/nodepilot-helper`）

## zsh 集成

如需单独安装或更新 shell 片段：

```bash
./scripts/install_zsh_integration.sh release ~/.local/bin/envpilot-helper
```

生成的片段由 `# >>> ENVPilot >>>` 和 `# <<< ENVPilot <<<` 包围，可重复执行安装脚本安全更新。

## 许可证

[Apache License 2.0](LICENSE)
