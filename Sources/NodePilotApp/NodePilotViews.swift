import SwiftUI
import ENVPilotCore

struct MenuBarContentView: View {
    @ObservedObject var store: NodeRuntimeStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        ZStack {
            PilotBackground()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) {
                    heroCard
                    if store.isLoading {
                        progressCard
                    }
                    nodeQuickSection
                    jdkQuickSection
                    if let message = store.latestError {
                        errorCard(message: message)
                    }
                    footerActions
                }
                .padding(12)
            }
        }
        .frame(minWidth: 460, minHeight: 540)
        .task {
            await store.refresh()
        }
    }

    private var heroCard: some View {
        PilotCard(tint: .blue.opacity(0.14)) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("ENVPilot")
                            .font(.title3.weight(.semibold))
                        Text("开发运行时面板")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    PilotBadge(
                        text: store.isLoading ? "同步中" : "在线",
                        color: store.isLoading ? .orange : .green
                    )
                }

                HStack(spacing: 8) {
                    metricPill(
                        title: "Node",
                        value: store.displayNodeVersion,
                        symbol: "shippingbox"
                    )
                    metricPill(
                        title: "JDK",
                        value: store.displayJavaVersion,
                        symbol: "cup.and.saucer"
                    )
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Node 当前路径")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(store.snapshot?.activeNodePath ?? "--")
                        .font(.caption)
                        .lineLimit(1)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private var progressCard: some View {
        PilotCard(tint: .orange.opacity(0.10)) {
            VStack(alignment: .leading, spacing: 8) {
                ProgressView()
                    .progressViewStyle(.linear)
                Text(store.loadingMessage ?? "正在处理...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var nodeQuickSection: some View {
        PilotCard {
            VStack(alignment: .leading, spacing: 10) {
                sectionHeader(
                    title: "Node 快速切换",
                    subtitle: "显示前 6 个已安装版本"
                )

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
                                HStack(spacing: 10) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Node \(item.version)")
                                            .font(.subheadline.weight(.medium))
                                        Text(item.installPath)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    if isNodeSelected(item: item, snapshot: snapshot) {
                                        PilotBadge(text: "已选中", color: .green)
                                    }
                                    Image(systemName: "arrow.right.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .padding(10)
                                .background(PilotPalette.rowBackground)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .disabled(store.isLoading)
                        }
                    }
                } else {
                    Text("正在载入运行时信息...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var jdkQuickSection: some View {
        PilotCard {
            VStack(alignment: .leading, spacing: 10) {
                sectionHeader(
                    title: "JDK 快速切换",
                    subtitle: "通过 JAVA_HOME 应用到终端会话"
                )

                if let snapshot = store.snapshot, !snapshot.javaInstallations.isEmpty {
                    ForEach(snapshot.javaInstallations.prefix(6)) { jdk in
                        Button {
                            Task { await store.setDefaultJava(version: jdk.version, homePath: jdk.homePath) }
                        } label: {
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("JDK \(jdk.version)")
                                        .font(.subheadline.weight(.medium))
                                    Text(jdk.homePath)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                if snapshot.settings.selectedJavaHome == jdk.homePath {
                                    PilotBadge(text: "已选中", color: .green)
                                } else if snapshot.activeJavaHome == jdk.homePath {
                                    PilotBadge(text: "运行中", color: .blue)
                                }
                                Image(systemName: "arrow.right.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .padding(10)
                            .background(PilotPalette.rowBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
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
    }

    private func errorCard(message: String) -> some View {
        PilotCard(tint: .red.opacity(0.10)) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var footerActions: some View {
        PilotCard {
            HStack(spacing: 8) {
                Button("刷新") {
                    Task { await store.refresh() }
                }
                .buttonStyle(.bordered)
                .disabled(store.isLoading)

                Button("打开设置") {
                    openWindow(id: "settings")
                }
                .buttonStyle(.borderedProminent)

                Spacer()

                Button {
                    NSApp.terminate(nil)
                } label: {
                    Text("退出")
                        .font(.body)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(Color.red.opacity(0.14))
                        )
                        .overlay(
                            Capsule()
                                .stroke(Color.red.opacity(0.18), lineWidth: 1)
                        )
                        .foregroundStyle(Color.red)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func metricPill(title: String, value: String, symbol: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
            Text(title)
                .font(.caption.weight(.medium))
            Text(value)
                .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(PilotPalette.pillBackground)
        .clipShape(Capsule())
    }

    private func sectionHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.headline)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func isNodeSelected(item: NodeInstallation, snapshot: NodeRuntimeSnapshot) -> Bool {
        snapshot.settings.selectedVersion == item.version
    }
}

struct SettingsView: View {
    @ObservedObject var store: NodeRuntimeStore

    @State private var selectedProfileID: UUID?
    @State private var draftProfile = EnvironmentProfile(name: "")
    @State private var newProfileName = ""
    @State private var nodeVersionInput = ""
    @State private var sdkmanJavaIdentifierInput = ""
    @State private var sdkmanSearchText = ""
    @State private var projectPreference: ProjectVersionPreference = .followProjectFiles
    @State private var isSynchronizing = false

    var body: some View {
        NavigationStack {
            ZStack {
                PilotBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        overviewSection

                        if store.isLoading {
                            progressBanner
                        }
                        if let message = store.latestError {
                            errorCard(message: message)
                        }

                        nodeSwitchSection
                        jdkSwitchSection
                        projectPreferenceSection
                        profileSelectionSection
                        profileEditorSection
                    }
                    .padding(24)
                }
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
        PilotCard(tint: .orange.opacity(0.10)) {
            VStack(alignment: .leading, spacing: 10) {
                ProgressView()
                    .progressViewStyle(.linear)
                Text(store.loadingMessage ?? "正在处理...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var overviewSection: some View {
        PilotCard(tint: .blue.opacity(0.12)) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("运行时概览")
                            .font(.title3.weight(.semibold))
                        Text("当前会话与已配置版本状态")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    PilotBadge(text: store.configuredNodeStatus, color: .blue)
                }

                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                    spacing: 10
                ) {
                    metricTile("Node 配置版本", value: store.configuredNodeVersion)
                    metricTile("Node 命令版本", value: store.snapshot?.activeVersion ?? "--")
                    metricTile("JDK 已选版本", value: store.displayJavaVersion)
                    metricTile("JDK 命令版本", value: store.snapshot?.activeJavaVersion ?? "--")
                }

                Divider()

                keyValueLine("Node 配置路径", value: store.configuredNodeInstallation?.installPath ?? "--")
                keyValueLine("Node 命令路径", value: store.snapshot?.activeNodePath ?? "--")
            }
        }
    }

    private var nodeSwitchSection: some View {
        PilotCard {
            VStack(alignment: .leading, spacing: 12) {
                sectionTitle("Node（NVM）", subtitle: "安装 / 切换 / 卸载")

                Text("仅支持 NVM 管理 Node 版本。启动时若未检测到 Homebrew，会先自动安装 Homebrew，再安装 NVM。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    TextField("输入版本号，如 24、24.11.1、lts", text: $nodeVersionInput)
                        .textFieldStyle(.roundedBorder)
                        .disabled(store.isLoading)
                    Button("安装") {
                        let version = nodeVersionInput.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !version.isEmpty else {
                            return
                        }
                        nodeVersionInput = ""
                        Task { await store.installNode(version: version) }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(store.isLoading || nodeVersionInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if let installations = store.snapshot?.installations, !installations.isEmpty {
                    ForEach(installations) { item in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Node \(item.version)")
                                    .font(.subheadline.weight(.medium))
                                Spacer()
                                if isNodeSelected(item: item) {
                                    PilotBadge(text: "已选中", color: .green)
                                }
                                Button("切换") {
                                    Task { await store.setDefaultNode(version: item.version) }
                                }
                                .buttonStyle(.bordered)
                                .disabled(store.isLoading)
                                Button("卸载") {
                                    Task { await store.uninstallNode(version: item.version) }
                                }
                                .buttonStyle(.bordered)
                                .disabled(store.isLoading)
                            }
                            Text(item.installPath)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                        .padding(10)
                        .background(PilotPalette.rowBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
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
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(10)
                    .background(PilotPalette.rowBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
        }
    }

    private var jdkSwitchSection: some View {
        PilotCard {
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("JDK 单独切换", subtitle: "兼容系统 JDK 与 SDKMAN 安装")

                Text("推荐使用 SDKMAN 管理和安装 JDK；切换后会通过 JAVA_HOME 生效。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                sdkmanControlPanel

                if let javaInstallations = store.snapshot?.javaInstallations, !javaInstallations.isEmpty {
                    ForEach(javaInstallations) { jdk in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("JDK \(jdk.version)")
                                    .font(.subheadline.weight(.medium))
                                Spacer()
                                if let sdkmanIdentifier = JavaRuntimeDetector.sdkmanJavaIdentifier(fromHomePath: jdk.homePath) {
                                    PilotBadge(text: "SDKMAN", color: .orange)
                                    Text(sdkmanIdentifier)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                if store.snapshot?.settings.selectedJavaHome == jdk.homePath {
                                    PilotBadge(text: "已选中", color: .green)
                                } else if store.snapshot?.activeJavaHome == jdk.homePath {
                                    PilotBadge(text: "运行中", color: .blue)
                                }
                                Button("切换") {
                                    Task { await store.setDefaultJava(version: jdk.version, homePath: jdk.homePath) }
                                }
                                .buttonStyle(.bordered)
                                .disabled(store.isLoading)
                                if let sdkmanIdentifier = JavaRuntimeDetector.sdkmanJavaIdentifier(fromHomePath: jdk.homePath) {
                                    Button("卸载") {
                                        Task { await store.uninstallJavaWithSDKMAN(identifier: sdkmanIdentifier) }
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(store.isLoading)
                                }
                            }
                            Text(jdk.homePath)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                        .padding(10)
                        .background(PilotPalette.rowBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("未发现本机 JDK。")
                        Text("可先安装 SDKMAN，再在上方输入 candidate id 安装 JDK。")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(10)
                    .background(PilotPalette.rowBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
        }
    }

    private var sdkmanControlPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                PilotBadge(
                    text: store.sdkmanStatus.isInstalled ? "SDKMAN 已就绪" : "SDKMAN 未安装",
                    color: store.sdkmanStatus.isInstalled ? .green : .orange
                )
                Text(store.sdkmanStatusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if !store.sdkmanStatus.isInstalled, store.sdkmanStatus.canInstall {
                    Button("安装 SDKMAN") {
                        Task { await store.installSDKMAN() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(store.isLoading)
                }
            }

            HStack(spacing: 10) {
                TextField("输入 SDKMAN candidate id，如 21.0.4-tem、17.0.12-zulu", text: $sdkmanJavaIdentifierInput)
                    .textFieldStyle(.roundedBorder)
                    .disabled(store.isLoading)
                Button("安装 JDK") {
                    let identifier = trimmedSDKMANJavaIdentifier
                    guard !identifier.isEmpty else {
                        return
                    }
                    sdkmanJavaIdentifierInput = ""
                    Task { await store.installJavaWithSDKMAN(identifier: identifier) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.isLoading || trimmedSDKMANJavaIdentifier.isEmpty)
            }

            if store.sdkmanStatus.isInstalled {
                HStack(spacing: 10) {
                    TextField("模糊查询 Java candidate，如 tem、17、zulu", text: $sdkmanSearchText)
                        .textFieldStyle(.roundedBorder)
                        .disabled(store.isLoading)
                    Button("查询版本") {
                        Task { await store.querySDKMANJavaCandidates() }
                    }
                    .buttonStyle(.bordered)
                    .disabled(store.isLoading)
                }

                if !store.sdkmanJavaCandidates.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(filteredSDKMANJavaCandidates.prefix(12)) { candidate in
                            HStack(spacing: 8) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(candidate.identifier)
                                        .font(.subheadline.weight(.medium))
                                    Text("\(candidate.vendor) · \(candidate.version) · \(candidate.distribution)")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if candidate.isInstalled {
                                    PilotBadge(text: "已安装", color: .green)
                                }
                                Button("安装") {
                                    sdkmanJavaIdentifierInput = candidate.identifier
                                    Task { await store.installJavaWithSDKMAN(identifier: candidate.identifier) }
                                }
                                .buttonStyle(.bordered)
                                .disabled(store.isLoading || candidate.isInstalled)
                            }
                            .padding(10)
                            .background(PilotPalette.cardBackground.opacity(0.72))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }

                        if filteredSDKMANJavaCandidates.count > 12 {
                            Text("仅显示前 12 条结果，请继续缩小搜索范围。")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Text("点击“查询版本”后可按 vendor、version、identifier 模糊过滤可安装 JDK。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if !store.sdkmanStatus.isInstalled {
                Text("首次安装 JDK 时会先尝试安装 SDKMAN。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(PilotPalette.rowBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var projectPreferenceSection: some View {
        PilotCard {
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("项目版本策略", subtitle: "控制 Node 版本选择优先级")
                Picker("Node 版本来源", selection: $projectPreference) {
                    Text("跟随 .nvmrc/.node-version").tag(ProjectVersionPreference.followProjectFiles)
                    Text("始终使用全局已选版本").tag(ProjectVersionPreference.globalDefault)
                }
                .pickerStyle(.segmented)
                .disabled(store.isLoading)
            }
        }
    }

    private var profileSelectionSection: some View {
        PilotCard {
            VStack(alignment: .leading, spacing: 12) {
                sectionTitle("环境配置", subtitle: "管理当前激活的环境变量集合")
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
                        .textFieldStyle(.roundedBorder)
                        .disabled(store.isLoading)
                    Button("创建") {
                        let name = newProfileName
                        newProfileName = ""
                        Task { await store.createProfile(named: name) }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(store.isLoading)
                }
            }
        }
    }

    private var profileEditorSection: some View {
        PilotCard {
            VStack(alignment: .leading, spacing: 12) {
                sectionTitle("配置编辑", subtitle: "编辑 registry、NODE_OPTIONS 与自定义变量")
                if selectedProfileID == nil {
                    Text("请选择或创建一个配置后再编辑环境变量。")
                        .foregroundStyle(.secondary)
                } else {
                    TextField("配置名称", text: $draftProfile.name)
                        .textFieldStyle(.roundedBorder)
                        .disabled(store.isLoading)
                    TextField("npm registry", text: $draftProfile.npmRegistry)
                        .textFieldStyle(.roundedBorder)
                        .disabled(store.isLoading)
                    TextField("pnpm registry", text: $draftProfile.pnpmRegistry)
                        .textFieldStyle(.roundedBorder)
                        .disabled(store.isLoading)
                    TextField("yarn registry", text: $draftProfile.yarnRegistry)
                        .textFieldStyle(.roundedBorder)
                        .disabled(store.isLoading)
                    TextField("NODE_OPTIONS", text: $draftProfile.nodeOptions)
                        .textFieldStyle(.roundedBorder)
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
                        HStack(spacing: 8) {
                            TextField("KEY", text: $draftProfile.variables[index].key)
                                .textFieldStyle(.roundedBorder)
                                .disabled(store.isLoading)
                            TextField("VALUE", text: $draftProfile.variables[index].value)
                                .textFieldStyle(.roundedBorder)
                                .disabled(store.isLoading)
                            Button("删除") {
                                draftProfile.variables.remove(at: index)
                            }
                            .buttonStyle(.bordered)
                            .disabled(store.isLoading)
                        }
                        .padding(8)
                        .background(PilotPalette.rowBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }

                    HStack {
                        Button("新增变量") {
                            draftProfile.variables.append(CustomEnvironmentVariable(key: "", value: ""))
                        }
                        .buttonStyle(.bordered)
                        .disabled(store.isLoading)
                        Spacer()
                        Button("重置") {
                            synchronizeFromSnapshot()
                        }
                        .buttonStyle(.bordered)
                        .disabled(store.isLoading)
                        Button("保存配置") {
                            Task { await store.saveProfile(draftProfile) }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(store.isLoading || draftProfile.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        }
    }

    private func errorCard(message: String) -> some View {
        PilotCard(tint: .red.opacity(0.10)) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text(message)
                    .font(.caption)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func metricTile(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(PilotPalette.rowBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func keyValueLine(_ key: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(key)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption)
                .textSelection(.enabled)
                .lineLimit(1)
        }
    }

    private func sectionTitle(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.headline)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var trimmedSDKMANJavaIdentifier: String {
        sdkmanJavaIdentifierInput.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredSDKMANJavaCandidates: [SDKMANJavaCandidate] {
        let query = sdkmanSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else {
            return store.sdkmanJavaCandidates
        }
        return store.sdkmanJavaCandidates.filter { candidate in
            [
                candidate.identifier,
                candidate.vendor,
                candidate.version,
                candidate.distribution,
            ]
            .joined(separator: " ")
            .lowercased()
            .contains(query)
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

    private func isNodeSelected(item: NodeInstallation) -> Bool {
        guard let snapshot = store.snapshot else {
            return false
        }
        return snapshot.settings.selectedVersion == item.version
    }
}

private enum PilotPalette {
    static let cardBackground = Color.white.opacity(0.82)
    static let rowBackground = Color.black.opacity(0.05)
    static let pillBackground = Color.white.opacity(0.72)
}

private struct PilotBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.90, green: 0.95, blue: 1.00),
                    Color(red: 0.94, green: 0.97, blue: 0.94),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Circle()
                .fill(Color.blue.opacity(0.18))
                .frame(width: 260, height: 260)
                .offset(x: 160, y: -240)
                .blur(radius: 36)
            Circle()
                .fill(Color.mint.opacity(0.16))
                .frame(width: 300, height: 300)
                .offset(x: -180, y: 280)
                .blur(radius: 48)
        }
        .ignoresSafeArea()
    }
}

private struct PilotCard<Content: View>: View {
    var tint: Color = .clear
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(PilotPalette.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(tint)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.black.opacity(0.06), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.04), radius: 12, x: 0, y: 6)
    }
}

private struct PilotBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.18))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}
