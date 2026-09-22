# Changelog

## v1.0.1 - 2026-09-22

### 修复：1.0.0 安装后打不开（「意外退出」）

- **原因**：`Package.swift` 给 `ENVPilotApp` 声明了 `resources:`，SwiftPM 因此生成 `Bundle.module`，而侧边栏的品牌图标正好读它。这个访问器在找不到资源包时会 `fatalError`，可「资源包该放哪」取决于构建工具——CI 上原生 SwiftPM 生成的访问器去 `.app` **根目录**找 `ENVPilot_ENVPilotApp.bundle`，打包脚本却按 macOS 惯例放进 `Contents/Resources/`。于是应用一渲染侧边栏就 SIGTRAP 崩溃。签名、`codesign --verify`、DMG 结构检查都看不出这个问题：`swift run` 与本地 Xcode 构建路径正常，只有装进 `/Applications` 的那一份会崩。
- **修复**：图标改从主 bundle 读（`Bundle.main.image(forResource: "AppIcon")`——脚本本来就把 `AppIcon.icns` 放进 `Contents/Resources/`），并去掉 `resources:` 声明，让 `Bundle.module` 这个失败模式彻底不存在。
- **防回归**：`scripts/create_dmg.sh` 现在会在签名之后、生成 DMG **之前**，真的把打好的 `.app` 启动一次并确认它 8 秒内没有退出。只做结构校验是拦不住「DMG 打得出来、装上去打不开」这类问题的。

> 已经装了 1.0.0 的话：它打不开，所以用不了应用内的「检查更新」，请直接下载本页的 DMG 覆盖安装。

## v1.0.0 - 2026-09-22

第一个 1.0。定位从「Node 版本管理器」扩成一整套开发环境管理器：除了 Node.js / JDK / Python，现在还管终端里的 AI 编码工具和包管理器；并且按 Apple HIG 做了一轮完整审计，把界面、无障碍、可靠性和数据安全上的问题一次性收干净。

### 新增：AI 工具版本管理

- 自动探测 `codex`、`claude`、`pi`、`opencode`，显示可执行文件路径、安装来源、当前版本与最新版本。
- 识别 Homebrew Cask、Homebrew Formula、ENVPilot Node、npm 与 pnpm 五种安装来源，更新时分别走 `brew upgrade` 或工具自身的更新命令。
- 已被其他来源安装的工具可一键切到 ENVPilot 管理：安装最新版到当前 ENVPilot Node，新终端优先使用该版本。
- 支持单个更新与「全部更新」；某一个工具检查失败只影响它自己，不会把整页状态带崩。

### 新增：包管理器管理

- 自动探测 `npm`、`pnpm`、`brew`、`uv`，显示来源、路径、当前版本和最新版本。
- 未安装时使用官方安装脚本；已安装时优先用自身的更新命令，Homebrew 管理的走 `brew upgrade`。
- 支持 npm / pnpm / uv 的镜像源设置，写入 `settings.json`，改完对新开的终端生效。
- 独立安装的 pnpm 与 uv 可一键切到 ENVPilot 管理（pnpm 装到当前 ENVPilot Node，uv 装到 `~/.envpilot/tools`）。
- 复用 AI 环境页那套进度与取消交互。

### 新增：环境检查与一键修复

- 首启检查 ENVPilot 运行 AI 工具所需的基础配置，缺少的必需项可一键补齐，逐项给出状态、说明与修复提示。
- 修复过程显示当前阶段，并且**可以中途取消**（会真的终止正在跑的安装）。
- 报告 60 秒内复用，不再每次打开都重跑一遍扫描。

### 主窗口与菜单栏

- 概览页改成 hero 行：版本号用大号等宽数字，右侧是名称与来源胶囊，路径次要显示。
- 侧边栏拆成品牌区与导航区两段，选中态改用强调色浅底 + 圆角，行高与行距不再被 `List` 牵着走。
- 新增 **⌘1–⌘4** 切页；「显示」菜单里的侧边栏开关标题会跟随折叠状态变化。
- 侧边栏宽度与折叠状态现在跨启动保留；**点 Dock 图标能找回主窗口**（此前关掉菜单栏入口又关掉窗口后，Dock 是唯一入口却没人接）。
- 窗口最小尺寸从 880×560 降到 640×480，不再挡住 1440 宽屏幕上的半屏平铺。
- 设置窗口可以缩放了；那张卡片里的两个开关现在对齐在同一条竖线上。

### 可靠性与数据安全

- **命令执行有了墙钟超时**（常规 30 分钟、源码构建 60 分钟），超时按 `timeout(1)` 约定返回退出码 124 并在 stderr 写明原因。
- **取消会终止整棵进程树**：以前只给 `/bin/zsh` 发 SIGTERM，`npm install`、`make`、`brew` 会变成孤儿继续跑；现在递归收集子孙（先 SIGTERM、宽限后 SIGKILL）。
- **所有长任务都能取消了**：运行时安装/切换/更新、AI 工具更新、包管理器安装、200MB 的更新下载——最后一条以前只是「不等它」，现在是 `invalidateAndCancel()` 真的掐断传输。
- **`~/.zshrc` 改写前先备份**（`~/.zshrc.envpilot-backup-<时间戳>`），保留原权限与属主，内容没变就完全不写。
- **`settings.json` 损坏不再被当成「没有设置」**：坏文件改名留档并提示，读操作不再顺手写盘；「读-改-写」改为原子操作，并发的镜像保存不会互相覆盖。
- **远程安装脚本不再 `curl | sh`**：先完整下载到临时文件、校验非空且确实是脚本，再执行；npm 那条还漏了 `-f`（HTTP 错误页会被喂给 `sh`）。
- 卸载运行时时被替换掉的独立 `pnpm`/`uv` 改为**移进废纸篓**并把结果写进成功提示，不再静默 `removeItem`。
- Python 源码归档按 python.org 官方 `md5_sum` 校验（校验源缺失时明确显示「未校验」）；Zulu JDK 仍无校验和，见「已知限制」。
- 可执行文件探测与进度上报都做了缓存与去重：一次操作只解析一次路径表，`brew install` 刷出的上千行同类输出只上报一次。

### 无障碍与视觉

- 新增排版令牌 `DesignType`：40 处硬编码字号迁移到系统语义样式，字号终于会跟随「更大字体」缩放；按钮高度、徽章图标、菜单栏面板宽高也随之缩放。
- **适配「提高对比度」**：令牌层现在识别高对比外观（此前 `.accessibilityHighContrastAqua` 会被归到普通浅色，整套颜色纹丝不动），半透明描边、凹槽与选中底色自动加深。
- 菜单栏图标补上无障碍名称——这是这个 App 在 VoiceOver 里唯一的入口，此前是匿名的。
- 自定义按钮样式（侧边栏行、菜单栏面板行）补上键盘焦点环；选中态不再只靠颜色区分。
- 中性胶囊的文字对比度从约 4.0:1 提到 4.5:1 以上；错误信息从窗口底部状态栏移到**顶部横幅**（底栏会被窗口位置挡住）。
- 设置页去掉了嵌套滚动区，滚动条不再把滚轮困在那几个 150pt 的小框里。

### 工程

- 约 1,400 行探针/离屏快照代码整体移入 `#if DEBUG`：release 包里不再包含它们（实测已从二进制中消失），热路径上每次 `body` 求值的探针调用也只在调试构建存在。
- 接入 **hig-doctor 静态审计**：`.github/workflows/hig-audit.yml` + `.hig-baseline.json`，PR 与 main 上跑，只挡新增问题，critical 为 0 才允许合并。本轮审计结论：95 → 0（16 项已知误报/刻意选择进 baseline），正向模式 276 → 325。
- 测试从 82 个增加到 **105 个**，新增覆盖超时与进程树终止、配置损坏隔离、归档校验、废纸篓、阶段去重、`~/.zshrc` 备份等。
- 仓库里删掉的探针入口不影响使用：需要离屏快照或折叠性能探针时用调试构建（`swift build` / `swift run`）。

### 已知限制

- Zulu JDK 仍无校验和：Azul 的分发元数据里没有稳定可取的 hash。
- npm / pnpm / uv / Homebrew 的安装脚本 URL 是 `latest`/`HEAD` 引用，无法钉 SHA-256；当前保证是「完整下载并确认是可执行脚本后才运行」。
- 运行时**卸载**还不能中途取消（本地删目录，秒级完成）；安装与更新可以。
- UI 文案仍是硬编码中文，`NSLocalizedString` 为 0 处。

## v0.6.7 - 2026-09-22

### 工程

- 发布流水线合进 `.github/workflows/release.yml` 一条脚本：`swift build -c release` → 组装 `.app` → 签名 → DMG/ZIP → sha256 → 建 Release。签名证书放在 `release-signing` Environment 上并设了 required reviewers，没配 Secret 时自动回退 ad-hoc。本版本无用户可见改动。

## v0.6.6 - 2026-09-21

### 移除：项目作用域与环境预设

「项目」和「环境预设」两个页面，连同它们背后的整套机制一起删掉了——不是把入口藏起来，是把解析链路整条拆掉。

- 删掉「按当前目录向上找 `.envpilot` 覆盖版本」这条链路。终端环境只由全局选择的版本决定，不再随所在目录变化。注意：这里读的从来不是 `.nvmrc` / `.java-version` / `.python-version`，只有 ENVPilot 自己的 `.envpilot`（`NODE_VERSION=` 这类键），所以删掉它不影响任何 nvm / jenv / pyenv 的兼容性。
- 删掉环境预设：registry、`NODE_OPTIONS`、自定义环境变量的注入，以及 `$ENVPILOT_ACTIVE_PROFILE`。
- 跟着一起删的：`ProjectNodeVersionResolver` / `ProjectJavaVersionResolver` / `ProjectPythonVersionResolver`、`ProfileEnvironmentBuilder`、`ProjectsView`、`ProfilesView`、`EnvironmentProfile` 与 `ProjectVersionPreference` 两个模型，以及 10 个相关用例（`swift test` 56 → 46）。
- **CLI 破坏性变更**：`ep use` 与 `ep profile` 整个命令族变成 Unknown command（退出码 2）；`ep status` 不再输出 `project_version_preference` / `selected_profile_id` / `selected_profile_name` / `profiles_count` / `selected_profile`，`--include-profile` 不再接受，`--fields` 里点这些名字会直接报 `Unknown status field`。`ep config get/set` 去掉 `project-version-preference` 与 `selected-profile` 两个键。自己脚本用到上面任何一项的要改。
- **shell 片段兼容**：`envpilot-helper activate` 仍然接受 `--cwd`。已安装用户 `~/.zshrc` 里跑的是 `activate --cwd "$PWD" > … && mv … && . …`，一旦不认这个参数，整条 `&&` 链不执行、终端环境会静默失效。参数照旧解析，只是不再参与选版本。
- `settings.json` 里遗留的 `profiles` / `selectedProfileID` / `projectVersionPreference` 三个键不需要迁移：`AppSettings` 用合成的 `Codable`，未知键读的时候忽略，下一次保存就写没了。

### 主窗口

- 侧边栏底部两行小字（运行时版本摘要、「新终端生效」）和中间的刷新按钮删掉，只留更新角标与设置按钮。刷新挪进「显示」菜单，⌘R 不变。
- 侧边栏重新分成两区：上面的品牌区（图标加大到 30pt，顶部留白越过红绿灯）与下面的导航区（「概览」「运行时」两项平铺，不再分组）。此前品牌行和两个导航项挤在同一个 `List` 里，三行等高贴在一起，整块内容「堆」在侧边栏顶部。导航项改用 `SelectableRowStyle`（强调色浅底 + 圆角）替代 `List` 的全宽选中条，行高和行间距（6pt）可以自己做主。
- 修好设置按钮。`NSApp.sendAction(Selector(("showSettingsWindow:")))` 在 macOS 27 上会返回 `true`（响应链上的 `AppDelegate` 用消息转接把动作吃掉了）但一个窗口都不开——按钮看起来就是点不动。现在改成派发主菜单里那个「设置…」项（SwiftUI 把它接在自己的 `menuAction:` 上），实测能真的开出设置窗口；两个历史选择器留作老系统的降级路径。

### 菜单栏

- 图标从 SF Symbol `terminal.fill` 换成跟 App 图标同一套图形（「>」折角 + 竖排三点），画成模板图，由系统按明暗菜单栏自己染色。
- 面板里那行「当前作用域路径」跟着项目作用域一起删掉，换成一句「切换版本后，新开的终端才会用上」。

### 设置

- 新增「开机自启动」，走 macOS 登录项（`SMAppService.mainApp`）。裸二进制下注册不了，开关会置灰并写明原因，不假装生效。
- 新增「关闭主窗口后保留菜单栏图标」。默认开，跟原来一样；关掉后最后一个窗口一关就退出应用（设置窗口还开着时不算最后一个窗口）。

### 本地化

- 系统级菜单中文化。此前 bundle 里没有任何 `.lproj`，「关于 / 编辑 / 显示 / 窗口 / 帮助」以及「Toggle Sidebar」这些系统菜单项在中文系统上仍是英文。打包时现在会带上 `Resources/zh-Hans.lproj/Localizable.strings`，并把 `CFBundleDevelopmentRegion` 改为 `zh_CN`、补上 `CFBundleLocalizations`。
- 「Toggle Sidebar」那条的标题不走本 App 的本地化表，改成接管「帮助」菜单：折叠侧边栏挪到「显示」菜单（⌃⌘S），帮助入口换成一条中文项。
- 顺带发现那条英文菜单项本来就是个空动作：它发的 `toggleSidebar:` 只作用于「真 sidebar item」，而本 App 用的是普通 `NSSplitViewItem`，整条响应链上没人接（`sendAction(to: nil)` 直接返回 false）。新的「切换侧边栏」改成先找出窗口背后那个 `SidebarSplitViewController`（从 `NSSplitView` 的 `delegate` 找）再直接调用它的动作——跟标题栏那个按钮同一个入口，实测能把侧边栏收起来（分隔条 218 → -2）。

### 工具

- `ENVPILOT_PERF_SETTINGS_PROBE=1`：配合 `ENVPILOT_PERF_DUMP=1`，直接走生产路径 `WindowActions.openSettings()` 并报告有没有真的开出设置窗口。设置入口下次再断，这条能当场照出来。
- `ENVPILOT_LOGIN_PROBE=status|on|off`：在 `.app` 里跑，打印并切换登录项状态。开机自启动这种东西，「编译通过」和「系统真的记下了」是两件事，得能读回来才算验证过（实测 `on` 之后回读是「已开启」，`off` 之后是「未开启」）。
- `scripts/ui_snapshot.sh` 的页面循环改为 `overview runtimes`。

## v0.6.5 - 2026-09-21

### 软件更新

- 新增「检查更新」：从 GitHub Releases 查最新版本并支持一键更新。查询优先走 Releases API（未鉴权），被限流或不可达时退回 `releases/latest` 的 302 跳转地址，再按发布流水线固定的资产名拼下载地址；比较版本用语义化版本（`0.6.10` > `0.6.9`，预发布版小于同号正式版），当前版本读不到（开发构建）时一律按「有更新」处理。
- 一键更新走 `ENVPilot.zip`：`ditto` 解压后校验 bundle id、`CFBundleShortVersionString` 与 `codesign --verify --deep --strict`，全部通过才写一个脱离 app 生命周期的替换脚本——等本进程退出 → `ditto` 覆盖 `.app` → `xattr -dr com.apple.quarantine` → 刷新 `~/.local/bin/envpilot-helper`（存在才刷新）→ `open` 重启。zip 下载、校验、换包全程在后台线程，卡片里显示百分比与速度。
- 运行位置决定落点：可写的 app 目录原地替换；DMG 与 App Translocation 的只读路径装到 `~/Applications`；非打包进程（`swift run`）只下载 dmg 并打开，不做替换。
- 入口四处：应用菜单「关于 ENVPilot」下的 **检查更新…**、菜单栏面板底部（已发现新版本时变成 **更新到 vX.Y.Z…**，进度在设置窗口里看）、设置窗口的「软件更新」卡片、以及侧边栏底部状态区的新版本角标。启动后延迟 3 秒自动检查，24 小时内只查一次，可在卡片里关掉。
- 设置窗口新增「软件更新」卡片：当前版本、状态胶囊、更新说明（Release 正文的轻量 Markdown 降级）、一键更新按钮、下载进度、每天自动检查开关与上次检查时间。命令式入口（菜单/菜单栏）的结果用系统弹窗给出，发现新版本时顺手打开设置窗口。
- 新增 `Sources/NodePilotCore/AppUpdateService.swift`（版本比较、GitHub 查询、下载、校验、替换脚本）与 `Sources/NodePilotApp/AppUpdateModel.swift`（状态机）。核心逻辑有 12 个单测覆盖：版本解析与比较、GitHub 返回体解码、安装方式判定、真实 zip 的解压与签名校验、替换脚本内容。

### 工具

- `WindowSnapshot` 增加 `ENVPILOT_WINDOW_SNAPSHOT_SETTINGS=1`：用真实的 `NSWindow` + `cacheDisplay` 渲染设置窗口（`ImageRenderer` 画不出滚动区与按钮，按钮会变成禁止符占位）。`ENVPILOT_WINDOW_SNAPSHOT_UPDATE` 可注入 `available|downloading|latest|failed` 四种状态，主窗口快照用它验证侧边栏角标。
- `MenuBarSnapshot` 增加 `ENVPILOT_MENUBAR_SNAPSHOT_UPDATE=0.6.5`，用于验收菜单栏面板里的「更新到 …」那一行。
- 新增 `UpdateProbe`（`ENVPILOT_UPDATE_PROBE=check|stage|apply`）：这条链路可以真跑一遍——check 只查版本，stage 下到暂存目录并校验，apply 连替换一起做（`ENVPILOT_UPDATE_RELAUNCH=0` 时不重启）。`ENVPILOT_UPDATE_STAGING_ROOT` 可改写暂存目录。


## v0.6.4 - 2026-09-21

### 主窗口

- **左右两栏改用 AppKit 原生的 `NSSplitViewController`**（`Sources/NodePilotApp/NativeSidebarShell.swift`），替掉 SwiftUI 的 `NavigationSplitView`。原因：在这台机器（macOS 27）上它并不是原生实现——窗口视图树里一个 `NSSplitViewController` 都没有，只有 SwiftUI 自己拼的 `NSSplitView` + `_NSSplitViewItemViewWrapper`。那套折叠动画有两个毛病：
  - 动画没跑完再点一次**不会反向重定向**，而是把侧边栏一步弹到目标宽度。实测折叠到 121pt 时再点一次会直接跳到 190pt，并且内容列先被铺成全宽（`minX:width = 0:1100`）再跳回来，肉眼看就是「跳一下」。
  - 点标题栏那个开关会**直接改 AppKit 的 item**，绕过 SwiftUI 的 `columnVisibility` binding（在 binding 的 `set` 里把改动全部排队也拦不住）。
- 换成原生实现后，打断时动画会从当前位置反向：同样 8 次连点、间隔 120ms，实测 107 个采样点里**没有任何一步跳变**（宽度 212→110 再平滑回到 212），卡顿 0 次；而且点开关不再触发整页重算（`body` 求值次数 20 → 3）。
- 折叠开关是普通工具栏项 + 显式 target。**没有**用标准的 `NSToolbarItem.Identifier.toggleSidebar`：只要侧边栏那一栏是真正的 sidebar item，AppKit 就会把工具栏项摆到侧边栏右边界（实测 x=216），而不是紧跟红绿灯。现在按钮回到 x=76，与重做前一致。
- 视觉不变：侧边栏宽度、分隔线位置、四个页面的内容与重做前逐像素对齐（离屏快照对比，分隔线差 1px）。

### 工具

- `scripts/probe.sh auto` 增加 `ENVPILOT_PERF_TRIGGER=toolbar`：直接调用标准工具栏按钮的 target/action，是现在最接近手点的入口。`auto 16 700` 是平稳对照，`auto 8 120` 复现「动画没跑完又点一次」。
- 探针记录每一栏的 `minX:width`、`body` 求值次数、`FlatTitleBar` 压平次数，用来判断某项开销是否真的在折叠路径上。

## v0.6.3 - 2026-09-21

### 主窗口

- 修复「折叠动画没跑完再点一次折叠按钮会跳一下」。`NavigationSplitView` 的折叠动画由 AppKit 的 `NSSplitViewItem` 驱动：动画中途改列可见性不会反向动画，而是把侧边栏一步弹到目标宽度（实测从 115pt 直接回到 220pt），内容列还会先被铺成全宽（`minX:width = 0:1100`）再跳回来。新增 `SidebarToggleGuard`：在事件到达标题栏那个按钮**之前**，把动画进行中落在工具栏上的鼠标按下吞掉，让当前动画走完。判据用分隔条的位置（既不在收起位、也不在展开位），因此不依赖动画时长。
- 这条路径没法从 SwiftUI 侧拦：标题栏那个按钮会绕过 `columnVisibility` 的 binding 直接改 AppKit 的 `NSSplitViewItem`（在 binding 的 `set` 里把改动全部排队，界面照样被弹走），所以拦截点放在 local event monitor 上。

### 工具

- `scripts/probe.sh auto` 全自动量折叠动画：`auto 16 700` 是平稳对照，`auto 8 120` 复现上面那次「跳」。探针另记 `body` 求值次数、`FlatTitleBar` 压平次数与每一栏的 `minX:width`。

## v0.6.2 - 2026-09-20

### 主窗口

- 去掉窗口顶部那条横栏，主窗口回到纯粹的左右两列。`Window` 改用 `.windowStyle(.hiddenTitleBar)`，再配 `FlatTitleBarHost` 把标题栏设为透明、关掉 `titlebarSeparatorStyle`：标题栏下方那条分隔线原本把左右两栏又切了一刀，看起来就像多出一条顶部栏。现在侧边栏与内容列之间的分隔线从窗口顶端一路画到底。
- 页面标题与副标题不再进标题栏。页面身份由侧边栏选中的条目表达，顶部约 40pt 还给内容；`AppSection.subtitle` 随之删除。
- 刷新按钮移到侧边栏底部的状态区，⌘R 不变。状态文字与按钮各占一行，214pt 宽的侧边栏里「node 24.18.0 · java 17.0.20.1」和两个按钮都放得下，不再出现中间截断。
- 运行时页的搜索从 `.searchable(placement: .toolbar)` 改为筛选行里的内联 `SearchField`（`NSSearchField`），与运行时切换、「仅 LTS」同一行、与内容列同宽，不再单独占掉窗口顶部一条。
- 整页底色从系统灰底改成纯色：浅色纯白、深色纯黑。`windowBackgroundColor` 在浅色下是一层灰、深色下是一层中灰，整页像蒙了一层雾，而且它与 `controlBackgroundColor` 的差值太小，卡片边界和底色糊在一起。现在画布 / 分组表面 / 凹槽 / 描边都由 `DesignColor` 显式给色（`NSColor` 的 dynamic provider，绘制时按 appearance 取值），层次回到留白与描边上。
- 深色下分组表面抬起 5.5% 白，浅色不抬：白色卡片叠在白色画布上只会显出一圈脏边；深色下不抬则在纯黑上分不出卡片。
- 侧边栏去掉 sidebar 材质（`.scrollContentBackground(.hidden)` + 画布色背景），与内容列共用同一张白 / 黑台面；筛选行、预设保存栏、侧边栏状态区里的 `.background(.bar)` 一并换成画布色。设置窗口与菜单栏面板同步跟上（面板底色纯白 / 纯黑，深色下分区表面同样抬起 5.5% 白）。

### 菜单栏

- 修复面板展开后只剩一条细缝、什么都看不见的问题：移除面板根部的 `ScrollView`。`MenuBarExtra` 是按内容对「当前提议尺寸」的响应来决定窗口高度的，而 `ScrollView` 在纵轴上是贪婪的 —— 初次布局提议高度为 0，它就回答 0，整块面板随之塌陷。正文改为 `fixedSize` 固定高度后，摘要态约 300pt、展开态约 560pt，都在 620pt 预算之内；需要滚动的展开版本列表仍由 `expandedListHeight` 显式限高。
- 离屏快照改为渲染真实的 `MenuBarView`（含面板外观），不再绕开 `body` 只画正文：塌陷这类问题只出现在根部容器上，快照必须覆盖同一棵树才拦得住回归。

## v0.6.1 - 2026-09-12

### 概览页

- 生效版本号提升为每行的主视觉（圆角等宽数字 + 运行时配色），版本来源降为它下方的一行小字，不再和版本号平级争抢注意力。
- 运行时报行里的完整安装路径移除：该信息在下方「路径详情」中已有，重复且会占满整行。
- 卡片右上角的作用域只显示目录名，完整路径移入 tooltip。

### 菜单栏

- 收敛 `@ViewBuilder` 用法：显式 `return` 会导致结果构建器失效，改为等价写法消除编译警告。

## v0.6.0 - 2026-09-12

### Menu Bar

- Replaced the native menu with a custom `.window` panel: one row per runtime showing its effective version, its source (项目声明 / 全局默认) and a one-click version switcher.
- Expanding a row lists every installed version with its origin (ENVPilot 管理 / 系统安装), marks the current one, and collapses the panel after a switch. Runtimes with nothing installed are flagged instead of offering a dead end.
- The panel reports the active scope (global or a specific project path) and keeps window-level actions (main window, settings, quit) together. It refreshes itself when opened, so a stale version list is no longer possible.

### App Icon

- Replaced the translucent, glass-like icon with a flat geometric mark: a solid indigo squircle, a white terminal chevron and three runtime dots for Node / JDK / Python.
- The icon is generated from code (`scripts/generate_app_icon.py`) rather than shipped as a hand-drawn asset, so colours and geometry stay reproducible.

### Tooling

- Added `MenuBarSnapshot`: an offscreen `ImageRenderer` snapshot of the real menu bar panel, in light and dark, with an option to expand a runtime row. The menu bar popover cannot be captured with `screencapture` or driven by automation, so this is the review and regression path.
- Added `.github/workflows/release.yml`: pushing a `v*` tag runs the test suite, packages the app with the tag as `CFBundleShortVersionString`, verifies the bundle signature, and publishes `ENVPilot.dmg` plus `ENVPilot.zip` to a GitHub Release. Manual runs upload the artifacts without creating a release.
- `scripts/package_app.sh` now accepts `APP_VERSION` and `APP_BUILD` overrides.
- Rewrote the README around the menu bar panel, the four main window pages, the release pipeline and the reproducible tooling.

### App UI and UX

- Rebuilt the window shell on `NavigationSplitView`: real translucent sidebar, unified toolbar (refresh + ⌘R), per-page navigation title and subtitle. The previous hand-built `NSWindow` and the duplicate `Settings` scene rendering the same root view are gone, so ⌘, now opens a small dedicated settings window instead of a second main window.
- Collapsed seven sidebar destinations into four pages: 概览 / 运行时 / 项目 / 环境预设. Node, JDK and Python share one 运行时 page with a segmented switcher instead of three near-identical pages.
- Added an always-visible current-environment panel on 概览: one row per runtime with its resolved version, a 项目声明 / 全局默认 source marker and an inline version switcher, so the most frequent action (changing the version you are using) is one click from launch.
- Added a project inspector on the 项目 page: choose or paste a directory, see which versions its `.envpilot` declares, whether they are installed, and copy the command that applies them to the current terminal. Recently inspected folders are remembered.
- Downloadable versions now load automatically when a runtime page opens and can be refiltered locally; install progress and per-row state stay attached to the row that is working instead of a page-wide banner.
- Moved errors and confirmations into a persistent status strip above the bottom of the window, so feedback is never scrolled out of view.
- Removed the decorative layer (gradient page background, tinted card rails, material-filled status capsules, custom text-field chrome) in favour of system materials, hairline separators and standard controls.
- Shortened the menu bar item to a standalone icon, independent of the main window.

### Platform

- Raised the minimum deployment target to macOS 14 (`Package.swift`, `LSMinimumSystemVersion`) to use the newer window and menu primitives.

## v0.5.1 - 2026-09-11

### JDK Discovery and Installation

- Managed JDK installs now keep the full macOS `.jdk` bundle layout (`Contents/Info.plist`, `Contents/MacOS`) instead of extracting only `Contents/Home`, which previously produced bundles that `/usr/libexec/java_home` and other standard tooling could not enumerate.
- Added a symbolic-link discovery entry under `~/Library/Java/JavaVirtualMachines` pointing at the managed runtime, created on install and removed on uninstall. Runtime payloads stay under `~/.envpilot/runtimes/java`.
- Kept non-bundle archive layouts in the private runtime directory, so malformed entries are never published into the standard JVM directory.
- Extended JDK detection to the user-domain `~/Library/Java/JavaVirtualMachines` directory and to Gradle-provisioned JDKs under `~/.gradle/jdks`. A discovery entry and its private target are counted once.

## v0.5.0 - 2026-07-13

### App UI

- Added an app settings page for showing or hiding the ENVPilot menu bar entry.
- Kept the main window available from the Dock when the menu bar entry is hidden.
- Refreshed the README with clean application screenshots and updated installation, CLI, and development guidance.

### Runtime Reliability and Security

- Restricted runtime download URLs to HTTPS.
- Added request and resource timeouts for runtime metadata and archive downloads.
- Changed SHA-256 verification to stream large archives instead of loading them fully into memory.
- Added archive path validation to reject absolute paths and parent-directory traversal before extraction.
- Staged Python installations before replacing a managed runtime.
- Made managed runtime replacement recover the previous installation when the final move fails.
- Drained shell command stdout and stderr concurrently to prevent large-output deadlocks.
- Centralized shell single-quote escaping across runtime detection, profile exports, activation scripts, and installers.

### State Management and Tests

- Returned updated runtime snapshots directly from mutating service operations to avoid redundant reloads.
- Added installer safety, checksum, rollback, and shell output regression tests.
- Added a project-local build-and-run entry point and Codex Run configuration.

## v0.3.0 - 2026-07-07

### Runtime Management

- Added first-class Python support in ENVPilot.
- Added Python version discovery from the official Python distribution index.
- Python candidate lists now show Python 3.8+ only, with the latest patch release for each 3.x feature version.
- Python installs are managed by ENVPilot under `~/.envpilot/runtimes/python/<version>`.
- Python switching now exports `ENVPILOT_PYTHON_HOME` and prepends `$ENVPILOT_PYTHON_HOME/bin` to `PATH`.
- Project-level `.envpilot` files now support `PYTHON_VERSION` in addition to `NODE_VERSION` and `JAVA_VERSION`.
- Node, JDK, and Python runtime lists only show ENVPilot-managed installations.
- Node and JDK install flows no longer depend on SDKMAN, Homebrew, fnm, or nvm.
- Node candidates are fetched from the official Node distribution index.
- JDK candidates are fetched from Adoptium Temurin.
- Candidate searches support stable/LTS filtering and display only the latest release per major or feature version.
- Download and install progress now appears on the selected candidate row with percentage and transfer speed.
- Already installed candidates are marked before installation and cannot be downloaded again.

### App UI

- Refreshed the full app UI with a custom sidebar, clearer page headers, stronger card boundaries, and more visible input fields.
- Added a dedicated Python page alongside Node and JDK.
- Added Python status and selected path information to the overview.
- Removed the duplicate global progress banner so install progress is shown only where the operation is happening.
- Reworked installed runtime rows so the selected runtime shows a green `已选中` status in the action area instead of a redundant `切换` button.
- Standardized installed-row behavior across Node, JDK, and Python.
- Added ENVPilot badges to managed Node/JDK/Python rows.
- Improved search controls for installable versions with clearer input fields and switches.

### CLI

- Added `ep available py` / `envpilot-helper available py`.
- Added `ep install-python <version>`.
- Added `ep set-python <version-or-home-path>`.
- Added `ep list py`.
- Added `ep use py <version>` to write `PYTHON_VERSION` into project `.envpilot` files.
- Added config support for `selected-python-version`, `selected-python-home`, and `selected-python`.
- Extended status output with selected, active, and detected Python fields.

### Packaging

- Added app icon resources and updated packaging scripts to include the icon.
- Updated local install packaging so the app bundle, DMG, helper, and CLI are produced together.

### Notes

- Python installation builds CPython from official source packages. It does not use pyenv, Homebrew, uv, or other third-party runtime managers.
- Python source builds require the local macOS compiler toolchain and may take longer than Node or JDK installs.
