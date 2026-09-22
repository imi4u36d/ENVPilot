import SwiftUI
import ENVPilotCore

// MARK: - 运行时

struct RuntimesView: View {
    @ObservedObject var store: NodeRuntimeStore
    @Binding var kind: RuntimeKind

    @State private var searchText = ""
    @State private var recommendedOnly = true
    @State private var pendingUninstall: RuntimeUninstallRequest?
    @State private var filterFocusToken = 0

    private let maximumVisibleCandidates = 40

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            controlBar

            ScrollView {
                VStack(alignment: .leading, spacing: Metric.sectionSpacing) {
                    installedSection
                    availableSection
                }
                .padding(.horizontal, Metric.pagePadding)
                .padding(.vertical, 20)
                .frame(maxWidth: Metric.pageMaxWidth, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .background(DesignColor.canvas)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: kind) {
            searchText = ""
            recommendedOnly = true
            await store.loadCandidates(for: kind)
        }
        .confirmationDialog(
            pendingUninstall?.isCurrent == true ? "无法卸载正在使用的版本" : "确认卸载该运行时？",
            isPresented: uninstallDialogBinding,
            titleVisibility: .visible,
            presenting: pendingUninstall
        ) { request in
            if request.isCurrent {
                Button("知道了", role: .cancel) {}
            } else {
                Button("卸载 \(request.displayName)", role: .destructive) {
                    uninstall(request)
                }
                Button("取消", role: .cancel) {}
            }
        } message: { request in
            if request.isCurrent {
                Text("请先切换到其他版本，再执行卸载。")
            } else {
                Text("将删除 \(request.displayName)。\n\(request.path)")
            }
        }
        .focusedValue(\.runtimeFilterFocus) {
            filterFocusToken += 1
        }
    }

    // MARK: 固定工具栏

    // MARK: 筛选行

    /// 运行时切换、版本搜索、「仅 LTS」都是筛选，放同一行贴着内容列，
    /// 不再往窗口顶部要一条工具栏。
    private var controlBar: some View {
        PageToolbar {
            HStack(spacing: 12) {
                Picker("运行时", selection: $kind) {
                    ForEach(RuntimeKind.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .fixedSize()

                Spacer(minLength: 12)

                SearchField(text: $searchText, placeholder: kind.searchPrompt, focusToken: filterFocusToken)
                    .frame(minWidth: 200, idealWidth: 250, maxWidth: 340, minHeight: 24)
                    .accessibilityLabel(kind.searchPrompt)

                Toggle(kind.filterTitle, isOn: $recommendedOnly)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .fixedSize()
                    .help("只显示长期支持版本")
            }
        }
    }

    // MARK: 已安装

    private var installedSection: some View {
        let summary = store.summary(for: kind)

        return GroupSection(title: "已安装", hint: installedCountLabel(summary)) {
            if summary.options.isEmpty {
                EmptyState(
                    symbol: "tray",
                    title: "本机没有 ENVPilot 管理的 \(kind.title)",
                    message: "在下方选择一个版本安装。"
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(summary.options.enumerated()), id: \.element.id) { index, option in
                        GroupRow(dividerAbove: index > 0) {
                            installedRow(option, isCurrent: summary.current?.id == option.id)
                        }
                    }
                }
            }
        }
    }

    private func installedRow(_ option: InstalledRuntime, isCurrent: Bool) -> some View {
        HStack(alignment: .center, spacing: 12) {
            RuntimeBadge(kind: kind, size: 26)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text(VersionLabel.display(option.kind, option.version))
                        .rowVersionFont()

                    if isCurrent {
                        Pill("当前使用", tone: .positive, symbol: "checkmark.circle.fill")
                    }

                    if option.isManaged {
                        Pill("ENVPilot", tone: .neutral)
                    }
                }

                Text(DisplayPath.short(option.path))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(option.path)
            }

            Spacer(minLength: 12)

            if store.isBusy(key: "switch:\(kind.rawValue)") {
                ProgressView()
                    .controlSize(.small)
            } else if !isCurrent {
                // 列表里会有多个「设为默认」：按钮文案带上版本，VoiceOver 逐条读时
                // 才分得清是哪一条（同文件 :327 已经用了这个写法）。
                Button("将 \(VersionLabel.display(kind, option.version)) 设为默认") {
                    Task { await store.selectDefault(option) }
                }
                .appButton(.secondary, size: .small)
                .disabled(store.isBusy)
                .help("将该版本设为终端默认")
            }

            if option.isManaged {
                Menu {
                    Button("在 Finder 中显示") {
                        DesktopPathActions.revealInFinder(option.path)
                    }
                    Divider()
                    Button("卸载 \(VersionLabel.display(kind, option.version))", role: .destructive) {
                        pendingUninstall = RuntimeUninstallRequest(
                            target: uninstallTarget(option: option, isCurrent: isCurrent)
                        )
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .disabled(store.isBusy)
                .help("更多操作")
                .accessibilityLabel("\(VersionLabel.display(kind, option.version)) 的更多操作")
            }
        }
    }

    // MARK: 可安装版本

    private var availableSection: some View {
        GroupSection(
            title: "可安装版本",
            footer: "来自 \(kind.title) 官方分发。",
            accessory: AnyView(
                Button {
                    Task { await store.loadCandidates(for: kind, force: true) }
                } label: {
                    Label("刷新版本列表", systemImage: "arrow.clockwise")
                }
                .appButton(.quiet, size: .small)
                .disabled(store.isBusy)
                .help("刷新 \(kind.title) 官方版本列表")
            )
        ) {
            candidateList
        }
    }

    @ViewBuilder
    private var candidateList: some View {
        let all = store.candidates(for: kind)
        let visible = filtered(all)

        if all.isEmpty {
            if store.isBusy(key: "candidates:\(kind.rawValue)") {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("正在获取 \(kind.title) 版本列表…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                .padding(Metric.groupPadding)
            } else {
                EmptyState(
                    symbol: "cloud.download",
                    title: "还没有载入 \(kind.title) 版本列表",
                    message: "点击右上角「刷新版本列表」从官方分发读取。"
                )
            }
        } else if visible.isEmpty {
            EmptyState(
                symbol: "magnifyingglass",
                title: "没有匹配的版本",
                message: searchEmptyMessage
            )
        } else {
            VStack(spacing: 0) {
                ForEach(Array(visible.prefix(maximumVisibleCandidates).enumerated()), id: \.element.id) { index, candidate in
                    GroupRow(dividerAbove: index > 0) {
                        candidateRow(candidate)
                    }
                }

                if visible.count > maximumVisibleCandidates {
                    RowDivider()
                    Text("仅显示前 \(maximumVisibleCandidates) 个结果，可用筛选缩小范围。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Metric.rowPadding)
                        .padding(.vertical, 9)
                }
            }
        }
    }

    private var searchEmptyMessage: String {
        if isSearching, recommendedOnly {
            return "没有匹配「\(searchText)」的版本，或已被「\(kind.filterTitle)」过滤。"
        }
        if isSearching {
            return "没有匹配「\(searchText)」的版本。"
        }
        return "已被「\(kind.filterTitle)」过滤，关闭筛选可看到全部版本。"
    }

    private func candidateRow(_ candidate: InstallCandidate) -> some View {
        let key = "install:\(candidate.id)"
        let isInstalling = store.isBusy(key: key)
        let progress = store.progress(forKey: key)
        let summary = store.summary(for: kind)
        let installedOption = summary.options.first { option in
            RuntimeSnapshotReader.matches(
                installed: option.version,
                requested: candidate.argument,
                kind: candidate.kind
            )
        }

        return HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text(candidate.displayVersion)
                        .rowVersionFont()

                    if candidate.isInstalled {
                        Pill("已安装", tone: .positive, symbol: "checkmark.circle.fill")
                    } else if !recommendedOnly, let badge = candidate.badge {
                        // 已打开「仅 LTS」时每行都带同一个标记，属于噪音，这里不再重复。
                        Pill(badge, tone: .informative)
                    }
                }

                Text(candidate.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if isInstalling, let progress {
                    VStack(alignment: .leading, spacing: 4) {
                        if let fraction = progress.fraction {
                            ProgressView(value: fraction)
                                .progressViewStyle(.linear)
                        }
                        Text(progress.message)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .padding(.top, 3)
                }
            }

            Spacer(minLength: 12)

            if candidate.isInstalled {
                if let installedOption, summary.current?.id != installedOption.id {
                    Button {
                        Task { await store.selectDefault(installedOption) }
                    } label: {
                        Label("设为默认", systemImage: "checkmark.circle")
                    }
                    .appButton(.secondary, size: .small)
                    .disabled(store.isBusy)
                    .accessibilityLabel("将 \(candidate.title) 设为默认")
                } else {
                    Image(systemName: "checkmark")
                        .font(.system(.subheadline, weight: .semibold))
                        .foregroundStyle(DesignColor.tertiaryText)
                        .accessibilityLabel("已安装")
                }
            } else if isInstalling {
                // 运行时安装可能是几分钟的下载 + 解包，必须留出口；取消会杀掉整棵
                // 进程树，而不是只把界面切回去。
                Button("取消") {
                    store.cancelOperation(candidate.kind)
                }
                .appButton(.secondary, size: .small)
                .accessibilityLabel("取消安装 \(VersionLabel.display(kind, candidate.displayVersion))")
            } else {
                Button {
                    Task { await store.install(candidate) }
                } label: {
                    Label("安装", systemImage: "square.and.arrow.down")
                }
                .appButton(.secondary, size: .small)
                .disabled(store.isBusy)
                .accessibilityLabel("安装 \(VersionLabel.display(kind, candidate.displayVersion))")
            }
        }
    }

    // MARK: Helpers

    private func installedCountLabel(_ summary: RuntimeSummary) -> String {
        summary.options.isEmpty ? "无" : "\(summary.options.count) 个版本"
    }

    private func filtered(_ candidates: [InstallCandidate]) -> [InstallCandidate] {
        var result = candidates
        if recommendedOnly {
            result = result.filter { $0.isRecommended }
        }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else {
            return result
        }
        return result.filter { candidate in
            [candidate.displayVersion, candidate.subtitle, candidate.argument]
                .joined(separator: " ")
                .lowercased()
                .contains(query)
        }
    }

    private func uninstall(_ request: RuntimeUninstallRequest) {
        pendingUninstall = nil
        guard !request.isCurrent else {
            return
        }
        let kind: RuntimeKind
        let version: String
        switch request.target {
        case .node(let versionValue, _, _):
            kind = .node
            version = versionValue
        case .java(let versionValue, _, _):
            kind = .java
            version = versionValue
        case .python(let versionValue, _, _):
            kind = .python
            version = versionValue
        }
        Task { await store.uninstall(kind: kind, version: version, path: request.path) }
    }

    private func uninstallTarget(option: InstalledRuntime, isCurrent: Bool) -> RuntimeUninstallTarget {
        switch option.kind {
        case .node:
            .node(version: option.version, path: option.path, isCurrent: isCurrent)
        case .java:
            .java(version: option.version, path: option.path, isCurrent: isCurrent)
        case .python:
            .python(version: option.version, path: option.path, isCurrent: isCurrent)
        }
    }

    private var uninstallDialogBinding: Binding<Bool> {
        Binding(
            get: { pendingUninstall != nil },
            set: { isPresented in
                if !isPresented {
                    pendingUninstall = nil
                }
            }
        )
    }
}

enum VersionLabel {
    static func display(_ kind: RuntimeKind, _ version: String) -> String {
        kind == .java ? RuntimeDisplayFormatter.javaVersion(version) : version
    }
}
