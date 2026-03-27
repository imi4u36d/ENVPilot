[![Release](https://img.shields.io/github/v/release/imi4u36d/ENVPilot?sort=semver)](https://github.com/imi4u36d/ENVPilot/releases)
[![macOS](https://img.shields.io/badge/macOS-13%2B-111111)](https://github.com/imi4u36d/ENVPilot)
[![Swift](https://img.shields.io/badge/Swift-6.2-F05138)](https://www.swift.org/)

# ENVPilot

ENVPilot 是一个 macOS 菜单栏工具，用于切换 Node / JDK 版本并管理环境配置。

![ENVPilot Preview](./docs/preview.svg)

## 功能

- 中文界面（菜单栏与设置页）
- Node 版本管理（仅支持 NVM）
  - 未检测到 NVM 时自动尝试使用 Homebrew 安装
  - 支持可视化安装 / 切换 / 卸载 Node 版本
  - 列表展示每个 Node 版本的安装路径
- JDK 版本检测与切换（通过 `JAVA_HOME` 激活）
- 缺失组件一键安装（在 App 设置页）
  - `JDK 21`（通过 Homebrew）
- Profile 环境配置
  - `npm/pnpm/yarn registry`
  - `NODE_OPTIONS`
  - 自定义环境变量

## 构建

```bash
cd /Users/wangzhuo/tools/ENVPilot
swift build
```

## 打包 .app

```bash
cd /Users/wangzhuo/tools/ENVPilot
./scripts/package_app.sh release
```

输出：

```bash
/Users/wangzhuo/tools/ENVPilot/dist/ENVPilot.app
```

## 本地一键安装（推荐）

```bash
cd /Users/wangzhuo/tools/ENVPilot
./scripts/install_local.sh
```

会自动安装：

- App 到 `~/Applications/ENVPilot.app`
- Helper 到 `~/.local/bin/envpilot-helper`
- zsh 自动激活片段到 `~/.zshrc`

## 运行 App

```bash
cd /Users/wangzhuo/tools/ENVPilot
swift run ENVPilotApp
```

## Helper 命令

```bash
envpilot-helper status [--cwd <path>]
envpilot-helper set-version <version>
envpilot-helper set-jdk <version-or-home-path>
envpilot-helper set-profile <profile-name-or-id>
envpilot-helper activate [--cwd <path>]
envpilot-helper install-snippet [--helper-path <path>]
```

## zsh 集成

手动输出并安装 snippet：

```bash
/Users/wangzhuo/tools/ENVPilot/.build/debug/envpilot-helper install-snippet --helper-path /Users/wangzhuo/tools/ENVPilot/.build/debug/envpilot-helper
```

或者使用脚本：

```bash
cd /Users/wangzhuo/tools/ENVPilot
./scripts/install_zsh_integration.sh release /Users/wangzhuo/tools/ENVPilot/.build/release/envpilot-helper
```
