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
    @Environment(\.openWindow) private var openWindow
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    /// 固定面板宽度；离屏快照可复用同一套排版。
    static let panelWidth: CGFloat = 336
    /// 面板最高高度，超出后在面板内滚动。
    static let panelMaxHeight: CGFloat = 620

    /// 当前展开版本列表的运行时；`nil` 表示只展示摘要。
    @State private var picking: RuntimeKind?
    @State private var didRequestRefresh = false

    /// 版本列表展开时最多占用的高度，超出后列表内部滚动。
    private static let expandedListHeight: CGFloat = 232
    /// 版本选项行高：与 `PickerRow` 保持一致，便于预先算出列表组高度。
    private static let pickerRowHeight: CGFloat = 28

    init(store: NodeRuntimeStore, initialPicking: RuntimeKind? = nil) {
        self.store = store
        _picking = State(initialValue: initialPicking)
    }

    var body: some View {
        ScrollView(.vertical) {
            panelContent
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(width: Self.panelWidth)
        .frame(maxHeight: Self.panelMaxHeight)
        .panelChrome(colorScheme)
        .onAppear(perform: refreshIfNeeded)
    }

    /// 面板正文。独立于 `ScrollView`，便于离屏快照直接渲染（`ImageRenderer`
    /// 不会绘制 `ScrollView` 的内容）。
    var panelContent: some View {
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
        HStack(alignment: .firstTextBaseline, spacing: 8) {
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
            } else {
                Label("已同步", systemImage: "checkmark.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(.green)
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
                withAnimation(.snappy(duration: 0.18)) {
                    picking = isExpanded ? nil : kind
                }
            } label: {
                HStack(spacing: 10) {
                    kindBadge(kind, isActive: summary.current != nil)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(kind.title)
                                .font(.callout.weight(.medium))
                                .foregroundStyle(.primary)

                            if summary.current != nil, summary.source != .none {
                                Pill(summary.source.label, tone: sourceTone(summary.source))
                            }
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
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 0 : -90))
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
                        .font(.system(size: 9))
                    Text("生效版本 \(VersionLabel.display(kind, summary.version)) 未安装")
                        .font(.caption2)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.orange)
                .padding(.horizontal, 16)
                .padding(.top, 6)
            }

            Button {
                openMainWindow()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "gearshape.2")
                        .font(.system(size: 10))
                    Text("打开运行时页管理")
                        .font(.caption)
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.up.forward")
                        .font(.system(size: 9))
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
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
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
                        picking = nil
                        // 选完即收起面板；`.window` 样式下 `dismiss()` 即为关闭弹层。
                        dismiss()
                        Task { await store.selectDefault(option) }
                    }
                }
            }
        }
    }

    // MARK: 作用域与状态

    private var statusSection: some View {
        HStack(spacing: 6) {
            Text(store.inspectedDirectory.map(abbreviated) ?? "全局默认作用域")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(store.inspectedDirectory?.path ?? "全局默认作用域")
                .layoutPriority(1)

            Spacer(minLength: 6)

            Text("新终端生效")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 4)
    }

    // MARK: 底部操作

    private var footer: some View {
        VStack(spacing: 0) {
            Divider()
                .padding(.bottom, 4)

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
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)

                Text(title)
                    .font(.callout)
                    .foregroundStyle(.primary)

                Spacer(minLength: 8)

                if let shortcut {
                    Text(shortcut)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.tertiary)
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
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(isActive ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
            .frame(width: 22, height: 22)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(DesignColor.hairline.opacity(isActive ? 0.28 : 0.16))
            )
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

    private func abbreviated(_ url: URL) -> String {
        url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }

    private func sourceTone(_ source: VersionSource) -> Pill.Tone {
        switch source {
        case .projectFile:
            return .informative
        case .global:
            return .neutral
        case .none:
            return .warning
        }
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
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear))
                    .frame(width: 12)

                Text(text)
                    .font(.caption.monospaced())
                    .foregroundStyle(.primary)

                Spacer(minLength: 8)

                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .frame(height: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(PanelRowButtonStyle())
        .help("切换到 \(text)")
    }
}

// MARK: - 面板样式

/// 面板外观令牌。非 private：离屏快照（`MenuBarSnapshot`）需要复用同一套外观。
enum PanelChrome {
    static let cornerRadius: CGFloat = 10

    /// 行悬停高亮。
    static var rowHighlight: Color {
        Color.primary.opacity(0.09)
    }
}

/// 面板底色：按 `colorScheme` 显式取色。
///
/// 面板外观刻意不用语义 NSColor（`.windowBackgroundColor` / `.controlBackgroundColor`）：
/// 视觉与正常窗口一致，同时离屏快照（`ImageRenderer`）也能正确呈现深浅色。
/// `scheme` 显式传入而非只依赖环境：`background` 修饰符内的环境在离屏渲染下不可靠。
private struct PanelBackground: View {
    let scheme: ColorScheme

    var body: some View {
        // 浅色下比纯白略暗一点，避免整个面板与白色卡片糊在一起。
        scheme == .dark ? Color(white: 0.13) : Color(white: 0.965)
    }
}

private struct PanelSection: ViewModifier {
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        return content
            .background(scheme == .dark ? Color(white: 0.17) : Color(white: 1), in: shape)
            .overlay {
                shape.strokeBorder(panelHairline(scheme), lineWidth: 1)
            }
    }
}

/// 面板描边：深色下需要比窗口分隔线更亮，否则卡片边界消失。
private func panelHairline(_ scheme: ColorScheme) -> Color {
    scheme == .dark ? Color(white: 1, opacity: 0.14) : Color(white: 0, opacity: 0.12)
}

/// 面板内的裸行按钮：悬停高亮 + 按下反馈。
private struct PanelRowButtonStyle: ButtonStyle {
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isHovering ? PanelChrome.rowHighlight : Color.clear)
            )
            .opacity(configuration.isPressed ? 0.72 : 1)
            .onHover { hovering in
                withAnimation(.easeOut(duration: 0.12)) {
                    isHovering = hovering
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
            .background(scheme == .dark ? Color(white: 1, opacity: 0.05) : Color(white: 0, opacity: 0.045))
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
