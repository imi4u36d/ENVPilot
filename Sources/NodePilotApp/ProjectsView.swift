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
            strategyCard
            inspectorCard
            if !store.recentProjectPaths.isEmpty {
                recentsCard
            }
        }
    }

    // MARK: Strategy

    private var strategyCard: some View {
        Card("版本来源") {
            VStack(alignment: .leading, spacing: 10) {
                Picker("版本来源", selection: preferenceBinding) {
                    Text("跟随项目 .envpilot").tag(ProjectVersionPreference.followProjectFiles)
                    Text("始终使用全局版本").tag(ProjectVersionPreference.globalDefault)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .fixedSize()

                Text(strategyHelp)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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

    // MARK: Inspector

    private var inspectorCard: some View {
        Card(
            "项目检查器",
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
            VStack(alignment: .leading, spacing: 12) {
                pathRow

                if store.snapshot == nil {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text("正在读取运行时信息…")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                } else if let project = store.projectSnapshot {
                    projectDetails(project)
                } else {
                    EmptyHint(
                        text: "选择一个项目目录，即可查看它的 .envpilot 会解析出哪些版本、这些版本是否已安装。",
                        symbol: "questionmark.circle"
                    )
                }
            }
        }
    }

    private var pathRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "folder")
                    .foregroundStyle(.secondary)
                Text(store.inspectedDirectory.map { abbreviated($0.path) } ?? "未选择项目目录")
                    .font(.callout.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
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
                    .textFieldStyle(.plain)
                    .font(.callout)
                    .onSubmit(submitPath)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(DesignColor.hairline.opacity(0.25), in: RoundedRectangle(cornerRadius: 6))

                Button("检查") {
                    submitPath()
                }
                .buttonStyle(.bordered)
                .disabled(pathInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func projectDetails(_ project: ProjectEnvironmentSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()

            VStack(spacing: 0) {
                ForEach(project.entries) { entry in
                    projectEntryRow(entry)
                    if entry.id != project.entries.last?.id {
                        Divider()
                    }
                }
            }

            Divider()

            applyRow(project)
        }
    }

    private func projectEntryRow(_ entry: ProjectRuntimeEntry) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: entry.kind.symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(entry.kind.title)
                        .font(.callout)

                    if !entry.usesProjectDeclaration {
                        Pill("全局", tone: .neutral)
                    }

                    if entry.declaredVersion != nil {
                        if entry.isSatisfied {
                            Pill("已安装", tone: .positive, symbol: "checkmark.circle.fill")
                        } else {
                            Pill("未安装", tone: .warning, symbol: "exclamationmark.triangle.fill")
                        }
                    }
                }

                Text(entryDetail(entry))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }

            Spacer(minLength: 10)

            if entry.declaredVersion != nil, !entry.isSatisfied {
                Button("去安装") {
                    onOpenRuntime(entry.kind)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 9)
    }

    private func entryDetail(_ entry: ProjectRuntimeEntry) -> String {
        if let declared = entry.declaredVersion {
            if let matched = entry.matchedInstallation {
                return "\(entry.kind.envPilotKey)=\(declared) → \(matched.path)"
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
            .background(DesignColor.hairline.opacity(0.25), in: RoundedRectangle(cornerRadius: 6))
        }
    }

    // MARK: Recents

    private var recentsCard: some View {
        Card("最近项目") {
            VStack(spacing: 0) {
                ForEach(Array(store.recentProjectPaths.enumerated()), id: \.offset) { index, path in
                    if index > 0 {
                        Divider()
                    }
                    HStack(spacing: 8) {
                        Text(abbreviated(path))
                            .font(.callout.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 6)
                        Button {
                            store.setProjectDirectory(path)
                        } label: {
                            Text("检查")
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
                    .padding(.vertical, 8)
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
