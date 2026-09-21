# Changelog

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
