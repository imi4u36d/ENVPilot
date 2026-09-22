import ENVPilotCore
import SwiftUI

struct AIEnvironmentsView: View {
    @ObservedObject var store: AIEnvironmentStore
    var focusKind: AIEnvironmentKind?

    @State private var highlightedKind: AIEnvironmentKind?

    var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                controlBar

                ScrollView {
                    VStack(alignment: .leading, spacing: Metric.sectionSpacing) {
                        toolsSection
                    }
                    .padding(.horizontal, Metric.pagePadding)
                    .padding(.vertical, 20)
                    .frame(maxWidth: Metric.pageMaxWidth, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                .background(DesignColor.canvas)

                if let status = store.statusMessage {
                    StatusBar(
                        text: status.text,
                        tone: status.tone == .error ? .error : .notice,
                        onDismiss: { store.dismissStatus() }
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .task(id: focusKind) {
                await store.refreshIfNeeded()
                guard let focusKind else {
                    return
                }
                try? await Task.sleep(for: .milliseconds(80))
                withAnimation(.snappy(duration: 0.2)) {
                    proxy.scrollTo(focusKind, anchor: .center)
                }
                highlightedKind = focusKind
                try? await Task.sleep(for: .seconds(1.6))
                guard highlightedKind == focusKind else {
                    return
                }
                withAnimation(.easeOut(duration: 0.2)) {
                    highlightedKind = nil
                }
            }
        }
    }

    private var controlBar: some View {
        PageToolbar {
            HStack(spacing: 12) {
                Text("已安装 \(store.installedCount) / \(AIEnvironmentKind.allCases.count)")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                if store.availableUpdateCount > 0 {
                    Pill(
                        "\(store.availableUpdateCount) 个可更新",
                        tone: .warning,
                        symbol: "arrow.down.circle"
                    )
                }

                Spacer(minLength: 12)

                if store.availableUpdateCount > 1 {
                    Button {
                        Task { await store.updateAvailableTools() }
                    } label: {
                        Label("全部更新", systemImage: "arrow.down.circle")
                    }
                    .appButton(.secondary, size: .small)
                    .disabled(store.isLoading || !store.canUpdateAnyTool)
                }

                Button {
                    Task { await store.refresh() }
                } label: {
                    Label("重新检查", systemImage: "arrow.clockwise")
                }
                .appButton(.quiet, size: .small)
                .disabled(store.isLoading || store.isUpdating)
                .help("重新读取本机 AI 工具与最新版本")
            }
        }
    }

    private var toolsSection: some View {
        GroupSection(title: "AI 编码工具") {
            VStack(spacing: 0) {
                ForEach(Array(store.statuses.enumerated()), id: \.element.id) { index, status in
                    GroupRow(dividerAbove: index > 0) {
                        toolRow(status)
                            .background(
                                highlightedKind == status.kind
                                    ? Color.accentColor.opacity(0.08)
                                    : Color.clear
                            )
                    }
                    .id(status.kind)
                }
            }
        }
    }

    private func toolRow(_ status: AIEnvironmentStatus) -> some View {
        HStack(alignment: .center, spacing: 12) {
            AIEnvironmentBadge(kind: status.kind)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Text(status.kind.displayName)
                        .font(.system(size: 14, weight: .semibold))

                    if status.isInstalled {
                        Pill(status.installMethod.label, tone: .neutral)
                    } else {
                        Pill("未安装", tone: .neutral)
                    }

                    if status.canSwitchToEnvPilot {
                        Button {
                            Task { await store.switchToEnvPilot(status.kind) }
                        } label: {
                            Label("切换到 ENVPilot 管理", systemImage: "arrow.down.circle")
                        }
                        .appButton(.secondary, size: .mini)
                        .disabled(store.isBusy(status.kind))
                        .help("安装最新版到当前 ENVPilot Node，并让新终端优先使用该版本")
                    }
                }

                if let executablePath = status.executablePath {
                    Text(executablePath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(executablePath)
                } else {
                    Text(status.kind.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                versionLine(status)
            }

            Spacer(minLength: 12)

            if store.isBusy(status.kind) {
                HStack(spacing: 7) {
                    ProgressView()
                        .controlSize(.small)

                    Text(
                        store.updateStage(for: status.kind)?.message
                            ?? store.busyAction(for: status.kind)?.progressFallback
                            ?? "正在处理"
                    )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Button("取消") {
                        store.cancelOperation(status.kind)
                    }
                    .appButton(.quiet, size: .small)
                }
                .frame(width: 190, alignment: .trailing)
                .help(
                    store.busyAction(for: status.kind) == .install
                        ? "取消安装 \(status.kind.displayName)"
                        : "取消更新 \(status.kind.displayName)"
                )
            } else if status.isInstalled {
                if status.updateAvailable, let latestVersion = status.latestVersion {
                    Button {
                        Task { await store.update(status.kind) }
                    } label: {
                        Label("更新到 \(latestVersion)", systemImage: "arrow.down.circle")
                    }
                    .appButton(.primary, size: .small)
                    .disabled(store.isBusy(status.kind))
                } else if status.latestVersion != nil {
                    Label("已是最新", systemImage: "checkmark")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Button("更新") {
                        Task { await store.update(status.kind) }
                    }
                    .appButton(.secondary, size: .small)
                    .disabled(store.isBusy(status.kind))
                }
            } else {
                Button {
                    Task { await store.install(status.kind) }
                } label: {
                    Label("安装", systemImage: "arrow.down.circle")
                }
                .appButton(.primary, size: .small)
                .disabled(store.isBusy(status.kind))
            }

            if status.isInstalled {
                Menu {
                    Button("在 Finder 中显示") {
                        DesktopPathActions.revealInFinder(status.executablePath ?? "")
                    }
                    Button("复制可执行文件路径") {
                        WindowActions.copy(status.executablePath ?? "")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .disabled(store.isBusy(status.kind))
                .help("更多操作")
                .accessibilityLabel("\(status.kind.displayName) 的更多操作")
            }
        }
    }

    @ViewBuilder
    private func versionLine(_ status: AIEnvironmentStatus) -> some View {
        HStack(spacing: 6) {
            if let currentVersion = status.currentVersion {
                Text(currentVersion)
                    .rowVersionFont()
            } else if status.isInstalled {
                Text("版本读取失败")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else if let latestVersion = status.latestVersion {
                Text("最新版 \(latestVersion)")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if status.updateAvailable, let latestVersion = status.latestVersion {
                Image(systemName: "arrow.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
                Text(latestVersion)
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if let errorMessage = status.errorMessage, !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(errorMessage)
            }
        }
    }
}

struct AIEnvironmentBadge: View {
    let kind: AIEnvironmentKind
    var size: CGFloat = Metric.badgeSize

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.29, style: .continuous)
            .fill(kind.tint.opacity(0.14))
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: kind.symbol)
                    .font(.system(size: size * 0.44, weight: .semibold))
                    .foregroundStyle(kind.tint)
            }
            .accessibilityHidden(true)
    }
}

extension AIEnvironmentKind {
    var subtitle: String {
        switch self {
        case .codex:
            return "OpenAI 终端编码代理"
        case .claudeCode:
            return "Anthropic 终端编码代理"
        case .pi:
            return "Pi 终端编码代理"
        case .openCode:
            return "OpenCode 终端编码代理"
        }
    }

    var symbol: String {
        switch self {
        case .codex:
            return "terminal.fill"
        case .claudeCode:
            return "sparkles"
        case .pi:
            return "function"
        case .openCode:
            return "chevron.left.forwardslash.chevron.right"
        }
    }

    var tint: Color {
        switch self {
        case .codex:
            return Color(red: 0.20, green: 0.48, blue: 0.78)
        case .claudeCode:
            return Color(red: 0.83, green: 0.39, blue: 0.18)
        case .pi:
            return Color(red: 0.22, green: 0.62, blue: 0.42)
        case .openCode:
            return Color(red: 0.50, green: 0.39, blue: 0.78)
        }
    }
}
