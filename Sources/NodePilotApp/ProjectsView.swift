import SwiftUI
import AppKit
import ENVPilotCore

// MARK: - 项目

struct ProjectsView: View {
    @ObservedObject var store: NodeRuntimeStore
    var onOpenRuntime: (RuntimeKind) -> Void

    @State private var pathInput = ""

    var body: some View {
        PageContainer {
            strategySection
            locationSection
            resolutionSection
            if !store.recentProjectPaths.isEmpty {
                recentsSection
            }
        }
    }

    // MARK: 版本来源

    private var strategySection: some View {
        GroupSection(title: "版本来源", footer: strategyHelp) {
            GroupRow {
                HStack(alignment: .center, spacing: 14) {
                    Text("解析方式")
                        .font(.callout)

                    Picker("版本来源", selection: preferenceBinding) {
                        Text("跟随项目 .envpilot").tag(ProjectVersionPreference.followProjectFiles)
                        Text("始终使用全局版本").tag(ProjectVersionPreference.globalDefault)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .fixedSize()

                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var strategyHelp: String {
        switch store.snapshot?.settings.projectVersionPreference ?? .followProjectFiles {
        case .followProjectFiles:
            return "进入含 .envpilot 的目录时，优先使用其中声明的版本；没有声明时使用全局默认版本。"
        case .globalDefault:
            return "忽略项目内的 .envpilot，所有终端统一使用全局默认版本。"
        }
    }

    private var preferenceBinding: Binding<ProjectVersionPreference> {
        Binding(
            get: { store.snapshot?.settings.projectVersionPreference ?? .followProjectFiles },
            set: { newValue in
                guard newValue != store.snapshot?.settings.projectVersionPreference else {
                    return
                }
                Task { await store.setProjectPreference(newValue) }
            }
        )
    }

    // MARK: 项目目录

    private var locationSection: some View {
        GroupSection(
            title: "项目目录",
            accessory: AnyView(
                Button {
                    chooseFolder()
                } label: {
                    Label("选择文件夹…", systemImage: "folder.badge.plus")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
            )
        ) {
            GroupRow {
                pathPicker
            }
        }
    }

    // MARK: 解析结果

    private var resolutionSection: some View {
        GroupSection(title: "解析结果", hint: resolutionHint) {
            if store.snapshot == nil {
                GroupRow {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text("正在读取运行时信息…")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                    }
                }
            } else if let project = store.projectSnapshot {
                projectDetails(project)
            } else {
                emptyInspector
            }
        }
    }

    private var resolutionHint: String? {
        guard store.snapshot != nil else {
            return nil
        }
        guard store.inspectedDirectory != nil else {
            return nil
        }
        guard let file = store.projectSnapshot?.envPilotFile else {
            return "未发现 .envpilot"
        }
        return abbreviated(file.path)
    }

    private var pathPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "folder")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)

                Text(store.inspectedDirectory.map { abbreviated($0.path) } ?? "未选择项目目录")
                    .font(.callout.monospaced())
                    .foregroundStyle(store.inspectedDirectory == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(store.inspectedDirectory?.path ?? "未选择项目目录")

                Spacer(minLength: 6)

                if store.inspectedDirectory != nil {
                    Button("清除") {
                        store.setProjectDirectory(nil)
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                }
            }

            HStack(spacing: 8) {
                TextField("或直接粘贴项目路径，例如 ~/work/my-app", text: $pathInput)
                    .textFieldStyle(.roundedBorder)
                    .font(.callout)
                    .onSubmit(submitPath)

                Button("检查") {
                    submitPath()
                }
                .buttonStyle(.bordered)
                .disabled(pathInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private var emptyInspector: some View {
        EmptyState(
            symbol: "folder.badge.questionmark",
            title: "还没有选择项目目录",
            message: "选择项目根目录后，可以看到 .envpilot 会解析出哪些版本、这些版本是否已安装。"
        ) {
            Button("选择项目文件夹…") {
                chooseFolder()
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func projectDetails(_ project: ProjectEnvironmentSnapshot) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(project.entries.enumerated()), id: \.element.id) { index, entry in
                GroupRow(dividerAbove: index > 0) {
                    projectEntryRow(entry)
                }
            }

            RowDivider()
            GroupRow {
                applyRow(project)
            }
        }
    }

    private func projectEntryRow(_ entry: ProjectRuntimeEntry) -> some View {
        HStack(alignment: .center, spacing: 12) {
            RuntimeBadge(kind: entry.kind, size: 26, isActive: entry.isSatisfied)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text(entry.kind.title)
                        .font(.callout.weight(.medium))

                    if !entry.usesProjectDeclaration {
                        Pill("全局", tone: .neutral)
                    }

                    if entry.declaredVersion != nil {
                        if entry.isSatisfied {
                            Pill("已安装", tone: .positive, symbol: "checkmark.circle.fill")
                        } else {
                            Pill("未安装", tone: .warning)
                        }
                    }
                }

                Text(entryDetail(entry))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }

            Spacer(minLength: 12)

            if entry.declaredVersion != nil, !entry.isSatisfied {
                Button("去安装") {
                    onOpenRuntime(entry.kind)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else if let matched = entry.matchedInstallation {
                Text(VersionLabel.display(entry.kind, matched.version))
                    .rowVersionFont()
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func entryDetail(_ entry: ProjectRuntimeEntry) -> String {
        if let declared = entry.declaredVersion {
            if let matched = entry.matchedInstallation {
                return "\(entry.kind.envPilotKey)=\(declared) → \(abbreviated(matched.path))"
            }
            return "\(entry.kind.envPilotKey)=\(declared) → 本机没有该版本"
        }
        if entry.effectiveVersion == RuntimeSummary.emptyVersion {
            return "未声明，且没有全局默认版本"
        }
        return "未声明，使用全局默认 \(entry.effectiveVersion)"
    }

    private func applyRow(_ project: ProjectEnvironmentSnapshot) -> some View {
        let command = "cd '\(project.directory.path)' && exec zsh -l"

        return VStack(alignment: .leading, spacing: 8) {
            Text("已在该项目目录中的终端，可重载 shell 立即生效：")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Text(command)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: 6)

                Button {
                    WindowActions.copy(command)
                } label: {
                    Label("复制", systemImage: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)

                Button {
                    DesktopPathActions.revealInFinder(project.directory.path)
                } label: {
                    Image(systemName: "folder")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .help("在 Finder 中显示")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(DesignColor.well, in: RoundedRectangle(cornerRadius: 6))
        }
    }

    // MARK: 最近项目

    private var recentsSection: some View {
        GroupSection(title: "最近项目") {
            VStack(spacing: 0) {
                ForEach(Array(store.recentProjectPaths.enumerated()), id: \.offset) { index, path in
                    GroupRow(dividerAbove: index > 0) {
                        HStack(spacing: 8) {
                            Text(abbreviated(path))
                                .font(.callout.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .help(path)

                            Spacer(minLength: 6)

                            Button("检查") {
                                store.setProjectDirectory(path)
                            }
                            .buttonStyle(.borderless)
                            .controlSize(.small)

                            Button {
                                store.forgetProject(path)
                            } label: {
                                Image(systemName: "xmark")
                            }
                            .buttonStyle(.borderless)
                            .controlSize(.small)
                            .help("从列表移除")
                            .accessibilityLabel("从列表移除")
                        }
                    }
                }
            }
        }
    }

    // MARK: Actions

    private func submitPath() {
        let value = pathInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            return
        }
        let expanded = (value as NSString).expandingTildeInPath
        store.setProjectDirectory(expanded)
        pathInput = ""
    }

    private func chooseFolder() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "检查此项目"
        panel.message = "选择项目目录，ENVPilot 会读取其中的 .envpilot"
        if let directory = store.inspectedDirectory {
            panel.directoryURL = directory
        }
        if panel.runModal() == .OK, let url = panel.url {
            store.setProjectDirectory(url.path)
        }
    }

    private func abbreviated(_ path: String) -> String {
        path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }
}
