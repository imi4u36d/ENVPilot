import SwiftUI
import ENVPilotCore

struct MenuBarContentView: View {
    @ObservedObject var store: NodeRuntimeStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if store.isLoading {
                progressBanner
            }
            Divider()
            nodeQuickSection
            Divider()
            jdkQuickSection
            if let message = store.latestError {
                Divider()
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            Divider()
            footerActions
        }
        .padding(12)
        .frame(minWidth: 420)
        .task {
            await store.refresh()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("ENVPilot")
                .font(.headline)
            Text("Node 当前命令版本: \(store.displayNodeVersion)")
                .font(.subheadline)
            Text("Node 当前命令路径: \(store.snapshot?.activeNodePath ?? "--")")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text("JDK 已选版本: \(store.displayJavaVersion)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var progressBanner: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text(store.loadingMessage ?? "正在处理...")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var nodeQuickSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Node 切换")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let snapshot = store.snapshot {
                if snapshot.installations.isEmpty {
                    Text("未发现可切换的 Node 版本")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(snapshot.installations.prefix(6)) { item in
                        Button {
                            Task { await store.setDefaultNode(version: item.version) }
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text("Node \(item.version)")
                                    Spacer()
                                    if isNodeSelected(item: item, snapshot: snapshot) {
                                        tag("已选中", color: .green)
                                    }
                                }
                                Text(item.installPath)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(store.isLoading)
                    }
                }
            }
        }
    }

    private var jdkQuickSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("JDK 切换")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let snapshot = store.snapshot, !snapshot.javaInstallations.isEmpty {
                ForEach(snapshot.javaInstallations.prefix(6)) { jdk in
                    Button {
                        Task { await store.setDefaultJava(version: jdk.version, homePath: jdk.homePath) }
                    } label: {
                        HStack {
                            Text("JDK \(jdk.version)")
                            Spacer()
                            if snapshot.settings.selectedJavaHome == jdk.homePath {
                                tag("已选中", color: .green)
                            } else if snapshot.activeJavaHome == jdk.homePath {
                                tag("运行中", color: .blue)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(store.isLoading)
                }
            } else {
                Text("未发现已安装 JDK")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var footerActions: some View {
        HStack {
            Button("刷新") {
                Task { await store.refresh() }
            }
            .disabled(store.isLoading)

            Button("打开设置") {
                openWindow(id: "settings")
            }

            Spacer()

            Button("退出") {
                NSApplication.shared.terminate(nil)
            }
        }
    }

    private func isNodeSelected(item: NodeInstallation, snapshot: NodeRuntimeSnapshot) -> Bool {
        snapshot.settings.selectedVersion == item.version
    }

    @ViewBuilder
    private func tag(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.2))
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

struct SettingsView: View {
    @ObservedObject var store: NodeRuntimeStore

    @State private var selectedProfileID: UUID?
    @State private var draftProfile = EnvironmentProfile(name: "")
    @State private var newProfileName = ""
    @State private var nodeVersionInput = ""
    @State private var projectPreference: ProjectVersionPreference = .followProjectFiles
    @State private var isSynchronizing = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if store.isLoading {
                        progressBanner
                    }
                    if let message = store.latestError {
                        GroupBox {
                            Text(message)
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    overviewSection
                    nodeSwitchSection
                    jdkSwitchSection
                    installToolsSection
                    projectPreferenceSection
                    profileSelectionSection
                    profileEditorSection
                }
                .padding(24)
            }
            .navigationTitle("ENVPilot 设置")
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button("刷新") {
                        Task { await store.refresh() }
                    }
                    .disabled(store.isLoading)
                }
            }
        }
        .task {
            if store.snapshot == nil {
                await store.refresh()
            }
            synchronizeFromSnapshot()
        }
        .onChange(of: store.snapshot?.settings.selectedProfileID) { _ in
            synchronizeFromSnapshot()
        }
        .onChange(of: store.snapshot?.settings.projectVersionPreference) { _ in
            synchronizeFromSnapshot()
        }
        .onChange(of: store.snapshot?.settings.profiles.map(\.id) ?? []) { _ in
            synchronizeFromSnapshot()
        }
        .onChange(of: selectedProfileID) { newValue in
            guard !isSynchronizing, let newValue else {
                return
            }
            if let selected = profiles.first(where: { $0.id == newValue }) {
                draftProfile = selected
            }
            Task { await store.setSelectedProfile(id: newValue) }
        }
        .onChange(of: projectPreference) { newValue in
            guard !isSynchronizing else {
                return
            }
            Task { await store.setProjectVersionPreference(newValue) }
        }
    }

    private var profiles: [EnvironmentProfile] {
        store.snapshot?.settings.profiles ?? []
    }

    private var progressBanner: some View {
        GroupBox {
            HStack(spacing: 10) {
                ProgressView()
                Text(store.loadingMessage ?? "正在处理...")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var overviewSection: some View {
        GroupBox("运行时概览") {
            VStack(alignment: .leading, spacing: 8) {
                LabeledContent("Node 配置版本") {
                    Text(store.configuredNodeVersion)
                }
                LabeledContent("Node 配置状态") {
                    Text(store.configuredNodeStatus)
                }
                LabeledContent("Node 配置路径") {
                    Text(store.configuredNodeInstallation?.installPath ?? "--")
                }
                LabeledContent("Node 命令版本") {
                    Text(store.snapshot?.activeVersion ?? "--")
                }
                LabeledContent("Node 命令路径") {
                    Text(store.snapshot?.activeNodePath ?? "--")
                }
                LabeledContent("JDK 已选版本") {
                    Text(store.displayJavaVersion)
                }
                LabeledContent("JDK 命令版本") {
                    Text(store.snapshot?.activeJavaVersion ?? "--")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var nodeSwitchSection: some View {
        GroupBox("Node（NVM）") {
            VStack(alignment: .leading, spacing: 12) {
                Text("仅支持 NVM 管理 Node 版本。若本机没有 NVM，会尝试通过 Homebrew 自动安装。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    TextField("输入版本号，如 24、24.11.1、lts", text: $nodeVersionInput)
                        .disabled(store.isLoading)
                    Button("安装") {
                        let version = nodeVersionInput.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !version.isEmpty else {
                            return
                        }
                        nodeVersionInput = ""
                        Task { await store.installNode(version: version) }
                    }
                    .disabled(store.isLoading || nodeVersionInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                Text("版本")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if let installations = store.snapshot?.installations, !installations.isEmpty {
                    ForEach(installations) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Node \(item.version)")
                                Spacer()
                                if isNodeSelected(item: item) {
                                    tag("已选中", color: .green)
                                }
                                Button("切换") {
                                    Task { await store.setDefaultNode(version: item.version) }
                                }
                                .disabled(store.isLoading)
                                Button("卸载") {
                                    Task { await store.uninstallNode(version: item.version) }
                                }
                                .disabled(store.isLoading)
                            }
                            Text(item.installPath)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("未发现通过 NVM 安装的 Node 版本，可直接在上方输入版本并安装。")
                        if let selectedVersion = store.snapshot?.settings.selectedVersion, !selectedVersion.isEmpty {
                            Text("当前配置版本是 \(selectedVersion)，但它不在 NVM 检测列表中。")
                        }
                        if let activePath = store.snapshot?.activeNodePath, !activePath.isEmpty {
                            Text("当前 node 命令来自 \(activePath)。")
                        }
                    }
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var jdkSwitchSection: some View {
        GroupBox("JDK 单独切换") {
            if let javaInstallations = store.snapshot?.javaInstallations, !javaInstallations.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(javaInstallations) { jdk in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("JDK \(jdk.version)")
                                Spacer()
                                if store.snapshot?.settings.selectedJavaHome == jdk.homePath {
                                    tag("已选中", color: .green)
                                }
                                Button("切换") {
                                    Task { await store.setDefaultJava(version: jdk.version, homePath: jdk.homePath) }
                                }
                                .disabled(store.isLoading)
                            }
                            Text(jdk.homePath)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }
            } else {
                Text("未发现本机 JDK。")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var installToolsSection: some View {
        GroupBox("组件安装") {
            if let statuses = store.snapshot?.componentAvailabilities, !statuses.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(statuses) { status in
                        HStack {
                            Text(status.component.displayName)
                            Spacer()
                            if status.isInstalled {
                                Text("已安装")
                                    .foregroundStyle(.secondary)
                            } else if status.isInstallSupported {
                                if isInstalling(status.component) {
                                    HStack(spacing: 6) {
                                        ProgressView()
                                            .controlSize(.small)
                                        Text("下载安装中...")
                                            .foregroundStyle(.secondary)
                                    }
                                } else {
                                    Button("一键安装") {
                                        Task { await store.installComponent(status.component) }
                                    }
                                    .disabled(store.isLoading)
                                }
                            } else {
                                Text("当前环境不可安装")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } else {
                Text("暂无安装状态信息")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var projectPreferenceSection: some View {
        GroupBox("项目版本策略") {
            Picker("Node 版本来源", selection: $projectPreference) {
                Text("跟随 .nvmrc/.node-version").tag(ProjectVersionPreference.followProjectFiles)
                Text("始终使用全局已选版本").tag(ProjectVersionPreference.globalDefault)
            }
            .pickerStyle(.segmented)
            .disabled(store.isLoading)
        }
    }

    private var profileSelectionSection: some View {
        GroupBox("环境配置") {
            VStack(alignment: .leading, spacing: 12) {
                if profiles.isEmpty {
                    Text("当前没有可用配置。")
                        .foregroundStyle(.secondary)
                } else {
                    Picker("当前配置", selection: $selectedProfileID) {
                        ForEach(profiles) { profile in
                            Text(profile.name).tag(Optional(profile.id))
                        }
                    }
                    .disabled(store.isLoading)
                }

                HStack {
                    TextField("新配置名称", text: $newProfileName)
                        .disabled(store.isLoading)
                    Button("创建") {
                        let name = newProfileName
                        newProfileName = ""
                        Task { await store.createProfile(named: name) }
                    }
                    .disabled(store.isLoading)
                }
            }
        }
    }

    private var profileEditorSection: some View {
        GroupBox("配置编辑") {
            if selectedProfileID == nil {
                Text("请选择或创建一个配置后再编辑环境变量。")
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    TextField("配置名称", text: $draftProfile.name)
                        .disabled(store.isLoading)
                    TextField("npm registry", text: $draftProfile.npmRegistry)
                        .disabled(store.isLoading)
                    TextField("pnpm registry", text: $draftProfile.pnpmRegistry)
                        .disabled(store.isLoading)
                    TextField("yarn registry", text: $draftProfile.yarnRegistry)
                        .disabled(store.isLoading)
                    TextField("NODE_OPTIONS", text: $draftProfile.nodeOptions)
                        .disabled(store.isLoading)

                    Divider()
                    Text("自定义环境变量")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if draftProfile.variables.isEmpty {
                        Text("暂无自定义变量。")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }

                    ForEach(Array(draftProfile.variables.indices), id: \.self) { index in
                        HStack {
                            TextField("KEY", text: $draftProfile.variables[index].key)
                                .textFieldStyle(.roundedBorder)
                                .disabled(store.isLoading)
                            TextField("VALUE", text: $draftProfile.variables[index].value)
                                .textFieldStyle(.roundedBorder)
                                .disabled(store.isLoading)
                            Button("删除") {
                                draftProfile.variables.remove(at: index)
                            }
                            .disabled(store.isLoading)
                        }
                    }

                    HStack {
                        Button("新增变量") {
                            draftProfile.variables.append(CustomEnvironmentVariable(key: "", value: ""))
                        }
                        .disabled(store.isLoading)
                        Spacer()
                        Button("重置") {
                            synchronizeFromSnapshot()
                        }
                        .disabled(store.isLoading)
                        Button("保存配置") {
                            Task { await store.saveProfile(draftProfile) }
                        }
                        .disabled(store.isLoading || draftProfile.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        }
    }

    private func synchronizeFromSnapshot() {
        guard let snapshot = store.snapshot else {
            return
        }

        isSynchronizing = true
        defer { isSynchronizing = false }

        projectPreference = snapshot.settings.projectVersionPreference
        let availableProfiles = snapshot.settings.profiles

        let preferredID = snapshot.settings.selectedProfileID ?? availableProfiles.first?.id
        selectedProfileID = preferredID

        if let preferredID,
           let selected = availableProfiles.first(where: { $0.id == preferredID }) {
            draftProfile = selected
        } else if let first = availableProfiles.first {
            draftProfile = first
        }
    }

    private func isInstalling(_ component: InstallableComponent) -> Bool {
        guard store.isLoading, let loadingMessage = store.loadingMessage else {
            return false
        }
        return loadingMessage.contains(component.displayName)
    }

    private func isNodeSelected(item: NodeInstallation) -> Bool {
        guard let snapshot = store.snapshot else {
            return false
        }
        return snapshot.settings.selectedVersion == item.version
    }

    @ViewBuilder
    private func tag(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.2))
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}
