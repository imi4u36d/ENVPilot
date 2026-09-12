import SwiftUI
import ENVPilotCore

// MARK: - 运行时

struct RuntimesView: View {
    @ObservedObject var store: NodeRuntimeStore
    @Binding var kind: RuntimeKind

    @State private var searchText = ""
    @State private var recommendedOnly = true
    @State private var pendingUninstall: RuntimeUninstallRequest?
    @FocusState private var searchFocused: Bool

    private let contentWidth: CGFloat = 920
    private let maximumVisibleCandidates = 40

    var body: some View {
        VStack(spacing: 0) {
            controlBar
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 10)
                .frame(maxWidth: contentWidth + 40, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .top)
                .background(.bar)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    installedCard
                    availableCard
                }
                .padding(20)
                .frame(maxWidth: contentWidth, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .top)
            }
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
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    searchFocused = true
                } label: {
                    Label("筛选", systemImage: "magnifyingglass")
                }
                .keyboardShortcut("f", modifiers: .command)
                .help("聚焦版本筛选 (⌘F)")
                .accessibilityLabel("聚焦版本筛选")
            }
        }
    }

    // MARK: Pinned controls

    private var controlBar: some View {
        HStack(spacing: 10) {
            Picker("运行时", selection: $kind) {
                ForEach(RuntimeKind.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .fixedSize()

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                TextField(kind.searchPrompt, text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.callout)
                    .focused($searchFocused)
                    .accessibilityLabel("筛选可安装版本")
            }
            .padding(.horizontal, 9)
            .frame(width: 250, height: 26)
            .background(DesignColor.hairline.opacity(0.25), in: RoundedRectangle(cornerRadius: 6))

            Toggle(kind.filterTitle, isOn: $recommendedOnly)
                .toggleStyle(.switch)
                .controlSize(.small)
                .fixedSize()

            Spacer(minLength: 8)

            Button {
                Task { await store.loadCandidates(for: kind, force: true) }
            } label: {
                Label("重新获取", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .disabled(store.isBusy)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Installed

    private var installedCard: some View {
        let summary = store.summary(for: kind)

        return Card(
            "已安装",
            accessory: AnyView(
                Text(installedCountLabel(summary))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            )
        ) {
            if summary.options.isEmpty {
                EmptyHint(
                    text: "本机没有 ENVPilot 管理的 \(kind.title)。可在下方选择一个版本安装。",
                    symbol: "tray"
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(summary.options.enumerated()), id: \.element.id) { index, option in
                        if index > 0 {
                            Divider()
                        }
                        installedRow(option, isCurrent: summary.current?.id == option.id)
                            .padding(.vertical, 9)
                    }
                }
            }
        }
    }

    private func installedRow(_ option: InstalledRuntime, isCurrent: Bool) -> some View {
        let canUninstall = option.isManaged

        return HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(VersionLabel.display(option.kind, option.version))
                        .font(.callout.monospacedDigit())

                    if isCurrent {
                        Pill("当前使用", tone: .positive, symbol: "checkmark.circle.fill")
                    }

                    if option.isManaged {
                        Pill("ENVPilot", tone: .neutral)
                    }
                }

                Text(option.path)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .help(option.path)
            }

            Spacer(minLength: 10)

            if store.isBusy(key: "switch:\(kind.rawValue)") {
                ProgressView()
                    .controlSize(.small)
            } else if !isCurrent {
                Button("设为默认") {
                    Task { await store.selectDefault(option) }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(store.isBusy)
            }

            if canUninstall {
                Button {
                    pendingUninstall = RuntimeUninstallRequest(
                        target: uninstallTarget(option: option, isCurrent: isCurrent)
                    )
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .help("卸载 \(option.version)")
                .accessibilityLabel("卸载 \(option.version)")
                .disabled(store.isBusy)
            }
        }
    }

    // MARK: Available

    private var availableCard: some View {
        Card(
            "可安装版本",
            accessory: AnyView(
                Text("来自 \(kind.title) 官方分发")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                }
            } else {
                EmptyHint(
                    text: "点击右上角「重新获取」载入 \(kind.title) 官方版本；进入本页时通常已自动获取。",
                    symbol: "cloud.download"
                )
            }
        } else if visible.isEmpty {
            EmptyHint(
                text: "没有匹配「\(searchText)」的版本\(recommendedOnly ? "，或已被「\(kind.filterTitle)」过滤" : "")。",
                symbol: "magnifyingglass"
            )
        } else {
            VStack(spacing: 0) {
                ForEach(Array(visible.prefix(maximumVisibleCandidates).enumerated()), id: \.element.id) { index, candidate in
                    if index > 0 {
                        Divider()
                    }
                    candidateRow(candidate)
                        .padding(.vertical, 9)
                }

                if visible.count > maximumVisibleCandidates {
                    Divider()
                    Text("仅显示前 \(maximumVisibleCandidates) 个结果，可用上方筛选缩小范围。")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 8)
                }
            }
        }
    }

    private func candidateRow(_ candidate: InstallCandidate) -> some View {
        let key = "install:\(candidate.id)"
        let isInstalling = store.isBusy(key: key)
        let progress = store.progress(forKey: key)

        return HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(candidate.displayVersion)
                        .font(.callout.monospacedDigit())

                    if candidate.isInstalled {
                        Pill("已安装", tone: .positive, symbol: "checkmark.circle.fill")
                    } else if let badge = candidate.badge {
                        Pill(badge, tone: .informative)
                    }
                }

                Text(candidate.subtitle)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                if isInstalling, let progress {
                    VStack(alignment: .leading, spacing: 4) {
                        if let fraction = progress.fraction {
                            ProgressView(value: fraction)
                                .progressViewStyle(.linear)
                        }
                        Text(progress.message)
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .padding(.top, 2)
                }
            }

            Spacer(minLength: 10)

            if candidate.isInstalled {
                Text("已安装")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else if !isInstalling {
                Button {
                    Task { await store.install(candidate) }
                } label: {
                    Label("安装", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(store.isBusy)
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

struct EmptyHint: View {
    let text: String
    let symbol: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol)
                .font(.caption)
                .foregroundStyle(.tertiary)
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }
}

enum VersionLabel {
    static func display(_ kind: RuntimeKind, _ version: String) -> String {
        kind == .java ? RuntimeDisplayFormatter.javaVersion(version) : version
    }
}
