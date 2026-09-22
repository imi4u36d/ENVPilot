# ENVPilot 修复报告（hig-doctor 审计 → 全部落地）

> 完成：2026-09-22 · 审计工具：hig-doctor 2.0.3（本地 skill，见附录）
> 范围：`docs/hig-optimization-checklist.md` 里的 34 条 + 执行过程中新发现的 5 条

## 一、结果

| 指标 | 修复前 | 修复后 |
| --- | ---: | ---: |
| hig-doctor concerns | **95** | **0**（16 项已知误报/刻意选择进 baseline） |
| critical / serious | 0 / 0 | 0 / 0 |
| positives（正向模式） | 276 | **325** |
| 组件用法 patterns | 140 | 145 |
| `swift/hardcoded-font-size` | 43 | 0（3 项比例缩放的徽章图标进 baseline） |
| `swift/hardcoded-rgbcolor` | 13 | **0** |
| `swift/image-without-a11y` | 37 | 11（全部为规则误报，见 §3） |
| `swift test` | 82 通过 | **105 通过 / 0 失败** |
| `swift build` && `swift build -c release` | — | 均通过，**0 warning** |

发布构建已确认探针被剥离：debug 产物含 `ENVPILOT_PERF_PROBE` 字面量，release 产物为 0（release 5.56 MB / debug 9.52 MB）。

## 二、逐项修复

### P0（8 项，全部完成）

| # | 问题 | 落地位置 |
| --- | --- | --- |
| 1 | 菜单栏图标对 VoiceOver 无名 | `MenuBarIcon.swift` 设 `accessibilityDescription`；`NodePilotApp.swift` label 加 `.accessibilityLabel("ENVPilot")` |
| 2 | 缺排版令牌、43 处硬编码字号 | 新增 `DesignType`（`DesignKit.swift`）+ 40 处替换为语义样式；3 处徽章图标改 `@ScaledMetric` 比例缩放；`AppButtonSize` 字号与最小高度随之缩放；`OverviewView` 大号版本号 `minWidth` + `minimumScaleFactor`；`RuntimesView` 搜索框去掉写死 250×24 |
| 3 | 长任务无超时、取消杀不掉子进程 | `ShellCommandRunner` 重写：墙钟超时（默认 30 min / 构建 60 min，超时返回退出码 124 + `timedOut`）、`proc_listchildpids` 递归杀整棵进程树（SIGTERM→SIGKILL）、`stdin` 置空、管道读取幂等；`NodeRuntimeStore` 补齐取消令牌并透传 Core |
| 4 | 行内动作缺 busy 守卫、加载期显示错误状态 | `PackageManagersView` 三个按钮补 `.disabled(store.isLoading \|\| store.isBusy(kind))`；两页首屏用 `.redacted(.placeholder)` |
| 5 | 取消把行永久钉在「正在取消」 | `AIEnvironmentStore` / `PackageManagerStore` 的 `cancelOperation` 前置 `guard isBusy` |
| 6 | 选「稍后」也被拽到设置窗口等 | `UpdatePrompter`：「已是最新」不弹窗、只在选「更新」时开设置、失败弹窗用 `.warning`、`runModal` 改 sheet、`activate(ignoringOtherApps:)` 改 `activate()`、`.none` 分支补反馈 |
| 7 | 设置页开关不对齐 / 窗口写死 / 嵌套滚动 | 新增 `SettingsToggleRow`（文案左、控件贴行尾）；`.frame(minWidth:minHeight:)` 允许缩放；去掉激活脚本与变更日志的内层 `ScrollView`；`ENVPilot dev` → `版本 0.6.7`；删掉与窗口标题重复的「设置」 |
| 8 | 「提高对比度」完全没适配 | `DesignColor.adaptive` 新增 `AppearanceAxis`，识别 `.accessibilityHighContrast*` 四档；半透明填充加深、中性灰更极端；选中色、品牌色各给高对比档 |

### P1（14 项，全部完成）

| # | 问题 | 落地位置 |
| --- | --- | --- |
| 9 | 环境检查诊断文本被截断 | 去掉 `check.detail` / `repairHint` 的 `lineLimit(1)` |
| 10 | 修复中无法取消、无阶段进度、每次重扫 | `repairStage` 透传 `progress:`；`cancelRepair()`（令牌注入真正耗时的 Node 安装）；`defer` 清理 busy；报告 60s TTL；视图侧已接「取消配置」按钮与阶段文字 |
| 11 | 颜色令牌没收干净 | 13 处 RGB 走新增的 `DesignColor.brandTint`（浅/深/高对比四档）；`MenuBarView` 的 `Color(white:)` 与注释不符已改为如实描述 |
| 12 | 中性胶囊对比度 ≈4.0:1 | `.neutral` 文字由 `.secondary` 改为 `Color.primary.opacity(0.78)` |
| 13 | 选中态只靠颜色 | 版本选项行保留占位勾 + 选中加粗 + `.isSelected` trait；侧边栏选中同样补非颜色线索 |
| 14 | 自定义按钮样式无焦点环 | `SelectableRowStyle` / `PanelRowButtonStyle` 补 `isFocused` 描边 |
| 15 | 重复按钮文案无上下文 | 「设为默认」带版本号；「安装」补 `accessibilityLabel` |
| 16 | 硬编码 230pt 动作列 | 全部改 `minWidth`（PM 6 处 + AI 5 处） |
| 17 | 菜单栏面板大字号被裁 | 面板宽高预算改 `@ScaledMetric`，跟着系统文字大小一起长 |
| 18 | 快捷键与菜单状态 | ⌘1–⌘4 切页（`FocusedValue` 注入）；「切换侧边栏」标题随折叠状态变化；「检查并修复本地环境」补菜单项 |
| 19 | 侧边栏宽度/折叠状态不持久 | `autosaveName` + 折叠状态持久化，只在首次启动套用设计宽度 |
| 20 | 路径动作静默失败 | `revealInFinder` 返回 `Bool` + `isUsablePath`，空路径禁用菜单项；`ValueRow` 被禁用的按钮补 `.help` 说明原因 |
| 21 | 关键错误只在底栏 | 新增 `StatusBanner`：error 走顶部横幅，成功/提示留底栏（三处页面统一） |
| 22 | 「恢复默认」立即提交 | 改为只清空输入框，提交交给「保存」 |

### P2（12 项，全部完成）

| # | 问题 | 落地位置 |
| --- | --- | --- |
| 23 | 静默删用户二进制 | `removeStandaloneInstallation` 改 `trashItem` 并返回被挪走的路径；`cleanupNotice` 已接进成功提示（PM 三处状态文案） |
| 24 | `settings.json` 损坏被当成「没有设置」、读操作会写盘 | `load()` 不再写盘；损坏文件重命名为 `.corrupt-<ts>` 并回报 `ConfigStoreWarning`；新增 mtime+size 缓存与 `update` / `updateWithDiagnostics` 原子读改写 |
| 25 | 整体重写 `~/.zshrc` 无备份 | 改写前备份 `.envpilot-backup-<ts>`，保留 posix 权限/属主，内容未变则完全不写 |
| 26 | 远程脚本 `curl \| sh` | 统一走 `remoteScriptPlan`：下载到临时文件 → 非空校验 → 必须是脚本 → 再执行；npm 那条同时补了 `-f` |
| 27 | npm 安装脚本缺 `-f` | 同上（`curl -fsSL`） |
| 28 | Python 安装无校验和 | `verifyPythonArchive`：先试 `<archive>.md5`，404 则走 python.org 官方 downloads API 取 `md5_sum`，用 CryptoKit 真校验；取不到才显示「未校验」 |
| 29 | 版本列表 N+1 网络请求 | Java 改并发（上限 4、保序）；Python 直接拼可预测 URL + 一次 HEAD 确认，失败才回退 HTML 探测 |
| 30 | 重复进程调用 / 进度洪水 | PM 与 AI 两个服务各加 `DetectionCache` + `StageDeduplicator`；`NodeRuntimeStore` 外提 installations；`ConfigStore` 加载加缓存 |
| 31 | 探针进发布构建 + `body` 副作用 | 4 个探针文件整体 `#if DEBUG`（release 提供空实现），`RootView`/`OverviewView`/`DesignKit`/`NativeSidebarShell` 的探针调用点同样只在调试构建求值 |
| 32 | 轮询代替等待 | `BoundedAwait` + 串行闸门：刷新会排队执行而不是 2 秒后静默丢弃；AI 扫描改 await 在途任务 |
| 33 | 启动 3 秒自动联网 / 首启弹窗 | 保留（有设置开关兜底、首启检查是产品流程），已在 §4 记录为刻意选择 |
| 34 | UI 层零测试 | 新增 CI：`.github/workflows/hig-audit.yml`（钉版本、SARIF 上传 code scanning、`--fail-on critical` 门槛）+ `.higauditignore` + `.hig-baseline.json` + `docs/hig-optimization-checklist.md` |

### 执行过程中新发现并修掉的 5 条

| 问题 | 落地位置 |
| --- | --- |
| 200MB 更新下载的「取消」是假的（只是不等它） | `ShellCommandCancellation.registerCancellationHandler` + `AppUpdateService.downloadFile` 注册 `session.invalidateAndCancel()`；`AppUpdateModel` 持有令牌，取消即真的掐断传输 |
| 被挪进废纸篓的 `pnpm`/`uv` 没人告诉用户 | `PackageManagerStore.cleanupSuffix` 把 `cleanupNotice` 拼进成功提示（install / update / switch 三处） |
| Core 的 `update` 内部 `try?` 吞掉损坏警告 | 新增 `updateWithDiagnostics`，`PackageManagerStore` 改用并把警告显示出来 |
| `PackageManagerStore.refreshIfNeeded()` 永不过期 | 加 `loadedAt` + 60s TTL（与 AI store 一致） |
| 点 Dock 图标找不回主窗口 | `MainWindowPresenter` + `applicationShouldHandleReopen`（关掉菜单栏入口又关主窗口时，Dock 是唯一入口） |

## 三、进了 baseline 的 16 项（不改，并已写明理由）

`.hig-baseline.json` 记录 16 条，CI 只挡**新增**问题。逐条理由：

- **11 × `image-without-a11y`（规则误报）**：`AIEnvironmentsView:258`、`PackageManagersView:248/261`、`RuntimesView:180`、`DesignKit:1394/1404/1515/1580`、`RootView:227/236` 都已在**按钮级**给了 `.accessibilityLabel`；`RootView:168` 的品牌图标由父容器 `.accessibilityHidden(true)` 兜住。规则只看 `Image` 本身，看不到按钮或父级的标签——**批量补 label 反而会把已正确的朗读覆盖成冗余**。
- **3 × `hardcoded-font-size`**：三个运行时/AI/包管理器徽章内的图标，尺寸 = 徽章边长 × 0.42–0.46 × `@ScaledMetric`。这是**比例缩放**，不是固定字号；写成令牌反而失真。
- **1 × `appkit/hardcoded-nscolor-constant`**：`MenuBarIcon.swift` 的 `NSColor.black` 是模板图（`isTemplate = true`）的前景墨色，由系统染色——**正确用法**。
- **1 × `ignores-safe-area`**：`RootView.swift` 隐藏标题栏布局的刻意选择，配合 `.flatTitleBar()` 与 32pt 顶部留白避让红绿灯。

## 四、没做 / 留给你决定的事（诚实清单）

1. **本地化**（清单 HIG-11）：UI 层 412 处中文仍是硬编码，`NSLocalizedString` 0 处。这是**产品决定**（要么明确「仅中文」并去掉多语言声明，要么做 L 级的 `L10n` 迁移），不是能顺手改的技术债，所以没有动。
2. **Zulu JDK 仍无校验和**：Node 验 `SHASUMS256`、Python 已接官方 md5，Zulu 的候选仍未校验（Azul 的分发元数据里没有稳定可取的 hash）。需要你确认是否接受，或指定校验源。
3. **64 位/HEAD 引用的远程安装脚本无法钉 SHA**：npm/pnpm/uv/Homebrew 的安装脚本 URL 都是 `latest`/`HEAD`。当前保证是「完整下载并确认是可执行脚本后才运行」（已实机用有效脚本/空文件/HTML/`exit 3` 四种情况验证），但做不到内容 pinning。要彻底解决只能把这些安装器 vendored 进来。
4. **运行时「卸载」还不能中途取消**：Core 的 `uninstallManagedNode/Java/Python` 未加 `cancellation` 参数（本地删目录，秒级完成）。安装/切换/更新已可取消。
5. **启动 3 秒后自动查更新、首启弹出环境检查**：保留原行为（有「每天自动检查更新」开关兜底）。
6. **`CommandGroup(replacing: .help)` 与 `MenuBarExtra` 默认开启**：保留原设计并已在代码注释里说明理由（Help 搜索无内容可搜；菜单栏面板是这个 App 的主入口，默认关掉等于藏起主功能）。
7. **未做视觉/VoiceOver 实机验收**：本轮只做了编译、单测、静态审计与 shell 行为实测。字号迁移、开关对齐、顶部错误横幅、大字号下面板表现这些**需要真机看一眼**；`artifacts/` 里的截图是改动前的，没有重新生成（旧截图现在已过时，别再当作现状参考）。

## 五、验证方式（可复现）

```bash
swift build && swift build -c release && swift test          # 全绿，0 warning，105 tests
node "$HOME/.agents/skills/hig-doctor-audit/scripts/hig-doctor/dist/index.js" . --json   # concerns: 0
node "$HOME/.agents/skills/hig-doctor-audit/scripts/hig-doctor/dist/index.js" . --baseline .hig-baseline.json --fail-on critical  # CI 门槛 clean
```

新增测试覆盖（共 +23）：`ShellCommandRunnerTests` 补超时/退出码 124/超时杀子孙/取消杀子孙/stdin 关闭；`ConfigStoreTests` 新增 5 条（读不写盘、损坏隔离、原子读改写等）；`PackageManagerServiceTests` / `RuntimeComponentInstallerTests` / `EnvironmentSetupServiceTests` / `NodeEnvironmentServiceTests` 由 Core 流补充下载校验、废纸篓、阶段去重、zshrc 备份、md5 校验、陈旧清理、取消透传等。

## 六、改动规模

39 个文件、+3,975 / −583 行；新增 5 个文件：`.github/workflows/hig-audit.yml`、`.higauditignore`、`.hig-baseline.json`、`Tests/NodePilotCoreTests/ConfigStoreTests.swift`、`docs/hig-optimization-checklist.md`。

**未提交**：所有改动都留在工作区，没有 commit，方便你先 review 再决定怎么切分提交。

---

## 附录 · hig-doctor 本地 skill 安装记录

- 位置：`~/.agents/skills/`（DSH 用户级 skill 根，与 `confluence-fetch` / `jetbrains-db` / `sql-rollback-log` 同级）
- 内容：上游 14 个 HIG 指导包 + `hig-doctor-audit`，含 156 个 HIG 参考主题（约 1.0 MB）
- 本机适配（唯一的上游改动）：本机只有 Node 24.17.0、无 `npx`/npm，因此把 npm 的 `hig-doctor@2.0.3` 打进 `hig-doctor-audit/scripts/hig-doctor/`（`VENDOR.md` 记录版本、来源与三项 sha256），`SKILL.md` 里加 fallback：优先 `npx`，不可用就跑同版本本地副本。
- 移除：`rm -rf ~/.agents/skills/hig-*`
- 上游：<https://github.com/raintree-technology/hig-doctor>（MIT；HIG 参考文本版权归 Apple Inc.）
