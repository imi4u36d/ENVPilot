import SwiftUI
import AppKit
import ENVPilotCore

// MARK: - 菜单栏面板

/// 菜单栏下拉面板（`.menuBarExtraStyle(.window)`）。
///
/// 信息层级自上而下：
/// 1. 标题与刷新状态；
/// 2. 三类运行时的当前生效版本，点击展开已安装版本列表完成切换；
/// 3. 作用域与终端生效提示；
/// 4. 主窗口 / 设置 / 退出等窗口级操作。
struct MenuBarView: View {
    @ObservedObject var store: NodeRuntimeStore
    @ObservedObject var updates: AppUpdateModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 固定面板宽度；离屏快照可复用同一套排版。
    static let panelWidth: CGFloat = 348
    /// 面板高度预算；正文按设计封顶在此以内（实测摘要态约 300，展开态约 560）。
    static let panelMaxHeight: CGFloat = 620

    /// 当前展开版本列表的运行时；`nil` 表示只展示摘要。
    /// 面板高度预算与宽度跟着系统文字大小走。正文本身不滚动（见 body 的注释），
    /// 所以预算必须一起长，否则大字号下页脚会被 `maxHeight` 直接裁掉。
    @ScaledMetric(relativeTo: .body) private var panelHeightScale: CGFloat = 1
    @ScaledMetric(relativeTo: .body) private var panelWidthScale: CGFloat = 1

    @State private var picking: RuntimeKind?
    @State private var didRequestRefresh = false
    @State private var operationError: String?

    /// 版本列表展开时最多占用的高度，超出后列表内部滚动。
    private static let expandedListHeight: CGFloat = 232
    /// 版本选项行高：与 `PickerRow` 保持一致，便于预先算出列表组高度。
    private static let pickerRowHeight: CGFloat = 28

    init(store: NodeRuntimeStore, updates: AppUpdateModel, initialPicking: RuntimeKind? = nil) {
        self.store = store
        self.updates = updates
        _picking = State(initialValue: initialPicking)
    }

    var body: some View {
        // 面板根部刻意不用 `ScrollView`：`MenuBarExtra` 是按内容对“当前（初次布局为 0）
        // 提议尺寸”的响应来决定窗口高度的，而 `ScrollView` 在纵轴上是贪婪的 ——
        // 提议高度为 0 时它回答 0，整个面板于是塌成一条细缝（啥也看不见）。
        // 正文本身高度确定（摘要态约 300，展开态约 560，均在 `panelMaxHeight` 以内），
        // 需要滚动的只有展开后的版本列表，由 `expandedListHeight` 显式限高。
        panelContent
            .frame(width: Self.panelWidth * panelWidthScale)
            .frame(maxHeight: Self.panelMaxHeight * panelHeightScale, alignment: .top)
            .fixedSize(horizontal: false, vertical: true)
            .panelChrome(colorScheme)
            .onAppear(perform: refreshIfNeeded)
    }

    /// 面板正文：标题、运行时、作用域与底部操作。面板外观（背景/描边）由 `body` 补上。
    private var panelContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            runtimeSection
            statusSection
            footer
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: 顶部

    private var header: some View {
        HStack(alignment: .center, spacing: 9) {
            Image(systemName: "terminal.fill")
                .font(.system(.subheadline, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
                .frame(width: 24, height: 24)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))

            Text("ENVPilot")
                .font(.headline)
                .foregroundStyle(.primary)

            Spacer(minLength: 6)

            if store.isBusy {
                HStack(spacing: 5) {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.7)
                    Text(store.progressMessage ?? "正在读取…")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .frame(maxWidth: 180, alignment: .trailing)
            } else if !store.lastRefreshSucceeded {
                Button {
                    Task { await store.refresh() }
                } label: {
                    Label("读取失败", systemImage: "exclamationmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(DesignColor.statusNegative)
                }
                .buttonStyle(.plain)
                .help("重新读取运行时状态")
                .accessibilityLabel("运行时状态读取失败，点击重试")
            } else {
                Label("已同步", systemImage: "checkmark.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(DesignColor.statusPositive)
                    .labelStyle(.titleAndIcon)
            }
        }
        .padding(.horizontal, 4)
    }

    // MARK: 运行时

    private var runtimeSection: some View {
        VStack(spacing: 0) {
            ForEach(Array(RuntimeKind.allCases.enumerated()), id: \.element.id) { index, kind in
                if index > 0 {
                    Divider().padding(.leading, 38)
                }
                runtimeRow(kind)
            }
        }
        .panelSection()
    }

    private func runtimeRow(_ kind: RuntimeKind) -> some View {
        let summary = store.summary(for: kind)
        let isExpanded = picking == kind
        let isSwitching = store.isBusy(key: "switch:\(kind.rawValue)")
        let versionText = summary.current.map { VersionLabel.display(kind, $0.version) } ?? summary.version
        // 归一化标签（JDK「8」）之外再补一行原始版本号，避免同一信息重复两次。
        let fullVersion = VersionLabel.display(kind, summary.version)
        let showsRawVersion = summary.current != nil && fullVersion != versionText

        return VStack(alignment: .leading, spacing: 0) {
            Button {
                operationError = nil
                if reduceMotion {
                    picking = isExpanded ? nil : kind
                } else {
                    withAnimation(.snappy(duration: 0.18)) {
                        picking = isExpanded ? nil : kind
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    kindBadge(kind, isActive: summary.current != nil)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(kind.title)
                                .font(.callout.weight(.medium))
                                .foregroundStyle(.primary)
                        }

                        if showsRawVersion {
                            Text(fullVersion)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }

                    Spacer(minLength: 8)

                    Group {
                        if isSwitching {
                            ProgressView().controlSize(.small)
                        } else {
                            versionPill(versionText, kind: kind, isEmpty: summary.options.isEmpty)
                        }
                    }
                    .layoutPriority(1)

                    Image(systemName: "chevron.down")
                        .font(.system(.caption2, weight: .semibold))
                        .foregroundStyle(DesignColor.tertiaryText)
                        .rotationEffect(.degrees(isExpanded ? 0 : -90))
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(store.isBusy)
            .accessibilityLabel("\(kind.title)，当前 \(versionText)")
            .accessibilityHint(summary.options.isEmpty ? "在运行时页安装版本" : "展开已安装版本列表")

            if isExpanded {
                pickerList(kind)
                    .transition(.opacity.combined(with: .move(edge: .top)))

                if let operationError, picking == kind {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(.caption))
                            .accessibilityHidden(true)
                        Text(operationError)
                            .font(.caption)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(DesignColor.statusNegative)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func pickerList(_ kind: RuntimeKind) -> some View {
        let summary = store.summary(for: kind)

        return VStack(alignment: .leading, spacing: 0) {
            // 已安装版本：独立成组，行数少时自适应高度，行数多时组内滚动。
            versionListGroup(summary)
                .padding(.horizontal, 6)

            // 生效版本缺失：给出明确解释，而不是静默停留在旧版本。
            if summary.current == nil, !summary.options.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(.caption2))
                        .accessibilityHidden(true)
                    Text("生效版本 \(VersionLabel.display(kind, summary.version)) 未安装")
                        .font(.caption2)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(DesignColor.statusWarning)
                .padding(.horizontal, 16)
                .padding(.top, 6)
            }

            Button {
                openMainWindow()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "gearshape.2")
                        .font(.system(.caption))
                        .accessibilityHidden(true)
                    Text("打开运行时页管理")
                        .font(.caption)
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.up.forward")
                        .font(.system(.caption2))
                        .accessibilityHidden(true)
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(PanelRowButtonStyle())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
        }
        // 给展开列表与下一行之间留出呼吸空间。
        .padding(.bottom, 10)
    }

    /// 版本列表组：行数少时直接用 `VStack`（离屏快照也能渲染），
    /// 超过限高时才套 `ScrollView` 组内滚动。
    @ViewBuilder
    private func versionListGroup(_ summary: RuntimeSummary) -> some View {
        if CGFloat(summary.options.count) * Self.pickerRowHeight > Self.expandedListHeight {
            ScrollView(.vertical) {
                versionList(summary)
                    .versionListGroupChrome(colorScheme)
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(height: Self.expandedListHeight, alignment: .top)
        } else {
            versionList(summary)
                .versionListGroupChrome(colorScheme)
        }
    }

    @ViewBuilder
    private func versionList(_ summary: RuntimeSummary) -> some View {
        if summary.options.isEmpty {
            HStack(spacing: 8) {
                Image(systemName: "shippingbox")
                    .font(.system(.subheadline))
                    .foregroundStyle(DesignColor.tertiaryText)
                    .accessibilityHidden(true)
                Text("尚未安装 \(summary.kind.title) 运行时")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(height: Self.pickerRowHeight)
        } else {
            VStack(spacing: 0) {
                ForEach(summary.options) { option in
                    PickerRow(
                        text: VersionLabel.display(summary.kind, option.version),
                        subtitle: option.isManaged ? "ENVPilot 管理" : "系统安装",
                        isSelected: option.id == summary.current?.id
                    ) {
                        operationError = nil
                        Task {
                            let succeeded = await store.selectDefault(option)
                            if succeeded {
                                // 选完才收起面板；失败时保留展开状态并就地显示错误。
                                dismiss()
                            } else {
                                operationError = store.statusMessage?.text ?? "切换版本失败，请稍后重试。"
                                picking = summary.kind
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: 生效提示

    /// 原来这里左边还有一行「当前作用域目录」，跟着项目作用域一起删掉了——版本只来自
    /// 全局选择，不存在「换个目录换个版本」，那行路径已经没有信息可言。
    private var statusSection: some View {
        Text("切换版本后，新开的终端才会用上")
            .font(.caption2)
            .foregroundStyle(DesignColor.tertiaryText)
            .padding(.horizontal, 4)
    }

    // MARK: 底部操作

    private var footer: some View {
        VStack(spacing: 0) {
            Divider()
                .padding(.bottom, 4)

            if let badge = updates.badgeText {
                // 已经知道有新版本：这一行就是「一键更新」，进度在设置窗口里看。
                footerRow(title: "更新到 \(badge)…", symbol: "arrow.down.circle") {
                    WindowActions.openSettings()
                    Task { await updates.install() }
                }
            } else {
                footerRow(title: "检查更新…", symbol: "arrow.triangle.2.circlepath") {
                    Task { await UpdatePrompter.checkAndPresent(model: updates) }
                }
            }

            footerRow(title: "打开 ENVPilot 主窗口", symbol: "macwindow", action: openMainWindow)
            footerRow(title: "设置…", symbol: "gearshape", shortcut: "⌘,") {
                WindowActions.openSettings()
            }
            footerRow(title: "退出 ENVPilot", symbol: "power", shortcut: "⌘Q") {
                NSApp.terminate(nil)
            }
        }
        .panelSection()
    }

    private func footerRow(
        title: String,
        symbol: String,
        shortcut: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(.subheadline, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                    .accessibilityHidden(true)

                Text(title)
                    .font(.callout)
                    .foregroundStyle(.primary)

                Spacer(minLength: 8)

                if let shortcut {
                    Text(shortcut)
                        .font(.caption2.monospaced())
                        .foregroundStyle(DesignColor.tertiaryText)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(PanelRowButtonStyle())
    }

    // MARK: 小组件

    private func kindBadge(_ kind: RuntimeKind, isActive: Bool) -> some View {
        Image(systemName: kind.symbol)
            .font(.system(.callout, weight: .medium))
            .foregroundStyle(isActive ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
            .frame(width: 22, height: 22)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(panelWell(colorScheme).opacity(isActive ? 1 : 0.6))
            )
            // 装饰性字形：旁边的文字已经说明了是哪个运行时。
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private func versionPill(_ text: String, kind: RuntimeKind, isEmpty: Bool) -> some View {
        if isEmpty {
            Pill("未安装", tone: .warning, symbol: "arrow.down.circle")
        } else if text == RuntimeSummary.emptyVersion {
            Pill("未选择", tone: .warning)
        } else {
            Pill(text, tone: .neutral)
        }
    }

    // MARK: 行为

    private func refreshIfNeeded() {
        guard !didRequestRefresh else {
            return
        }
        didRequestRefresh = true
        Task { await store.refresh() }
    }

    private func openMainWindow() {
        picking = nil
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - 版本选项行

private struct PickerRow: View {
    let text: String
    let subtitle: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                // 未选中时以前用 `.clear` 把勾藏起来：选中态只剩颜色，色觉障碍用户
                // 看不出选了哪个。留一个占位勾，选中时再上色。
                Image(systemName: "checkmark")
                    .font(.system(.caption, weight: .bold))
                    .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear))
                    .frame(width: 12)
                    .accessibilityHidden(true)

                Text(text)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.primary)
                    .fontWeight(isSelected ? .semibold : .regular)

                Spacer(minLength: 8)

                Text(subtitle)
                    .font(DesignType.micro)
                    .foregroundStyle(DesignColor.tertiaryText)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(PanelRowButtonStyle())
        .help("切换到 \(text)")
        .accessibilityLabel("\(text)，\(subtitle)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

// MARK: - 面板样式

/// 面板外观令牌。非 private：离屏快照（`MenuBarSnapshot`）需要复用同一套外观。
enum PanelChrome {
    static let cornerRadius: CGFloat = 12

    /// 行悬停高亮。
    static var rowHighlight: Color {
        DesignColor.hover
    }
}

/// 面板底色：按 `colorScheme` 显式取色。
///
/// 面板外观刻意不用语义 NSColor（`.windowBackgroundColor` / `.controlBackgroundColor`）：
/// 视觉与正常窗口一致，同时离屏快照（`ImageRenderer`）也能正确呈现深浅色。
/// `scheme` 显式传入而非只依赖环境：`background` 修饰符内的环境在离屏渲染下不可靠。
/// 取值与主窗口的 `DesignColor` 保持一致：浅色纯白、深色纯黑。
private struct PanelBackground: View {
    let scheme: ColorScheme

    var body: some View {
        scheme == .dark ? Color(white: 0.075) : Color(white: 0.985)
    }
}

private struct PanelSection: ViewModifier {
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        return content
            .background(scheme == .dark ? Color(white: 0.11) : Color(white: 1), in: shape)
            .overlay {
                shape.strokeBorder(panelHairline(scheme), lineWidth: 1)
            }
    }
}

/// 面板描边。`DesignColor.hairline` 自己按外观（含「提高对比度」）取色，
/// 所以这里不需要再按 `scheme` 分支——原注释说「深色下更亮」但实现忽略入参，
/// 是注释与代码不一致，这里改成如实描述。
private func panelHairline(_ scheme: ColorScheme) -> Color {
    _ = scheme
    return DesignColor.hairline
}

/// 面板里的中性凹槽 / 徽章底色。与主窗口的 `DesignColor.well` 同值，
/// 但同样按 `scheme` 显式取色，理由同 `PanelBackground`。
private func panelWell(_ scheme: ColorScheme) -> Color {
    DesignColor.well
}

/// 面板内的裸行按钮：悬停高亮 + 按下反馈 + 键盘焦点环。
private struct PanelRowButtonStyle: ButtonStyle {
    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isFocused) private var isFocused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isHovering ? PanelChrome.rowHighlight : Color.clear)
            )
            .overlay {
                // 以前这条键盘路径完全没有焦点提示，Tab 到哪一行看不出来。
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(
                        isFocused ? DesignColor.primaryAction.opacity(0.92) : .clear,
                        lineWidth: 2
                    )
            }
            .opacity(configuration.isPressed ? 0.72 : 1)
            .onHover { hovering in
                if reduceMotion {
                    isHovering = hovering
                } else {
                    withAnimation(.easeOut(duration: 0.12)) {
                        isHovering = hovering
                    }
                }
            }
    }
}

private extension View {
    func panelSection() -> some View {
        modifier(PanelSection())
    }

    /// 展开列表里那层浅凹槽背景。
    func versionListGroupChrome(_ scheme: ColorScheme) -> some View {
        frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .background(DesignColor.well)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

extension View {
    /// 面板外观：背景、圆角与描边。菜单栏面板与离屏快照共用。
    func panelChrome(_ scheme: ColorScheme) -> some View {
        background(PanelBackground(scheme: scheme))
            .clipShape(RoundedRectangle(cornerRadius: PanelChrome.cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: PanelChrome.cornerRadius, style: .continuous)
                    .strokeBorder(panelHairline(scheme), lineWidth: 1)
            }
    }
}
