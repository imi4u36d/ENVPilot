import SwiftUI
import ENVPilotCore

// MARK: - 概览

struct OverviewView: View {
    @ObservedObject var store: NodeRuntimeStore
    var onOpenRuntime: (RuntimeKind) -> Void

    @State private var detailsExpanded = false

    /// 作用域只显示目录名，完整路径放 tooltip——顶栏没必要塞一整条路径。
    private var scopeLabel: String {
        guard let directory = store.inspectedDirectory else {
            return "全局默认作用域"
        }
        return "项目 · \(directory.lastPathComponent)"
    }

    private var activationScript: String {
        guard let snapshot = store.snapshot else {
            return ""
        }
        return RuntimeSnapshotReader.activationScript(for: snapshot, directory: store.inspectedDirectory)
    }

    var body: some View {
        PageContainer {
            if store.snapshot == nil {
                Card {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text("正在读取本机运行时…")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                if !store.hasAnyRuntime {
                    onboardingCard
                }
                currentEnvironmentCard
                terminalCard
                detailsCard
            }
        }
    }

    // MARK: Cards

    private var onboardingCard: some View {
        Card("开始使用") {
            VStack(alignment: .leading, spacing: 12) {
                Text("本机还没有 ENVPilot 管理的运行时。安装一个版本后，这里会显示终端将要使用的版本。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

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

    private var currentEnvironmentCard: some View {
        Card(
            "当前环境",
            accessory: AnyView(
                HStack(spacing: 6) {
                    Text(scopeLabel)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(scopeLabel)
                }
                .frame(maxWidth: 320, alignment: .trailing)
            )
        ) {
            VStack(spacing: 0) {
                ForEach(Array(store.summaries.enumerated()), id: \.element.id) { index, summary in
                    if index > 0 {
                        Divider()
                    }
                    environmentRow(summary)
                        .padding(.vertical, 9)
                }
            }
        }
    }

    private func environmentRow(_ summary: RuntimeSummary) -> some View {
        let isSwitching = store.isBusy(key: "switch:\(summary.kind.rawValue)")
        let version = summary.current.map { VersionLabel.display(summary.kind, $0.version) } ?? summary.version
        let hasRuntime = !summary.options.isEmpty

        return HStack(alignment: .center, spacing: 12) {
            Image(systemName: summary.kind.symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 18)

            // 版本号是这一行唯一的主视觉；来源放在它下面一行，靠位置而不是颜色区分。
            VStack(alignment: .leading, spacing: 2) {
                if hasRuntime {
                    Text(version)
                        .runtimeVersionFont()
                        .foregroundStyle(summary.current == nil ? AnyShapeStyle(.tertiary) : AnyShapeStyle(summary.kind.tint))
                } else {
                    Text("未安装")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                }

                HStack(spacing: 5) {
                    Text(summary.kind.title)
                    if hasRuntime, summary.source != .none {
                        Text("·")
                        Text(summary.source.label)
                    }
                    if !summary.isCurrentValid {
                        Text("·")
                        Text("配置缺失")
                            .foregroundStyle(.orange)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
            }

            Spacer(minLength: 10)

            if isSwitching {
                ProgressView()
                    .controlSize(.small)
            } else {
                VersionSwitcher(
                    kind: summary.kind,
                    options: summary.options,
                    selectionID: summary.current?.id,
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
    }

    private var terminalCard: some View {
        Card(
            "终端环境",
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
            )
        ) {
            VStack(alignment: .leading, spacing: 10) {
                Text("新开的终端会自动执行以下语句；已打开的终端可粘贴执行，或按 ⌘N 新开一个窗口。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if activationScript.isEmpty {
                    Text("当前没有需要导出的环境变量。")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(DesignColor.hairline.opacity(0.25), in: RoundedRectangle(cornerRadius: 6))
                } else {
                    ScrollView {
                        Text(activationScript)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                    }
                    .frame(maxHeight: 148)
                    .background(DesignColor.hairline.opacity(0.25), in: RoundedRectangle(cornerRadius: 6))
                }

                Divider()

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.tertiary)
                    Text("版本变更只影响之后打开的终端。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var detailsCard: some View {
        Card {
            DisclosureGroup(isExpanded: $detailsExpanded) {
                VStack(spacing: 9) {
                    ValueRow(label: "Node 目录", value: store.summary(for: .node).path ?? "未选择")
                    ValueRow(label: "JAVA_HOME", value: store.summary(for: .java).path ?? "未选择")
                    ValueRow(label: "PYTHON_HOME", value: store.summary(for: .python).path ?? "未选择")
                    Divider()
                    ValueRow(label: "配置文件", value: SettingsPaths.settingsFile)
                    ValueRow(label: "运行时目录", value: SettingsPaths.runtimeRoot)
                }
                .padding(.top, 10)
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("路径详情")
                        .font(.subheadline.weight(.medium))
                    Spacer(minLength: 8)
                    Text("复制或定位运行时路径")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: Helpers

    private func abbreviated(_ path: String) -> String {
        path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
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
