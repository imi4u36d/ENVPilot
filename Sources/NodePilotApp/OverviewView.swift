import SwiftUI
import ENVPilotCore

// MARK: - 概览

struct OverviewView: View {
    @ObservedObject var store: NodeRuntimeStore
    @ObservedObject var aiStore: AIEnvironmentStore
    var onOpenRuntime: (RuntimeKind) -> Void
    var onOpenAI: (AIEnvironmentKind) -> Void

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
#if DEBUG
        let _ = PerfProbe.noteBody("overview")
#endif
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
                aiEnvironmentSection
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
                message: "前往运行时页安装版本后，这里会显示终端将要使用的版本。"
            ) {
                Button("前往运行时") {
                    onOpenRuntime(.node)
                }
                .appButton(.secondary, size: .small)
            }
        }
    }

    // MARK: 当前环境

    /// 大号等宽版本号是展示的重心；版本切换和安装留在运行时页。
    private var currentEnvironmentSection: some View {
        GroupSection(title: "当前环境", hint: "全局生效") {
            VStack(spacing: 0) {
                ForEach(Array(store.summaries.enumerated()), id: \.element.id) { index, summary in
                    GroupRow(dividerAbove: index > 0) {
                        EnvironmentHeroRow(summary: summary) {
                            onOpenRuntime(summary.kind)
                        }
                    }
                }
            }
        }
    }

    // MARK: AI 环境

    private var aiEnvironmentSection: some View {
        GroupSection(
            title: "AI 环境",
            hint: "已安装 \(aiStore.installedCount) / \(AIEnvironmentKind.allCases.count)"
        ) {
            VStack(spacing: 0) {
                ForEach(Array(aiStore.statuses.enumerated()), id: \.element.id) { index, status in
                    GroupRow(dividerAbove: index > 0) {
                        AIEnvironmentOverviewRow(
                            status: status,
                            onOpen: { onOpenAI(status.kind) }
                        ) {
                            onOpenAI(status.kind)
                        }
                    }
                }
            }
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
                    .appButton(.quiet, size: .small)
                    .disabled(activationScript.isEmpty)
                    .help("复制终端将执行的导出语句")
                ),
                isExpanded: $showsScript
            ) {
                if activationScript.isEmpty {
                    Text("当前没有需要导出的环境变量。")
                        .font(.caption)
                        .foregroundStyle(DesignColor.tertiaryText)
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

/// 「当前环境」里的一行：徽章 + 大号版本号 + 名称/路径/状态。
private struct EnvironmentHeroRow: View {
    let summary: RuntimeSummary
    let onOpen: () -> Void

    private var isActive: Bool {
        summary.current != nil
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            RuntimeBadge(kind: summary.kind, size: 26, isActive: isActive)

            Text(isActive ? VersionLabel.display(summary.kind, summary.version) : "—")
                .font(.system(.title2, design: .monospaced, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(isActive ? AnyShapeStyle(Color.primary) : AnyShapeStyle(DesignColor.tertiaryText))
                // 列宽只给下限：三个运行时的名称列仍然纵向对齐，但长版本号
                // （`8 · 1.8.0_402`、`17.0.20.1`）不会再被硬裁。
                .frame(minWidth: 118, alignment: .leading)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 7) {
                    Text(summary.kind.title)
                        .font(.callout.weight(.medium))

                    if !summary.isCurrentValid {
                        Pill("配置缺失", tone: .warning)
                    } else if !isActive {
                        Pill(summary.options.isEmpty ? "未安装" : "未选择", tone: .neutral)
                    } else {
                        Pill("当前使用", tone: .positive, symbol: "checkmark.circle.fill")
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

            if summary.options.isEmpty {
                Button("安装") {
                    onOpen()
                }
                .appButton(.secondary, size: .small)
                .accessibilityLabel("安装 \(summary.kind.title)")
            } else if !summary.isCurrentValid {
                Button("管理版本") {
                    onOpen()
                }
                .appButton(.secondary, size: .small)
                .accessibilityLabel("管理 \(summary.kind.title) 版本")
            } else if !isActive {
                Button("选择版本") {
                    onOpen()
                }
                .appButton(.secondary, size: .small)
                .accessibilityLabel("选择 \(summary.kind.title) 版本")
            }
        }
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

// MARK: - AI 环境行

private struct AIEnvironmentOverviewRow: View {
    let status: AIEnvironmentStatus
    let onOpen: () -> Void
    let onOpenUpdate: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            AIEnvironmentBadge(kind: status.kind, size: 26)

            Text(status.currentVersion ?? "—")
                .font(.system(.title2, design: .monospaced, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(status.isInstalled ? AnyShapeStyle(Color.primary) : AnyShapeStyle(DesignColor.tertiaryText))
                .frame(width: 118, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 7) {
                    Text(status.kind.displayName)
                        .font(.callout.weight(.medium))

                    if status.isInstalled {
                        Pill(status.installMethod.label, tone: .neutral)
                    } else {
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

            if status.updateAvailable, let latestVersion = status.latestVersion {
                OverviewUpdateTip(version: latestVersion, action: onOpenUpdate)
            } else if !status.isInstalled {
                Button("管理") {
                    onOpen()
                }
                .appButton(.secondary, size: .small)
                .accessibilityLabel("管理 \(status.kind.displayName)")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(status.kind.displayName) \(status.currentVersion ?? "未安装")")
    }

    private var detail: String {
        guard let executablePath = status.executablePath else {
            return status.kind.subtitle
        }
        return executablePath.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }
}

private struct OverviewUpdateTip: View {
    let version: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "arrow.down.circle")
                    .font(.system(.caption, weight: .semibold))
                    .accessibilityHidden(true)
                Text("可更新至 \(version)")
                Image(systemName: "chevron.right")
                    .font(.system(.caption2, weight: .bold))
                    .accessibilityHidden(true)
            }
            .font(.caption2.weight(.medium))
            .foregroundStyle(DesignColor.statusWarning)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(DesignColor.statusWarning.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
        .help("前往 AI 环境页更新 \(version)")
        .accessibilityLabel("可更新至 \(version)，前往 AI 环境页")
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
