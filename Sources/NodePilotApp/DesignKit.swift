import AppKit
import ENVPilotCore
import SwiftUI

// MARK: - Navigation model

enum AppSection: String, CaseIterable, Identifiable, Hashable {
    case overview
    case runtimes
    case projects
    case profiles

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview:
            return "概览"
        case .runtimes:
            return "运行时"
        case .projects:
            return "项目"
        case .profiles:
            return "环境预设"
        }
    }

    var symbol: String {
        switch self {
        case .overview:
            return "gauge.with.dots.needle.67percent"
        case .runtimes:
            return "square.stack.3d.up"
        case .projects:
            return "folder"
        case .profiles:
            return "slider.horizontal.3"
        }
    }

    /// 侧边栏分组标题。分组让四项导航有结构，而不是一条平铺的列表。
    var groupTitle: String {
        switch self {
        case .overview, .runtimes:
            return "环境"
        case .projects, .profiles:
            return "项目与预设"
        }
    }

    static var grouped: [(title: String, sections: [AppSection])] {
        var order: [String] = []
        var buckets: [String: [AppSection]] = [:]
        for section in allCases {
            if buckets[section.groupTitle] == nil {
                order.append(section.groupTitle)
            }
            buckets[section.groupTitle, default: []].append(section)
        }
        return order.map { ($0, buckets[$0] ?? []) }
    }
}

enum RuntimeKind: String, CaseIterable, Identifiable, Hashable {
    case node
    case java
    case python

    var id: String { rawValue }

    var title: String {
        switch self {
        case .node:
            return "Node.js"
        case .java:
            return "JDK"
        case .python:
            return "Python"
        }
    }

    var commandName: String {
        switch self {
        case .node:
            return "node"
        case .java:
            return "java"
        case .python:
            return "python3"
        }
    }

    var symbol: String {
        switch self {
        case .node:
            return "shippingbox"
        case .java:
            return "cup.and.saucer"
        case .python:
            return "curlybraces"
        }
    }

    var filterTitle: String {
        switch self {
        case .node, .java:
            return "仅 LTS"
        case .python:
            return "仅稳定版"
        }
    }

    var searchPrompt: String {
        switch self {
        case .node:
            return "筛选版本，例如 22 或 LTS 名称"
        case .java:
            return "筛选版本，例如 21、17 或 Temurin"
        case .python:
            return "筛选版本，例如 3.13 或 3.12"
        }
    }
}

// MARK: - Window commands

@MainActor
enum WindowActions {
    static func openSettings() {
        for name in ["showSettingsWindow:", "showPreferencesWindow:"] {
            if NSApp.sendAction(Selector((name)), to: nil, from: nil) {
                return
            }
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    static func copy(_ text: String) {
        guard !text.isEmpty else {
            return
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}

// MARK: - Layout tokens

/// 全局尺寸令牌。整页只用这几个数值，避免每处各写一个魔数。
enum Metric {
    /// 正文最大宽度。超宽窗口下居中，而不是让右侧留一大片空白。
    static let pageMaxWidth: CGFloat = 1000
    static let pagePadding: CGFloat = 24
    /// 分组的间距：比组内行距明显大一档，层次靠留白而不是靠边框。
    static let sectionSpacing: CGFloat = 22

    static let groupRadius: CGFloat = 10
    static let controlRadius: CGFloat = 7
    static let groupPadding: CGFloat = 14

    static let rowPadding: CGFloat = 14
    static let rowVerticalPadding: CGFloat = 11
    /// 分隔线缩进：与行首图标的中心对齐，读起来像一条连续的分组。
    static let rowDividerInset: CGFloat = 14

    static let badgeSize: CGFloat = 30
}

// MARK: - Color tokens

/// 页面灰阶。
///
/// 整页只用「纯白 / 纯黑」两套底色，不再借用系统的灰底：
/// `windowBackgroundColor` 在浅色下是一层灰、深色下是一层中灰，整页看起来像蒙了雾，
/// 而且它与 `controlBackgroundColor` 的差值太小，卡片边界和底色糊在一起。
/// 这里把画布定成纯白（深色纯黑），层次改由 **留白 + 1px 描边** 表达。
///
/// 颜色一律用 `NSColor` 的 dynamic provider 在绘制时按当前 appearance 取值，
/// 因此 `background`、`strokeBorder` 以及离屏快照（`cacheDisplay`）都能拿到正确的深浅色。
enum DesignColor {
    /// 页面画布。
    static let canvas = adaptive(.white, .black)

    /// 分组表面。浅色与画布同为纯白，只靠描边划界；深色抬到 5.5% 白，
    /// 保证卡片仍能从纯黑画布里浮出来。
    static let group = adaptive(.white, gray(0.055))

    /// 兼容旧调用点。
    static var surface: Color {
        group
    }

    /// 分组内的凹槽：导出脚本、路径条。比卡片深一档，但仍不与画布争层次。
    static let well = adaptive(gray(0, alpha: 0.04), gray(1, alpha: 0.06))

    /// 描边。底色相同，卡片边界全靠这一条线，因此比系统分隔线略实。
    static let hairline = adaptive(gray(0, alpha: 0.11), gray(1, alpha: 0.14))

    static var hairlineShape: some View {
        RoundedRectangle(cornerRadius: Metric.groupRadius, style: .continuous)
            .strokeBorder(hairline, lineWidth: 1)
    }

    /// 分组表面形状，供背景与描边复用。
    static var groupShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Metric.groupRadius, style: .continuous)
    }

    /// 深浅色各给一档灰阶。
    private static func adaptive(_ light: NSColor, _ dark: NSColor) -> Color {
        let color = NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return isDark ? dark : light
        }
        return Color(nsColor: color)
    }

    private static func gray(_ white: CGFloat, alpha: CGFloat = 1) -> NSColor {
        NSColor(white: white, alpha: alpha)
    }
}

// MARK: - Window chrome

/// 主窗口的标题栏配置。
///
/// `.windowStyle(.hiddenTitleBar)` 只负责隐藏标题文字并让内容铺满整个窗口，
/// 标题栏下方那条分隔线仍然由 AppKit 自己决定：内容顶到窗口边缘时，它会被画成
/// 一条横贯窗口的灰带，把左右两栏重新切成「上 / 下」。这里在视图挂进窗口之后
/// 把它关掉，左右两栏才真的从窗口最顶端开始。
struct FlatTitleBarHost: NSViewRepresentable {
    func makeNSView(context: Context) -> FlatTitleBarView {
        FlatTitleBarView()
    }

    func updateNSView(_ nsView: FlatTitleBarView, context: Context) {
        nsView.flatten()
    }
}

@MainActor
final class FlatTitleBarView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        flatten()
    }

    func flatten() {
        guard let window else {
            return
        }
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.titlebarSeparatorStyle = .none
    }
}

extension View {
    /// 把标题栏与内容之间的那条分隔线关掉（见 `FlatTitleBarView`）。
    func flatTitleBar() -> some View {
        background(FlatTitleBarHost())
    }
}

// MARK: - Page scaffolding

struct PageContainer<Content: View>: View {
    var maxWidth: CGFloat = Metric.pageMaxWidth
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metric.sectionSpacing) {
                content
            }
            .padding(.horizontal, Metric.pagePadding)
            .padding(.vertical, 20)
            .frame(maxWidth: maxWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(DesignColor.canvas)
    }
}

/// 分组标题行：标题在分组之外，视觉上比组内文字更轻，形成「标题 - 内容」两级。
struct SectionHeader: View {
    var title: String?
    var hint: String?
    var accessory: AnyView?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if let title {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
            }

            Spacer(minLength: 8)

            if let accessory {
                accessory
            } else if let hint {
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 2)
        .padding(.bottom, 7)
    }
}

/// 一个分组：可选标题 + 圆角表面 + 可选脚注说明。
///
/// 内容自己负责内边距：整块内容用 `Metric.groupPadding`，行列表用 `GroupRow`。
struct GroupSection<Content: View>: View {
    var title: String?
    var hint: String?
    var footer: String?
    var accessory: AnyView?
    @ViewBuilder var content: Content

    init(
        title: String? = nil,
        hint: String? = nil,
        footer: String? = nil,
        accessory: AnyView? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.hint = hint
        self.footer = footer
        self.accessory = accessory
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if title != nil || hint != nil || accessory != nil {
                SectionHeader(title: title, hint: hint, accessory: accessory)
            }

            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(DesignColor.group, in: DesignColor.groupShape)
                .overlay {
                    DesignColor.groupShape.strokeBorder(DesignColor.hairline, lineWidth: 1)
                }

            if let footer {
                Text(footer)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 2)
                    .padding(.top, 7)
            }
        }
    }
}

/// 分组内的一行：统一内边距，分隔线由 `dividerAbove` 控制。
struct GroupRow<Content: View>: View {
    var dividerAbove = false
    var inset: CGFloat = Metric.rowDividerInset
    @ViewBuilder var content: Content

    init(dividerAbove: Bool = false, inset: CGFloat = Metric.rowDividerInset, @ViewBuilder content: () -> Content) {
        self.dividerAbove = dividerAbove
        self.inset = inset
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            if dividerAbove {
                RowDivider(inset: inset)
            }
            content
                .padding(.horizontal, Metric.rowPadding)
                .padding(.vertical, Metric.rowVerticalPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct RowDivider: View {
    var inset: CGFloat = Metric.rowDividerInset

    var body: some View {
        Divider().padding(.leading, inset)
    }
}

/// 分组内可展开的一行。标题区整块可点，右侧可以再放一个独立按钮。
struct DisclosureRow<Content: View>: View {
    let title: String
    var subtitle: String?
    var symbol: String?
    var accessory: AnyView?
    @Binding var isExpanded: Bool
    @ViewBuilder var content: Content

    init(
        title: String,
        subtitle: String? = nil,
        symbol: String? = nil,
        accessory: AnyView? = nil,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.accessory = accessory
        self._isExpanded = isExpanded
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            GroupRow {
                HStack(spacing: 10) {
                    if let symbol {
                        Image(systemName: symbol)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 18)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.callout)
                        if let subtitle {
                            Text(subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }

                    Spacer(minLength: 8)

                    if let accessory {
                        accessory
                    }

                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .frame(width: 12)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.snappy(duration: 0.18)) {
                        isExpanded.toggle()
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel(title)
            }

            if isExpanded {
                RowDivider()
                content
                    .padding(Metric.groupPadding)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

/// 兼容既有调用点（设置窗口等）：标题 + 内边距内容的分组。
struct Card<Content: View>: View {
    var title: String?
    var accessory: AnyView?
    @ViewBuilder var content: Content

    init(
        _ title: String? = nil,
        accessory: AnyView? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.accessory = accessory
        self.content = content()
    }

    var body: some View {
        GroupSection(title: title, accessory: accessory) {
            content
                .padding(Metric.groupPadding)
        }
    }
}

// MARK: - Runtime identity

extension RuntimeKind {
    /// 运行时标识色。只用在图标徽章上，不铺到文字和背景。
    var tint: Color {
        switch self {
        case .node:
            return Color(red: 0.24, green: 0.66, blue: 0.40)
        case .java:
            return Color(red: 0.86, green: 0.49, blue: 0.16)
        case .python:
            return Color(red: 0.26, green: 0.51, blue: 0.82)
        }
    }
}

/// 运行时图标徽章：颜色只出现在这一小块上，整页因此安静下来。
struct RuntimeBadge: View {
    let kind: RuntimeKind
    var size: CGFloat = Metric.badgeSize
    var isActive = true

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.29, style: .continuous)
            .fill(kind.tint.opacity(isActive ? 0.15 : 0.08))
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: kind.symbol)
                    .font(.system(size: size * 0.46, weight: .semibold))
                    .foregroundStyle(isActive ? AnyShapeStyle(kind.tint) : AnyShapeStyle(.tertiary))
            }
            .accessibilityHidden(true)
    }
}

// MARK: - Search field

/// 内联搜索框。
///
/// 不用 `.searchable(placement: .toolbar)`：那会在窗口顶部再切出一条工具栏，
/// 把左右两栏从中间打断。搜索属于内容列的筛选行，就把它放回筛选行里；
/// `NSSearchField` 自带放大镜、清除按钮和键盘焦点，观感仍是系统控件。
struct SearchField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String = ""

    func makeCoordinator() -> Coordinator {
        Coordinator(binding: $text)
    }

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.delegate = context.coordinator
        field.focusRingType = .none
        field.usesSingleLineMode = true
        field.sendsSearchStringImmediately = true
        field.sendsWholeSearchString = false
        return field
    }

    func updateNSView(_ nsView: NSSearchField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        nsView.placeholderString = placeholder
    }

    @MainActor
    final class Coordinator: NSObject, NSSearchFieldDelegate {
        private let text: Binding<String>

        init(binding: Binding<String>) {
            self.text = binding
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSSearchField else {
                return
            }
            text.wrappedValue = field.stringValue
        }
    }
}

// MARK: - Typography

extension View {
    /// 行内版本号：等宽数字保证多行版本号对齐，单色不靠颜色区分运行时。
    func rowVersionFont() -> some View {
        font(.system(size: 14, weight: .semibold, design: .rounded).monospacedDigit())
    }
}

// MARK: - Status pill

struct Pill: View {
    enum Tone {
        case neutral
        case positive
        case warning
        case negative
        case informative

        var color: Color {
            switch self {
            case .neutral:
                return .secondary
            case .positive:
                return .green
            case .warning:
                return .orange
            case .negative:
                return .red
            case .informative:
                return .blue
            }
        }
    }

    let text: String
    var tone: Tone = .neutral
    var symbol: String? = nil

    init(_ text: String, tone: Tone = .neutral, symbol: String? = nil) {
        self.text = text
        self.tone = tone
        self.symbol = symbol
    }

    var body: some View {
        HStack(spacing: 3) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 8, weight: .bold))
            }
            Text(text)
        }
        .font(.caption2.weight(.medium))
        .foregroundStyle(tone.color)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(tone.color.opacity(0.12), in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

/// 极轻的来源/状态标记：一个小圆点加一行说明文字，用在行副标题里。
struct StatusDot: View {
    var tone: Pill.Tone = .neutral

    var body: some View {
        Circle()
            .fill(tone.color.opacity(0.85))
            .frame(width: 5, height: 5)
            .accessibilityHidden(true)
    }
}

// MARK: - Empty state

/// 空状态：一个图标、一句「为什么为空」、至多一个主要动作。
struct EmptyState<Actions: View>: View {
    let symbol: String
    let title: String
    var message: String?
    @ViewBuilder var actions: Actions

    init(
        symbol: String,
        title: String,
        message: String? = nil,
        @ViewBuilder actions: () -> Actions = { EmptyView() }
    ) {
        self.symbol = symbol
        self.title = title
        self.message = message
        self.actions = actions()
    }

    var body: some View {
        VStack(spacing: 9) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(.tertiary)

            Text(title)
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)

            if let message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            actions
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.vertical, 28)
    }
}

/// 分组内的紧凑提示：一行图标加说明，不占据整块高度。
struct InlineHint: View {
    let symbol: String
    let text: String

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Path / value row

struct ValueRow: View {
    let label: String
    let value: String

    @State private var didCopy = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 108, alignment: .leading)

            Text(value)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .help(value)

            Spacer(minLength: 8)

            Button {
                WindowActions.copy(value)
                didCopy = true
                Task {
                    try? await Task.sleep(nanoseconds: 1_400_000_000)
                    didCopy = false
                }
            } label: {
                Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .help(didCopy ? "已复制" : "复制")
            .accessibilityLabel(didCopy ? "已复制 \(label)" : "复制\(label)")
            .disabled(!value.hasPrefix("/"))

            Button {
                DesktopPathActions.revealInFinder(value)
            } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(.borderless)
            .help("在 Finder 中显示")
            .accessibilityLabel("在 Finder 中显示\(label)")
            .disabled(!pathExists)
        }
        .controlSize(.small)
    }

    private var pathExists: Bool {
        value.hasPrefix("/") && FileManager.default.fileExists(atPath: value)
    }
}

// MARK: - Version switcher

/// 用原生下拉按钮而不是 `Menu`：`Menu` 在 `.borderlessButton` 样式下会把
/// 标签里的 `Text` 提为标题、其余视图降级成前导图标，箭头会跑到版本号左边。
/// `Picker` 得到的是标准 macOS 弹出按钮：数值在左、箭头在右，可点区域也正确。
struct VersionSwitcher: View {
    let kind: RuntimeKind
    let options: [InstalledRuntime]
    let selectionID: String?
    let isDisabled: Bool
    let onSelect: (InstalledRuntime) -> Void
    var onInstall: () -> Void = {}

    private static let manageTag = "__envpilot_manage__"

    var body: some View {
        if options.isEmpty {
            Button {
                onInstall()
            } label: {
                Label("安装", systemImage: "arrow.down.circle")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(isDisabled)
            .help("安装 \(kind.title)")
        } else {
            Picker("切换 \(kind.title) 版本", selection: selectionBinding) {
                ForEach(options) { option in
                    Text(VersionLabel.display(kind, option.version)).tag(option.id)
                }
                Divider()
                Text("管理\(kind.title)版本…").tag(Self.manageTag)
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
            .disabled(isDisabled)
            .help("切换 \(kind.title) 版本")
            .accessibilityLabel("切换 \(kind.title) 版本")
        }
    }

    private var selectionBinding: Binding<String> {
        Binding(
            get: { selectionID ?? "" },
            set: { newValue in
                guard newValue != Self.manageTag else {
                    onInstall()
                    return
                }
                guard let option = options.first(where: { $0.id == newValue }),
                      option.id != selectionID else {
                    return
                }
                onSelect(option)
            }
        )
    }
}

// MARK: - Selectable row

/// 可选中行的样式：选中用强调色浅底，悬停用极浅的填充。
///
/// 用它替代 `List` 的行，是为了让列表容器和页面里的其他分组用同一套
/// 表面颜色——`List` 在深色下自带更暗的底色，会和分组风格脱节。
struct SelectableRowStyle: ButtonStyle {
    var isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        SelectableRowChrome(configuration: configuration, isSelected: isSelected)
    }

    private struct SelectableRowChrome: View {
        let configuration: ButtonStyleConfiguration
        let isSelected: Bool

        @State private var isHovering = false

        var body: some View {
            configuration.label
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(fill)
                )
                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .opacity(configuration.isPressed ? 0.72 : 1)
                .onHover { hovering in
                    withAnimation(.easeOut(duration: 0.12)) {
                        isHovering = hovering
                    }
                }
        }

        private var fill: Color {
            if isSelected {
                return Color.accentColor.opacity(0.16)
            }
            return isHovering ? Color.primary.opacity(0.07) : Color.clear
        }
    }
}

// MARK: - Status bar

struct StatusBar: View {
    enum Tone {
        case idle
        case notice
        case error
    }

    let text: String
    let tone: Tone
    var onDismiss: (() -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            switch tone {
            case .idle:
                Image(systemName: "circle")
                    .foregroundStyle(.tertiary)
            case .notice:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .error:
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }

            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .textSelection(.enabled)

            Spacer(minLength: 8)

            if let onDismiss {
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .help("关闭提示")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(DesignColor.canvas)
        .overlay(alignment: .top) {
            Divider()
        }
    }
}
