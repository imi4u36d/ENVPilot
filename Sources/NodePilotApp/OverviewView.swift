import SwiftUI
import ENVPilotCore

// MARK: - 概览

struct OverviewView: View {
    @ObservedObject var store: NodeRuntimeStore
    var onOpenRuntime: (RuntimeKind) -> Void

    @State private var showsScript = false
    @State private var showsPaths = false

    private var activationScript: String {
        guard let snapshot = store.snapshot else {
            return ""
        }
        return RuntimeSnapshotReader.activationScript(for: snapshot)
    }

    private var exportedVariableCount: Int {
        activationScript
            .split(whereSeparator: \.isNewline)
            .filter { $0.hasPrefix("export ") }
            .count
    }

    var body: some View {
        let _ = PerfProbe.noteBody("overview")
        PageContainer {
            if store.snapshot == nil {
                GroupSection {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text("正在读取本机运行时…")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                    }
                    .padding(Metric.groupPadding)
                }
            } else {
                if !store.hasAnyRuntime {
                    onboardingSection
                }
                currentEnvironmentSection
                terminalSection
                pathsSection
            }
        }
    }

    // MARK: 开始使用

    private var onboardingSection: some View {
        GroupSection(title: "开始使用") {
            EmptyState(
                symbol: "shippingbox",
                title: "本机还没有 ENVPilot 管理的运行时",
                message: "安装一个版本后，这里会显示终端将要使用的版本。"
            ) {
                HStack(spacing: 8) {
                    ForEach(RuntimeKind.allCases) { kind in
                        Button("安装 \(kind.title)") {
                            onOpenRuntime(kind)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
    }

    // MARK: 当前环境

    /// 主角行：大号等宽版本号是展示的重心，版本 chip 是切换器。
    /// 行间不用分隔线而用 hover 底色，读起来像「三个环境对象」，不是一张表格。
    private var currentEnvironmentSection: some View {
        GroupSection(title: "当前环境", hint: "全局生效") {
            VStack(spacing: 6) {
                ForEach(store.summaries) { summary in
                    EnvironmentHeroRow(
                        summary: summary,
                        isSwitching: store.isBusy(key: "switch:\(summary.kind.rawValue)"),
                        isDisabled: store.isBusy,
                        onSelect: { option in
                            Task { await store.selectDefault(option) }
                        },
                        onInstall: {
                            onOpenRuntime(summary.kind)
                        }
                    )
                }
            }
            .padding(8)
        }
    }

    // MARK: 终端环境

    private var terminalSection: some View {
        GroupSection(footer: "版本变更只影响之后打开的终端。") {
            DisclosureRow(
                title: "终端环境",
                subtitle: activationScript.isEmpty
                    ? "当前没有需要导出的环境变量"
                    : "新开的终端会自动执行 \(exportedVariableCount) 条导出语句",
                symbol: "terminal",
                accessory: AnyView(
                    Button {
                        WindowActions.copy(activationScript)
                    } label: {
                        Label("复制", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .disabled(activationScript.isEmpty)
                    .help("复制终端将执行的导出语句")
                ),
                isExpanded: $showsScript
            ) {
                if activationScript.isEmpty {
                    Text("当前没有需要导出的环境变量。")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(DesignColor.well, in: RoundedRectangle(cornerRadius: 6))
                } else {
                    Text(activationScript)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(DesignColor.well, in: RoundedRectangle(cornerRadius: 6))
                }
            }
        }
    }

    // MARK: 路径详情

    private var pathsSection: some View {
        GroupSection(footer: "复制路径，或在 Finder 中定位运行时目录。") {
            DisclosureRow(
                title: "路径详情",
                subtitle: "运行时目录与配置文件位置",
                symbol: "folder",
                isExpanded: $showsPaths
            ) {
                VStack(spacing: 9) {
                    ValueRow(label: "Node 目录", value: store.summary(for: .node).path ?? "未选择")
                    ValueRow(label: "JAVA_HOME", value: store.summary(for: .java).path ?? "未选择")
                    ValueRow(label: "PYTHON_HOME", value: store.summary(for: .python).path ?? "未选择")
                    Divider().padding(.vertical, 2)
                    ValueRow(label: "配置文件", value: SettingsPaths.settingsFile)
                    ValueRow(label: "运行时目录", value: SettingsPaths.runtimeRoot)
                }
            }
        }
    }
}

// MARK: - 主角行

/// 「当前环境」里的一行：徽章 + 大号版本号 + 名称/路径 + chip 切换器。
private struct EnvironmentHeroRow: View {
    let summary: RuntimeSummary
    let isSwitching: Bool
    let isDisabled: Bool
    let onSelect: (InstalledRuntime) -> Void
    let onInstall: () -> Void

    @State private var isHovering = false

    private var isActive: Bool {
        summary.current != nil
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            RuntimeBadge(kind: summary.kind, size: 24, isActive: isActive)

            Text(isActive ? VersionLabel.display(summary.kind, summary.version) : "—")
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(isActive ? AnyShapeStyle(Color.primary) : AnyShapeStyle(.tertiary))
                // 固定列宽：三种运行时的名称列与 chip 列纵向对齐。
                .frame(width: 128, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 7) {
                    Text(summary.kind.title)
                        .font(.callout.weight(.medium))

                    if !summary.isCurrentValid {
                        Pill("配置缺失", tone: .warning)
                    } else if !isActive {
                        Pill("未安装", tone: .neutral)
                    }
                }

                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(detail)
            }

            Spacer(minLength: 12)

            if isSwitching {
                ProgressView()
                    .controlSize(.small)
            } else {
                VersionChipRow(
                    kind: summary.kind,
                    options: summary.options,
                    selectionID: summary.current?.id,
                    isDisabled: isDisabled,
                    onSelect: onSelect,
                    onInstall: onInstall
                )
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(
            DesignColor.well.opacity(isHovering ? 1 : 0),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .onHover { isHovering = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(summary.kind.title) \(isActive ? summary.version : "未安装")")
    }

    private var detail: String {
        guard !summary.options.isEmpty else {
            return "尚未安装，安装后即可使用"
        }
        guard let path = summary.path else {
            return "未选择运行时"
        }
        return path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }
}

enum SettingsPaths {
    static var settingsFile: String {
        (try? ConfigStore().settingsURL().path) ?? ""
    }

    static var runtimeRoot: String {
        NSHomeDirectory() + "/.envpilot/runtimes"
    }
}
