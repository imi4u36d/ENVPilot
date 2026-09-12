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

    var subtitle: String {
        switch self {
        case .overview:
            return "当前生效的运行时与终端环境"
        case .runtimes:
            return "已安装版本与可安装版本"
        case .projects:
            return "项目版本策略与 .envpilot 解析"
        case .profiles:
            return "registry、NODE_OPTIONS 与自定义环境变量"
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

// MARK: - Layout

struct PageContainer<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                content
            }
            .padding(20)
            .frame(maxWidth: 920, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
    }
}

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
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(title)
                        .font(.headline)
                    Spacer(minLength: 8)
                    if let accessory {
                        accessory
                    }
                }
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            DesignColor.surface,
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .overlay(DesignColor.hairlineShape)
    }
}

enum DesignColor {
    static var surface: Color {
        Color(nsColor: .controlBackgroundColor)
    }

    static var hairline: Color {
        Color(nsColor: .separatorColor).opacity(0.55)
    }

    static var hairlineShape: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .strokeBorder(hairline, lineWidth: 1)
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
                .layoutPriority(1)

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

struct VersionSwitcher: View {
    let kind: RuntimeKind
    let options: [InstalledRuntime]
    let selectionID: String?
    let isDisabled: Bool
    let onSelect: (InstalledRuntime) -> Void
    var onInstall: () -> Void = {}

    var body: some View {
        if options.isEmpty {
            Button("安装 \(kind.title)") {
                onInstall()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(isDisabled)
        } else {
            Picker(
                "切换 \(kind.title) 版本",
                selection: Binding(
                    get: { selectionID ?? "" },
                    set: { newValue in
                        guard let option = options.first(where: { $0.id == newValue }), option.id != selectionID else {
                            return
                        }
                        onSelect(option)
                    }
                )
            ) {
                ForEach(options) { option in
                    Text(VersionLabel.display(kind, option.version)).tag(option.id)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
            .disabled(isDisabled)
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
        .background(.bar)
        .overlay(alignment: .top) {
            Divider()
        }
    }
}
