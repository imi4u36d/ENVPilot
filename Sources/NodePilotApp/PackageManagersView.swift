import ENVPilotCore
import SwiftUI

struct PackageManagersView: View {
    @ObservedObject var store: PackageManagerStore
    @State private var expandedKind: PackageManagerKind?
    @State private var hoveredKind: PackageManagerKind?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(store: PackageManagerStore) {
        self.store = store
        self._expandedKind = State(initialValue: WindowSnapshot.initialExpandedPackageManager)
    }

    var body: some View {
        VStack(spacing: 0) {
            controlBar

            ScrollView {
                VStack(alignment: .leading, spacing: Metric.sectionSpacing) {
                    managersSection
                }
                .padding(.horizontal, Metric.pagePadding)
                .padding(.vertical, 20)
                .frame(maxWidth: Metric.pageMaxWidth, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .background(DesignColor.canvas)

            if let status = store.statusMessage, status.tone == .error {
                StatusBanner(text: status.text, onDismiss: { store.dismissStatus() })
            } else if let status = store.statusMessage {
                StatusBar(
                    text: status.text,
                    tone: .notice,
                    onDismiss: { store.dismissStatus() }
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            await store.refreshIfNeeded()
        }
    }

    private var controlBar: some View {
        PageToolbar {
            HStack(spacing: 12) {
                Text("已安装 \(store.installedCount) / \(PackageManagerKind.allCases.count)")
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
                .disabled(store.isLoading || store.isBusy)
                .help("重新读取本机包管理器与最新版本")
            }
        }
    }

    private var managersSection: some View {
        GroupSection(title: "包管理器") {
            VStack(spacing: 0) {
                // 扫描还没回来时不要先渲染「未安装」+ 可点的安装按钮：
                // 那是一个已知错误的状态，用户会据此做出错误操作。

                ForEach(Array(store.statuses.enumerated()), id: \.element.id) { index, status in
                    GroupRow(dividerAbove: index > 0) {
                        managerSummary(status)
                    }
                    .background(rowBackground(for: status.kind))
                    .onHover { isHovering in
                        updateHover(kind: status.kind, isHovering: isHovering)
                    }
                    .redacted(reason: store.isLoading ? .placeholder : [])

                    if expandedKind == status.kind {
                        VStack(spacing: 0) {
                            RowDivider()
                            PackageManagerMirrorEditor(
                                kind: status.kind,
                                savedAddress: store.mirrorAddress(for: status.kind)
                            ) { address in
                                Task {
                                    await store.saveMirror(address, for: status.kind)
                                }
                            }
                            .padding(.horizontal, Metric.rowPadding)
                            .padding(.vertical, Metric.groupPadding)
                            .background(DesignColor.well)
                        }
                        .transition(.opacity)
                    }
                }
            }
        }
    }

    private func managerSummary(_ status: PackageManagerStatus) -> some View {
        HStack(alignment: .center, spacing: 12) {
            PackageManagerBadge(kind: status.kind)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Text(status.kind.displayName)
                        .font(.system(.body, weight: .semibold))

                    if let currentVersion = status.currentVersion {
                        Text(currentVersion)
                            .rowVersionFont()
                    } else if !status.isInstalled, let latestVersion = status.latestVersion {
                        Text("最新版 \(latestVersion)")
                            .rowVersionFont()
                    }

                    if status.isInstalled {
                        Pill(status.installMethod.label, tone: .neutral)
                    } else {
                        Pill("未安装", tone: .neutral)
                    }

                    if status.canSwitchToEnvPilot {
                        Button {
                            Task { await store.switchToEnvPilot(status.kind) }
                        } label: {
                            Label("切换到 ENVPilot 安装", systemImage: "arrow.down.circle")
                        }
                        .appButton(.secondary, size: .mini)
                        .disabled(store.isBusy(status.kind))
                        .help("安装最新版到 ENVPilot 管理目录，并让终端优先使用该版本")
                    }
                }

                if let executablePath = status.executablePath {
                    Text(DisplayPath.short(executablePath))
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

                if status.errorMessage?.isEmpty == false
                    || status.updateAvailable
                    || (status.isInstalled && status.currentVersion == nil) {
                    versionLine(status)
                }
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
                .frame(minWidth: 230, alignment: .trailing)
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
                    .disabled(store.isLoading || store.isBusy(status.kind))
                    .frame(minWidth: 230, alignment: .trailing)
                } else if status.latestVersion != nil {
                    Label("已是最新", systemImage: "checkmark")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 230, alignment: .trailing)
                } else {
                    Button("更新") {
                        Task { await store.update(status.kind) }
                    }
                    .appButton(.secondary, size: .small)
                    .disabled(store.isLoading || store.isBusy(status.kind))
                    .frame(minWidth: 230, alignment: .trailing)
                }
            } else {
                Button {
                    Task { await store.install(status.kind) }
                } label: {
                    Label("安装", systemImage: "arrow.down.circle")
                }
                .appButton(.secondary, size: .small)
                .disabled(store.isLoading || store.isBusy(status.kind))
                .frame(minWidth: 230, alignment: .trailing)
            }

            if status.isInstalled {
                Menu {
                    Button("在 Finder 中显示") {
                        DesktopPathActions.revealInFinder(status.executablePath ?? "")
                    }
                    // 路径为空时以前是「点了没反应」（复制还会复制走空串）。禁用比留一个
                    // 看起来可用的菜单项诚实。
                    .disabled(!DesktopPathActions.isUsablePath(status.executablePath))
                    Button("复制可执行文件路径") {
                        WindowActions.copy(status.executablePath ?? "")
                    }
                    .disabled(!DesktopPathActions.isUsablePath(status.executablePath))
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

            Button {
                toggleExpansion(status.kind)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(.caption, weight: .semibold))
                    .foregroundStyle(DesignColor.tertiaryText)
                    .rotationEffect(.degrees(expandedKind == status.kind ? 90 : 0))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(expandedKind == status.kind ? "收起镜像地址设置" : "展开镜像地址设置")
            .accessibilityLabel("\(status.kind.displayName) 的镜像地址设置")
            .accessibilityValue(expandedKind == status.kind ? "已展开" : "已收起")
        }
    }

    private func toggleExpansion(_ kind: PackageManagerKind) {
        if reduceMotion {
            expandedKind = expandedKind == kind ? nil : kind
        } else {
            withAnimation(.snappy(duration: 0.22)) {
                expandedKind = expandedKind == kind ? nil : kind
            }
        }
    }

    private func updateHover(kind: PackageManagerKind, isHovering: Bool) {
        let update = {
            if isHovering {
                hoveredKind = kind
            } else if hoveredKind == kind {
                hoveredKind = nil
            }
        }
        if reduceMotion {
            update()
        } else {
            withAnimation(.easeOut(duration: 0.12)) {
                update()
            }
        }
    }

    private func rowBackground(for kind: PackageManagerKind) -> Color {
        if expandedKind == kind {
            return DesignColor.selection.opacity(0.42)
        }
        return hoveredKind == kind ? DesignColor.hover : .clear
    }

    @ViewBuilder
    private func versionLine(_ status: PackageManagerStatus) -> some View {
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
                    .font(.system(.caption2, weight: .semibold))
                    .foregroundStyle(DesignColor.tertiaryText)
                    .accessibilityHidden(true)
                Text(latestVersion)
                    .font(.system(.callout, weight: .medium).monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if let errorMessage = status.errorMessage, !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(DesignColor.statusNegative)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(errorMessage)
            }
        }
    }
}

private struct PackageManagerMirrorEditor: View {
    let kind: PackageManagerKind
    let savedAddress: String
    let onSave: (String) -> Void

    @State private var address: String

    init(
        kind: PackageManagerKind,
        savedAddress: String,
        onSave: @escaping (String) -> Void
    ) {
        self.kind = kind
        self.savedAddress = savedAddress
        self.onSave = onSave
        self._address = State(initialValue: savedAddress)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("镜像地址")
                    .font(.callout.weight(.medium))

                Pill(
                    savedAddress.isEmpty ? "官方源" : "自定义",
                    tone: savedAddress.isEmpty ? .neutral : .informative
                )

                Spacer(minLength: 8)

                if !savedAddress.isEmpty {
                    // 「保存」才是提交动作。这里只把输入框改回官方源，避免一次点击就把
                    // 用户自定义的镜像静默丢掉。
                    Button("恢复默认") {
                        address = ""
                    }
                    .appButton(.quiet, size: .small)
                }
            }

            HStack(spacing: 8) {
                Image(systemName: "link")
                    .font(.system(.callout, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                    .accessibilityHidden(true)

                TextField(placeholder, text: $address)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(save)

                Button {
                    save()
                } label: {
                    Label("保存", systemImage: "checkmark")
                }
                .appButton(.primary, size: .small)
                .disabled(!canSave)
            }

            if let validationMessage {
                Text(validationMessage)
                    .font(.caption)
                    .foregroundStyle(DesignColor.statusNegative)
            }
        }
        .onChange(of: savedAddress) { _, newValue in
            address = newValue
        }
    }

    private var normalizedAddress: String {
        address.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var validationMessage: String? {
        guard !normalizedAddress.isEmpty else {
            return nil
        }
        guard let components = URLComponents(string: normalizedAddress),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              components.host?.isEmpty == false else {
            return "请输入完整的 http 或 https 地址。"
        }
        return nil
    }

    private var canSave: Bool {
        validationMessage == nil && normalizedAddress != savedAddress
    }

    private var placeholder: String {
        switch kind {
        case .npm, .pnpm:
            return "https://registry.npmjs.org"
        case .homebrew:
            return "https://formulae.brew.sh/api"
        case .uv:
            return "https://pypi.org/simple"
        }
    }

    private func save() {
        guard canSave else {
            return
        }
        onSave(normalizedAddress)
    }
}

private struct PackageManagerBadge: View {
    let kind: PackageManagerKind
    var size: CGFloat = Metric.badgeSize
    @ScaledMetric(relativeTo: .body) private var glyphScale: CGFloat = 1

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.29, style: .continuous)
            .fill(kind.tint.opacity(0.14))
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: kind.symbol)
                    .font(.system(size: size * 0.42 * glyphScale, weight: .semibold))
                    .foregroundStyle(kind.tint)
                    .accessibilityHidden(true)
            }
            .accessibilityHidden(true)
    }
}

private extension PackageManagerKind {
    var subtitle: String {
        switch self {
        case .npm:
            return "Node.js 包管理器"
        case .pnpm:
            return "快速、节省磁盘空间的包管理器"
        case .homebrew:
            return "macOS 与 Linux 包管理器"
        case .uv:
            return "Python 包与项目管理器"
        }
    }

    var symbol: String {
        switch self {
        case .npm:
            return "shippingbox.fill"
        case .pnpm:
            return "square.stack.3d.up.fill"
        case .homebrew:
            return "mug.fill"
        case .uv:
            return "bolt.fill"
        }
    }

    var tint: Color {
        switch self {
        case .npm:
            return DesignColor.brandTint(red: 0.78, green: 0.20, blue: 0.18)
        case .pnpm:
            return DesignColor.brandTint(red: 0.85, green: 0.55, blue: 0.10)
        case .homebrew:
            return DesignColor.brandTint(red: 0.68, green: 0.44, blue: 0.12)
        case .uv:
            return DesignColor.brandTint(red: 0.35, green: 0.28, blue: 0.72)
        }
    }
}
