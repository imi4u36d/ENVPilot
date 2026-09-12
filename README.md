[![Release](https://img.shields.io/github/v/release/imi4u36d/ENVPilot?sort=semver)](https://github.com/imi4u36d/ENVPilot/releases)
[![macOS](https://img.shields.io/badge/macOS-14%2B-111111?logo=apple)](https://github.com/imi4u36d/ENVPilot)
[![Swift](https://img.shields.io/badge/Swift-6.2-F05138?logo=swift&logoColor=white)](https://www.swift.org/)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)

# ENVPilot

ENVPilot 是一款原生 macOS 开发环境管理工具。它统一管理 Node.js、JDK 和 Python 运行时，并根据全局设置或项目中的 `.envpilot` 文件自动生成终端环境。

- 原生 SwiftUI 主窗口（侧边栏 + 工具栏）与可选菜单栏入口
- 运行时由 ENVPilot 自主管理，不依赖 Homebrew、SDKMAN、nvm、fnm 或 pyenv
- 同时提供图形界面、`envpilot-helper` 和简写命令 `ep`
- 支持项目版本策略、环境预设和自定义环境变量

## 应用界面

主窗口分四个页面，左侧栏切换（⌘R 随时重新读取本机运行时）：

| 页面 | 作用 |
| --- | --- |
| 概览 | 当前生效的 Node / JDK / Python、版本来源（项目声明或全局默认）、一键切换版本、终端将执行的导出语句 |
| 运行时 | 一个页面内切换 Node / JDK / Python；上半部分是已安装版本（设为默认、卸载），下半部分是可安装版本（搜索、仅 LTS、安装进度） |
| 项目 | 项目版本策略，选择或粘贴项目目录后展示 `.envpilot` 解析出的版本、是否已安装，以及让当前终端立即生效的命令 |
| 环境预设 | 左侧预设列表，右侧编辑 npm / pnpm / yarn registry、`NODE_OPTIONS` 与自定义环境变量 |

应用设置（菜单栏入口开关、终端环境、路径与诊断信息）在 **ENVPilot ▸ 设置…** 或 ⌘, 的独立窗口中，不占用主窗口页面。

## 功能

### 运行时管理

- Node.js：从 Node 官方分发查询版本，支持 LTS 过滤、安装、切换和卸载。
- JDK：从 Adoptium Temurin 与 Azul Zulu 查询版本，支持 LTS 过滤，并通过 `JAVA_HOME` 和 `PATH` 激活。
- Python：从 Python 官方分发查询 Python 3.8+，安装 ENVPilot 管理的 CPython，并通过 `ENVPILOT_PYTHON_HOME` 和 `PATH` 激活。
- 已安装运行时默认保存在 `~/.envpilot/runtimes`。
- 下载支持进度显示；安装前执行归档路径检查，并使用暂存目录完成安全替换。

### 项目感知

在项目根目录创建 `.envpilot`：

```dotenv
NODE_VERSION=24.18.0
JAVA_VERSION=17
PYTHON_VERSION=3.13.7
```

进入项目目录后，zsh 集成会向上查找最近的 `.envpilot` 文件并激活对应版本。你也可以在应用中切换为始终使用全局默认版本。

### 环境预设

每个预设可配置：

- npm、pnpm、yarn registry
- `NODE_OPTIONS`
- 任意合法名称的自定义环境变量

预设切换后会应用到新打开的终端。

## 安装

### 下载应用

从 [Releases](https://github.com/imi4u36d/ENVPilot/releases) 下载最新构建。

### 从源码一键安装

要求 macOS 14 或更高版本，以及支持 Swift 6.2 的开发工具链。

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

# 写入当前项目的 .envpilot
ep use n 22.17.0
ep use j 21
ep use py 3.13.7

# 管理环境预设
ep profile list
ep profile create "公司网络" --select
ep profile set "公司网络" --npm-registry https://registry.example.com
ep profile var set "公司网络" HTTPS_PROXY http://127.0.0.1:7890

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

打包产物位于：

```text
dist/ENVPilot.app
dist/ENVPilot.dmg
```

项目包含三个 SwiftPM 产品：

- `ENVPilotApp`：SwiftUI macOS 应用
- `ENVPilotCore`：运行时检测、安装、配置与 shell 集成
- `envpilot-helper`：终端 CLI，安装后同时提供 `ep` 符号链接

## zsh 集成

如需单独安装或更新 shell 片段：

```bash
./scripts/install_zsh_integration.sh release ~/.local/bin/envpilot-helper
```

生成的片段由 `# >>> ENVPilot >>>` 和 `# <<< ENVPilot <<<` 包围，可重复执行安装脚本安全更新。

## 许可证

[Apache License 2.0](LICENSE)
