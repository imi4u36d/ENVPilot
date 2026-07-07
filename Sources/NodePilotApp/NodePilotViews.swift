import SwiftUI
import ENVPilotCore

struct MenuBarContentView: View {
    @ObservedObject var store: NodeRuntimeStore

    var body: some View {
        ZStack {
            LiquidGlassBackground()

            VStack(alignment: .leading, spacing: 0) {
                menuHeader
                Divider()
                runtimeSummary
                if store.isLoading {
                    Divider()
                    ProgressRow(message: store.loadingMessage ?? "正在处理...")
                }
                if let message = store.latestError {
                    Divider()
                    MessageRow(message: message, systemImage: "exclamationmark.triangle.fill", color: .red)
                }
                Divider()
                quickActions
                Divider()
                footerActions
            }
            .frame(width: 360)
            .liquidGlassPanel(cornerRadius: 18, tint: Color.white.opacity(0.04))
            .padding(10)
        }
        .frame(width: 380)
    }

    private var menuHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "terminal.fill")
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text("ENVPilot")
                    .font(.headline)
                Text(store.isLoading ? "正在同步运行时" : "开发运行时已就绪")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                Task { await store.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("刷新")
            .disabled(store.isLoading)
        }
        .padding(12)
    }

    private var runtimeSummary: some View {
        VStack(alignment: .leading, spacing: 10) {
            RuntimeMenuRow(
                title: "Node",
                value: store.displayNodeVersion,
                detail: store.snapshot?.activeNodePath ?? "未检测到 node 命令",
                systemImage: "shippingbox"
            )
            RuntimeMenuRow(
                title: "JDK",
                value: store.displayJavaVersion,
                detail: store.snapshot?.activeJavaHome ?? "未配置 JAVA_HOME",
                systemImage: "cup.and.saucer"
            )
            RuntimeMenuRow(
                title: "Python",
                value: store.displayPythonVersion,
                detail: store.snapshot?.activePythonHome ?? "未配置 Python",
                systemImage: "curlybraces"
            )
        }
        .padding(12)
    }

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("快速切换")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let snapshot = store.snapshot {
                QuickRuntimeMenu(
                    title: "Node",
                    emptyTitle: "未发现 ENVPilot Node",
                    items: Array(snapshot.installations.prefix(5)),
                    isSelected: { snapshot.settings.selectedVersion == $0.version },
                    version: { $0.version },
                    path: { $0.installPath },
                    action: { item in Task { await store.setDefaultNode(version: item.version) } }
                )

                QuickRuntimeMenu(
                    title: "JDK",
                    emptyTitle: "未发现 JDK",
                    items: Array(snapshot.javaInstallations.prefix(5)),
                    isSelected: { snapshot.settings.selectedJavaHome == $0.homePath },
                    version: { $0.version },
                    path: { $0.homePath },
                    action: { item in Task { await store.setDefaultJava(version: item.version, homePath: item.homePath) } }
                )

                QuickRuntimeMenu(
                    title: "Python",
                    emptyTitle: "未发现 Python",
                    items: Array(snapshot.pythonInstallations.prefix(5)),
                    isSelected: { snapshot.settings.selectedPythonHome == $0.homePath },
                    version: { $0.version },
                    path: { $0.homePath },
                    action: { item in Task { await store.setDefaultPython(version: item.version, homePath: item.homePath) } }
                )
            } else {
                Text("正在载入运行时信息...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            }
        }
        .padding(12)
    }

    private var footerActions: some View {
        HStack {
            Button {
                ENVPilotApplicationDelegate.showMainWindow()
            } label: {
                Label("打开主界面", systemImage: "macwindow")
            }
            .buttonStyle(.borderedProminent)

            Spacer()

            Button {
                NSApp.terminate(nil)
            } label: {
                Label("退出", systemImage: "power")
            }
            .buttonStyle(.borderless)
        }
        .padding(12)
    }
}

struct SettingsView: View {
    @ObservedObject var store: NodeRuntimeStore

    @State private var selectedSection: SettingsSection? = .overview
    @State private var selectedProfileID: UUID?
    @State private var draftProfile = EnvironmentProfile(name: "")
    @State private var newProfileName = ""
    @State private var nodeCandidateSearchText = ""
    @State private var javaCandidateSearchText = ""
    @State private var pythonCandidateSearchText = ""
    @State private var nodeCandidatesLTSOnly = true
    @State private var javaCandidatesLTSOnly = true
    @State private var pythonCandidatesStableOnly = true
    @State private var projectPreference: ProjectVersionPreference = .followProjectFiles
    @State private var isSynchronizing = false

    var body: some View {
        NavigationSplitView {
            List(SettingsSection.allCases, selection: $selectedSection) { section in
                Label(section.title, systemImage: section.systemImage)
                    .tag(section)
            }
            .navigationTitle("ENVPilot")
            .scrollContentBackground(.hidden)
            .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 220)
        } detail: {
            ZStack {
                LiquidGlassBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        SettingsDetailHeader(
                            section: selectedSection ?? .overview,
                            isLoading: store.isLoading,
                            refreshAction: { Task { await store.refresh() } }
                        )

                        if let message = store.latestError {
                            InlineMessage(message: message, systemImage: "exclamationmark.triangle.fill", color: .red)
                        }
                        detailContent
                    }
                    .padding(24)
                    .frame(maxWidth: 900, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("")
        }
        .groupBoxStyle(LiquidGlassGroupBoxStyle())
        .task {
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

    @ViewBuilder
    private var detailContent: some View {
        switch selectedSection ?? .overview {
        case .overview:
            overviewSection
        case .node:
            nodeSection
        case .jdk:
            jdkSection
        case .python:
            pythonSection
        case .project:
            projectSection
        case .profiles:
            profilesSection
        }
    }

    private var profiles: [EnvironmentProfile] {
        store.snapshot?.settings.profiles ?? []
    }

    private var configuredNodeOverviewStatus: String {
        guard store.snapshot?.settings.selectedVersion != nil else {
            return "未配置"
        }
        return store.configuredNodeInstallation == nil ? "未下载" : "已下载"
    }

    private var configuredJavaOverviewStatus: String {
        guard let selectedJavaHome = store.snapshot?.settings.selectedJavaHome, !selectedJavaHome.isEmpty else {
            return "未配置"
        }
        let isInstalled = store.snapshot?.javaInstallations.contains { $0.homePath == selectedJavaHome } == true
        return isInstalled ? "已下载" : "未下载"
    }

    private var configuredPythonOverviewStatus: String {
        guard let selectedPythonHome = store.snapshot?.settings.selectedPythonHome, !selectedPythonHome.isEmpty else {
            return "未配置"
        }
        let isInstalled = store.snapshot?.pythonInstallations.contains { $0.homePath == selectedPythonHome } == true
        return isInstalled ? "已下载" : "未下载"
    }

    private var overviewSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("运行时概览")
                                .font(.title2.weight(.semibold))
                            Text("查看 ENVPilot 已选运行时与终端激活后的生效路径。")
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        StatusBadge(text: store.configuredNodeStatus, systemImage: "checkmark.circle.fill", color: .blue)
                    }

                    LazyVGrid(
                        columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                        spacing: 12
                    ) {
                        MetricTile(title: "Node 已选版本", value: store.configuredNodeVersion, systemImage: "shippingbox")
                        MetricTile(title: "Node 状态", value: configuredNodeOverviewStatus, systemImage: "terminal")
                        MetricTile(title: "JDK 已选版本", value: store.snapshot?.settings.selectedJavaVersion ?? "--", systemImage: "cup.and.saucer")
                        MetricTile(title: "JDK 状态", value: configuredJavaOverviewStatus, systemImage: "terminal")
                        MetricTile(title: "Python 已选版本", value: store.snapshot?.settings.selectedPythonVersion ?? "--", systemImage: "curlybraces")
                        MetricTile(title: "Python 状态", value: configuredPythonOverviewStatus, systemImage: "terminal")
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 10) {
                        PathRow(title: "Node 安装目录（已选）", value: store.configuredNodeInstallation?.installPath ?? "未选择")
                        PathRow(title: "ENVPilot node 可执行文件", value: store.configuredNodeInstallation?.executablePath ?? "未选择")
                        PathRow(title: "JAVA_HOME（已选）", value: store.snapshot?.settings.selectedJavaHome ?? "未选择")
                        PathRow(title: "PYTHON_HOME（已选）", value: store.snapshot?.settings.selectedPythonHome ?? "未选择")
                    }
                }
            }

            GroupBox("当前环境配置") {
                VStack(alignment: .leading, spacing: 10) {
                    LabeledContent("配置") {
                        Text(currentProfileName)
                    }
                    LabeledContent("Node 版本来源") {
                        Text(projectPreferenceText(store.snapshot?.settings.projectVersionPreference ?? .followProjectFiles))
                    }
                    LabeledContent("切换方式") {
                        Text("ENVPilot 环境变量")
                    }
                }
            }
        }
    }

    private var nodeSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                SectionHeader(
                    title: "Node",
                    subtitle: "从 Node 官方分发安装到 ENVPilot 目录，并通过环境变量切换 PATH。",
                    systemImage: "shippingbox"
                )

                installNodePanel

                if let installations = store.snapshot?.installations, !installations.isEmpty {
                    VStack(spacing: 8) {
                        ForEach(installations) { item in
                            let canUninstall = isManagedNodePath(item.installPath)
                            let isSelected = isNodeSelected(item: item)
                            RuntimeListRow(
                                title: "Node \(item.version)",
                                path: item.installPath,
                                badges: nodeBadges(for: item),
                                primaryTitle: isSelected ? "" : "切换",
                                primarySystemImage: "arrow.triangle.2.circlepath",
                                primaryStatusBadge: isSelected ? StatusBadgeModel(text: "已选中", systemImage: "checkmark.circle.fill", color: .green) : nil,
                                destructiveTitle: canUninstall ? "卸载" : "",
                                primaryAction: { Task { await store.setDefaultNode(version: item.version) } },
                                destructiveAction: { Task { await store.uninstallNode(version: item.version) } },
                                isDisabled: store.isLoading
                            )
                        }
                    }
                } else {
                    EmptyState(
                        title: "未发现 ENVPilot Node",
                        message: nodeEmptyMessage,
                        systemImage: "shippingbox"
                    )
                }
            }
        }
    }

    private var jdkSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox {
                VStack(alignment: .leading, spacing: 16) {
                    SectionHeader(
                        title: "JDK",
                        subtitle: "从 Adoptium Temurin 安装到 ENVPilot 目录，并写入 JAVA_HOME 与 PATH。",
                        systemImage: "cup.and.saucer"
                    )
                    installJavaPanel
                }
            }

            GroupBox("已安装 JDK") {
                if let javaInstallations = store.snapshot?.javaInstallations, !javaInstallations.isEmpty {
                    VStack(spacing: 8) {
                        ForEach(javaInstallations) { jdk in
                            let canUninstall = isManagedJavaPath(jdk.homePath)
                            let isSelected = store.snapshot?.settings.selectedJavaHome == jdk.homePath
                            RuntimeListRow(
                                title: "JDK \(jdk.version)",
                                path: jdk.homePath,
                                badges: javaBadges(for: jdk),
                                primaryTitle: isSelected ? "" : "切换",
                                primarySystemImage: "arrow.triangle.2.circlepath",
                                primaryStatusBadge: isSelected ? StatusBadgeModel(text: "已选中", systemImage: "checkmark.circle.fill", color: .green) : nil,
                                destructiveTitle: canUninstall ? "卸载" : "",
                                primaryAction: { Task { await store.setDefaultJava(version: jdk.version, homePath: jdk.homePath) } },
                                destructiveAction: { Task { await store.uninstallJava(version: jdk.version, homePath: jdk.homePath) } },
                                isDisabled: store.isLoading
                            )
                        }
                    }
                } else {
                    EmptyState(
                        title: "未发现 ENVPilot JDK",
                        message: "可以在上方查询 Temurin 候选版本并安装到 ENVPilot 目录。",
                        systemImage: "cup.and.saucer"
                    )
                }
            }
        }
    }

    private var pythonSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox {
                VStack(alignment: .leading, spacing: 16) {
                    SectionHeader(
                        title: "Python",
                        subtitle: "从 Python 官方源码构建到 ENVPilot 目录，并通过 PATH 切换 python3。",
                        systemImage: "curlybraces"
                    )
                    installPythonPanel
                }
            }

            GroupBox("已安装 Python") {
                if let pythonInstallations = store.snapshot?.pythonInstallations, !pythonInstallations.isEmpty {
                    VStack(spacing: 8) {
                        ForEach(pythonInstallations) { python in
                            let isSelected = store.snapshot?.settings.selectedPythonHome == python.homePath
                            RuntimeListRow(
                                title: "Python \(python.version)",
                                path: python.homePath,
                                badges: pythonBadges(for: python),
                                primaryTitle: isSelected ? "" : "切换",
                                primarySystemImage: "arrow.triangle.2.circlepath",
                                primaryStatusBadge: isSelected ? StatusBadgeModel(text: "已选中", systemImage: "checkmark.circle.fill", color: .green) : nil,
                                destructiveTitle: isManagedPythonPath(python.homePath) ? "卸载" : "",
                                primaryAction: { Task { await store.setDefaultPython(version: python.version, homePath: python.homePath) } },
                                destructiveAction: { Task { await store.uninstallPython(version: python.version, homePath: python.homePath) } },
                                isDisabled: store.isLoading
                            )
                        }
                    }
                } else {
                    EmptyState(
                        title: "未发现 ENVPilot Python",
                        message: "可以在上方查询 Python 官方候选版本并安装到 ENVPilot 目录。",
                        systemImage: "curlybraces"
                    )
                }
            }
        }
    }

    private var installNodePanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("搜索 Node 版本")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.primary)
                    TextField("过滤版本，例如 22、20 或 LTS 名称", text: $nodeCandidateSearchText)
                        .textFieldStyle(EnvPilotTextFieldStyle())
                        .disabled(store.isLoading)
                }
                Toggle("仅 LTS", isOn: $nodeCandidatesLTSOnly)
                    .toggleStyle(.switch)
                    .disabled(store.isLoading)
                Button {
                    Task { await store.queryNodeDownloadCandidates(ltsOnly: nodeCandidatesLTSOnly) }
                } label: {
                    Label("查询", systemImage: "arrow.clockwise")
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .disabled(store.isLoading)
            }
            .padding(14)
            .background(AppPalette.controlSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(AppPalette.borderStrong, lineWidth: 1)
            }

            if store.nodeDownloadCandidates.isEmpty {
                InlineMessage(message: "点击查询后展示 Node 官方可下载版本。", systemImage: "info.circle", color: .blue)
            } else {
                VStack(spacing: 8) {
                    ForEach(filteredNodeDownloadCandidates.prefix(12)) { candidate in
                        let isInstalled = isNodeCandidateInstalled(candidate)
                        let isInstalling = store.installingCandidateID == nodeCandidateID(candidate)
                        DownloadCandidateRow(
                            title: "Node \(candidate.version)",
                            subtitle: candidate.lts.map { "LTS \($0)" } ?? "Current",
                            badges: nodeCandidateBadges(candidate, isInstalled: isInstalled),
                            progressMessage: isInstalling ? store.installingCandidateMessage : nil,
                            actionTitle: isInstalled ? "已下载" : (isInstalling ? "安装中" : "安装"),
                            actionSystemImage: isInstalled ? "checkmark.circle" : (isInstalling ? "hourglass" : "square.and.arrow.down"),
                            action: { Task { await store.installNode(version: candidate.version) } },
                            isDisabled: store.isLoading || isInstalled
                        )
                    }
                }
            }
        }
    }

    private var installJavaPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("搜索 JDK 版本")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.primary)
                    TextField("过滤版本，例如 21、17 或 Temurin", text: $javaCandidateSearchText)
                        .textFieldStyle(EnvPilotTextFieldStyle())
                        .disabled(store.isLoading)
                }
                Toggle("仅 LTS", isOn: $javaCandidatesLTSOnly)
                    .toggleStyle(.switch)
                    .disabled(store.isLoading)
                Button {
                    Task { await store.queryJavaDownloadCandidates(ltsOnly: javaCandidatesLTSOnly) }
                } label: {
                    Label("查询", systemImage: "arrow.clockwise")
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .disabled(store.isLoading)
            }
            .padding(14)
            .background(AppPalette.controlSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(AppPalette.borderStrong, lineWidth: 1)
            }

            if store.javaDownloadCandidates.isEmpty {
                InlineMessage(message: "点击查询后展示 Temurin JDK 可下载版本。", systemImage: "info.circle", color: .blue)
            } else {
                VStack(spacing: 8) {
                    ForEach(filteredJavaDownloadCandidates.prefix(12)) { candidate in
                        let isInstalled = isJavaCandidateInstalled(candidate)
                        let isInstalling = store.installingCandidateID == javaCandidateID(candidate)
                        DownloadCandidateRow(
                            title: "JDK \(candidate.featureVersion)",
                            subtitle: "\(candidate.vendor) \(candidate.version)",
                            badges: javaCandidateBadges(candidate, isInstalled: isInstalled),
                            progressMessage: isInstalling ? store.installingCandidateMessage : nil,
                            actionTitle: isInstalled ? "已下载" : (isInstalling ? "安装中" : "安装"),
                            actionSystemImage: isInstalled ? "checkmark.circle" : (isInstalling ? "hourglass" : "square.and.arrow.down"),
                            action: { Task { await store.installJava(featureVersion: candidate.featureVersion) } },
                            isDisabled: store.isLoading || isInstalled
                        )
                    }
                }
            }
        }
    }

    private var installPythonPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("搜索 Python 版本")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.primary)
                    TextField("过滤版本，例如 3.14、3.13 或 3.12", text: $pythonCandidateSearchText)
                        .textFieldStyle(EnvPilotTextFieldStyle())
                        .disabled(store.isLoading)
                }
                Toggle("仅稳定版", isOn: $pythonCandidatesStableOnly)
                    .toggleStyle(.switch)
                    .disabled(store.isLoading)
                Button {
                    Task { await store.queryPythonDownloadCandidates(stableOnly: pythonCandidatesStableOnly) }
                } label: {
                    Label("查询", systemImage: "arrow.clockwise")
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .disabled(store.isLoading)
            }
            .padding(14)
            .background(AppPalette.controlSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(AppPalette.borderStrong, lineWidth: 1)
            }

            if store.pythonDownloadCandidates.isEmpty {
                InlineMessage(message: "点击查询后展示 Python 官方可下载源码版本；安装会在本机编译，耗时会比 Node/JDK 更长。", systemImage: "info.circle", color: .blue)
            } else {
                VStack(spacing: 8) {
                    ForEach(filteredPythonDownloadCandidates.prefix(12)) { candidate in
                        let isInstalled = isPythonCandidateInstalled(candidate)
                        let isInstalling = store.installingCandidateID == pythonCandidateID(candidate)
                        DownloadCandidateRow(
                            title: "Python \(candidate.version)",
                            subtitle: "CPython source · \(candidate.packageName)",
                            badges: pythonCandidateBadges(candidate, isInstalled: isInstalled),
                            progressMessage: isInstalling ? store.installingCandidateMessage : nil,
                            actionTitle: isInstalled ? "已下载" : (isInstalling ? "安装中" : "安装"),
                            actionSystemImage: isInstalled ? "checkmark.circle" : (isInstalling ? "hourglass" : "square.and.arrow.down"),
                            action: { Task { await store.installPython(version: candidate.version) } },
                            isDisabled: store.isLoading || isInstalled
                        )
                    }
                }
            }
        }
    }

    private var projectSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                SectionHeader(
                    title: "项目版本策略",
                    subtitle: "控制进入项目目录时 Node 版本选择优先级。",
                    systemImage: "folder.badge.gearshape"
                )

                Picker("", selection: $projectPreference) {
                    Text("跟随 .envpilot 项目配置").tag(ProjectVersionPreference.followProjectFiles)
                    Text("始终使用全局已选版本").tag(ProjectVersionPreference.globalDefault)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .disabled(store.isLoading)

                InlineMessage(
                    message: projectPreferenceHelpText,
                    systemImage: "info.circle",
                    color: .blue
                )
            }
        }
    }

    private var profilesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox {
                VStack(alignment: .leading, spacing: 14) {
                    SectionHeader(
                        title: "环境配置",
                        subtitle: "管理当前激活的 registry、NODE_OPTIONS 与自定义变量。",
                        systemImage: "slider.horizontal.3"
                    )

                    if profiles.isEmpty {
                        EmptyState(title: "当前没有可用配置", message: "创建一个配置后即可编辑环境变量。", systemImage: "slider.horizontal.3")
                    } else {
                        Picker("当前配置", selection: $selectedProfileID) {
                            ForEach(profiles) { profile in
                                Text(profile.name).tag(Optional(profile.id))
                            }
                        }
                        .disabled(store.isLoading)
                    }

                    HStack(alignment: .bottom, spacing: 12) {
                        VStack(alignment: .leading, spacing: 7) {
                            Text("新建配置")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.primary)
                            TextField("输入配置名称", text: $newProfileName)
                                .textFieldStyle(EnvPilotTextFieldStyle())
                                .disabled(store.isLoading)
                        }
                        .frame(maxWidth: .infinity)
                        Button {
                            let name = newProfileName.trimmingCharacters(in: .whitespacesAndNewlines)
                            newProfileName = ""
                            Task { await store.createProfile(named: name) }
                        } label: {
                            Label("创建", systemImage: "plus")
                        }
                        .controlSize(.large)
                        .buttonStyle(.borderedProminent)
                        .disabled(store.isLoading || newProfileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .padding(14)
                    .background(AppPalette.controlSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(AppPalette.borderStrong, lineWidth: 1.2)
                    }
                }
            }

            GroupBox("配置编辑") {
                if selectedProfileID == nil {
                    EmptyState(title: "请选择一个配置", message: "选中或创建配置后再编辑环境变量。", systemImage: "pencil")
                } else {
                    profileEditor
                }
            }
        }
    }

    private var profileEditor: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 12) {
                ProfileInputRow(title: "配置名称") {
                    TextField("例如：默认、公司网络、私有源", text: $draftProfile.name)
                        .textFieldStyle(EnvPilotTextFieldStyle())
                        .disabled(store.isLoading)
                }
                ProfileInputRow(title: "npm registry") {
                    TextField("https://registry.npmjs.org/", text: $draftProfile.npmRegistry)
                        .textFieldStyle(EnvPilotTextFieldStyle())
                        .disabled(store.isLoading)
                }
                ProfileInputRow(title: "pnpm registry") {
                    TextField("留空则不设置", text: $draftProfile.pnpmRegistry)
                        .textFieldStyle(EnvPilotTextFieldStyle())
                        .disabled(store.isLoading)
                }
                ProfileInputRow(title: "yarn registry") {
                    TextField("留空则不设置", text: $draftProfile.yarnRegistry)
                        .textFieldStyle(EnvPilotTextFieldStyle())
                        .disabled(store.isLoading)
                }
                ProfileInputRow(title: "NODE_OPTIONS") {
                    TextField("例如 --max-old-space-size=4096", text: $draftProfile.nodeOptions)
                        .textFieldStyle(EnvPilotTextFieldStyle())
                        .disabled(store.isLoading)
                }
            }
            .padding(14)
            .background(AppPalette.controlSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(AppPalette.borderStrong, lineWidth: 1)
            }

            Divider()

            HStack {
                Text("自定义环境变量")
                    .font(.headline)
                Spacer()
                Button {
                    draftProfile.variables.append(CustomEnvironmentVariable(key: "", value: ""))
                } label: {
                    Label("新增变量", systemImage: "plus")
                }
                .disabled(store.isLoading)
            }

            if draftProfile.variables.isEmpty {
                Text("暂无自定义变量。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(draftProfile.variables.indices), id: \.self) { index in
                        HStack(spacing: 8) {
                            TextField("KEY", text: $draftProfile.variables[index].key)
                                .textFieldStyle(EnvPilotTextFieldStyle())
                                .disabled(store.isLoading)
                            TextField("VALUE", text: $draftProfile.variables[index].value)
                                .textFieldStyle(EnvPilotTextFieldStyle())
                                .disabled(store.isLoading)
                            Button(role: .destructive) {
                                draftProfile.variables.remove(at: index)
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                            .help("删除变量")
                            .disabled(store.isLoading)
                        }
                    }
                }
            }

            HStack {
                Spacer()
                Button {
                    synchronizeFromSnapshot()
                } label: {
                    Label("重置", systemImage: "arrow.uturn.backward")
                }
                .disabled(store.isLoading)

                Button {
                    Task { await store.saveProfile(draftProfile) }
                } label: {
                    Label("保存配置", systemImage: "checkmark")
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.isLoading || draftProfile.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private var currentProfileName: String {
        guard let selectedID = store.snapshot?.settings.selectedProfileID,
              let profile = store.snapshot?.settings.profiles.first(where: { $0.id == selectedID }) else {
            return "未选择"
        }
        return profile.name
    }

    private var nodeEmptyMessage: String {
        var messages = ["可以在上方查询 Node 官方候选版本并安装到 ENVPilot 目录。"]
        if let selectedVersion = store.snapshot?.settings.selectedVersion, !selectedVersion.isEmpty {
            messages.append("当前配置版本是 \(selectedVersion)，但未检测到对应的 ENVPilot Node 安装路径。")
        }
        if let activePath = store.snapshot?.activeNodePath, !activePath.isEmpty {
            messages.append("当前 node 命令来自 \(activePath)。")
        }
        return messages.joined(separator: " ")
    }

    private var projectPreferenceHelpText: String {
        switch projectPreference {
        case .followProjectFiles:
            return "进入项目目录时优先读取 .envpilot 中的 NODE_VERSION；未声明时使用全局已选版本。"
        case .globalDefault:
            return "忽略项目内版本文件，始终使用 ENVPilot 中配置的全局 Node 版本。"
        }
    }

    private var filteredNodeDownloadCandidates: [NodeDownloadCandidate] {
        let query = nodeCandidateSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else {
            return store.nodeDownloadCandidates
        }
        return store.nodeDownloadCandidates.filter { candidate in
            [
                candidate.version,
                candidate.lts ?? "",
            ]
            .joined(separator: " ")
            .lowercased()
            .contains(query)
        }
    }

    private var filteredJavaDownloadCandidates: [JavaDownloadCandidate] {
        let query = javaCandidateSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else {
            return store.javaDownloadCandidates
        }
        return store.javaDownloadCandidates.filter { candidate in
            [
                String(candidate.featureVersion),
                candidate.version,
                candidate.vendor,
                candidate.packageName,
            ]
            .joined(separator: " ")
            .lowercased()
            .contains(query)
        }
    }

    private var filteredPythonDownloadCandidates: [PythonDownloadCandidate] {
        let query = pythonCandidateSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else {
            return store.pythonDownloadCandidates
        }
        return store.pythonDownloadCandidates.filter { candidate in
            [
                candidate.version,
                candidate.packageName,
            ]
            .joined(separator: " ")
            .lowercased()
            .contains(query)
        }
    }

    private func nodeBadges(for item: NodeInstallation) -> [StatusBadgeModel] {
        var badges: [StatusBadgeModel] = []
        if isManagedNodePath(item.installPath) {
            badges.append(StatusBadgeModel(text: "ENVPilot", systemImage: "checkmark.seal.fill", color: .orange))
        }
        return badges
    }

    private func javaBadges(for jdk: JavaInstallation) -> [StatusBadgeModel] {
        var badges: [StatusBadgeModel] = []
        if isManagedJavaPath(jdk.homePath) {
            badges.append(StatusBadgeModel(text: "ENVPilot", systemImage: "checkmark.seal.fill", color: .orange))
        }
        if store.snapshot?.settings.selectedJavaHome != jdk.homePath,
           store.snapshot?.activeJavaHome == jdk.homePath {
            badges.append(StatusBadgeModel(text: "运行中", systemImage: "play.circle.fill", color: .blue))
        }
        return badges
    }

    private func pythonBadges(for python: PythonInstallation) -> [StatusBadgeModel] {
        var badges: [StatusBadgeModel] = []
        if isManagedPythonPath(python.homePath) {
            badges.append(StatusBadgeModel(text: "ENVPilot", systemImage: "checkmark.seal.fill", color: .orange))
        }
        if store.snapshot?.settings.selectedPythonHome != python.homePath,
           store.snapshot?.activePythonHome == python.homePath {
            badges.append(StatusBadgeModel(text: "运行中", systemImage: "play.circle.fill", color: .blue))
        }
        return badges
    }

    private func projectPreferenceText(_ preference: ProjectVersionPreference) -> String {
        switch preference {
        case .followProjectFiles:
            return "跟随 .envpilot 项目配置"
        case .globalDefault:
            return "始终使用全局版本"
        }
    }

    private func isManagedNodePath(_ path: String) -> Bool {
        path.contains("/.envpilot/runtimes/node/")
    }

    private func isManagedJavaPath(_ path: String) -> Bool {
        path.contains("/.envpilot/runtimes/java/")
    }

    private func isManagedPythonPath(_ path: String) -> Bool {
        path.contains("/.envpilot/runtimes/python/")
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

    private func nodeCandidateID(_ candidate: NodeDownloadCandidate) -> String {
        "node-\(candidate.version)"
    }

    private func javaCandidateID(_ candidate: JavaDownloadCandidate) -> String {
        "java-\(candidate.featureVersion)"
    }

    private func pythonCandidateID(_ candidate: PythonDownloadCandidate) -> String {
        "python-\(candidate.version)"
    }

    private func isNodeCandidateInstalled(_ candidate: NodeDownloadCandidate) -> Bool {
        store.snapshot?.installations.contains { $0.version == candidate.version } == true
    }

    private func isJavaCandidateInstalled(_ candidate: JavaDownloadCandidate) -> Bool {
        store.snapshot?.javaInstallations.contains { javaVersion($0.version, matchesFeatureVersion: candidate.featureVersion) } == true
    }

    private func isPythonCandidateInstalled(_ candidate: PythonDownloadCandidate) -> Bool {
        store.snapshot?.pythonInstallations.contains { $0.version == candidate.version } == true
    }

    private func nodeCandidateBadges(_ candidate: NodeDownloadCandidate, isInstalled: Bool) -> [StatusBadgeModel] {
        var badges: [StatusBadgeModel] = []
        if isInstalled {
            badges.append(StatusBadgeModel(text: "已下载", systemImage: "checkmark.circle.fill", color: .green))
        }
        if candidate.lts != nil {
            badges.append(StatusBadgeModel(text: "LTS", systemImage: "clock.badge.checkmark", color: .blue))
        }
        return badges
    }

    private func javaCandidateBadges(_ candidate: JavaDownloadCandidate, isInstalled: Bool) -> [StatusBadgeModel] {
        var badges: [StatusBadgeModel] = []
        if isInstalled {
            badges.append(StatusBadgeModel(text: "已下载", systemImage: "checkmark.circle.fill", color: .green))
        }
        if candidate.version.contains("LTS") || [25, 21, 17, 11, 8].contains(candidate.featureVersion) {
            badges.append(StatusBadgeModel(text: "LTS", systemImage: "clock.badge.checkmark", color: .blue))
        }
        return badges
    }

    private func pythonCandidateBadges(_ candidate: PythonDownloadCandidate, isInstalled: Bool) -> [StatusBadgeModel] {
        var badges: [StatusBadgeModel] = []
        if isInstalled {
            badges.append(StatusBadgeModel(text: "已下载", systemImage: "checkmark.circle.fill", color: .green))
        }
        badges.append(StatusBadgeModel(text: "官方源码", systemImage: "curlybraces", color: .blue))
        return badges
    }

    private func javaVersion(_ version: String, matchesFeatureVersion featureVersion: Int) -> Bool {
        version == String(featureVersion) || version.hasPrefix("\(featureVersion).")
    }
}

private enum AppPalette {
    static let pageBackgroundTop = Color(red: 0.97, green: 0.985, blue: 1.00)
    static let pageBackgroundBottom = Color(red: 0.95, green: 0.97, blue: 0.965)
    static let panelSurface = Color(nsColor: .controlBackgroundColor)
    static let controlSurface = Color(nsColor: .textBackgroundColor)
    static let rowSurface = Color.white.opacity(0.72)
    static let sidebarSurface = Color(nsColor: .windowBackgroundColor)
    static let selectedSurface = Color.accentColor.opacity(0.14)
    static let border = Color.black.opacity(0.10)
    static let borderStrong = Color.accentColor.opacity(0.34)
    static let shadow = Color.black.opacity(0.07)
}

private struct LiquidGlassBackground: View {
    var body: some View {
        LinearGradient(
            colors: [
                AppPalette.pageBackgroundTop,
                AppPalette.pageBackgroundBottom,
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}

private struct LiquidGlassPanelModifier: ViewModifier {
    let cornerRadius: CGFloat
    let tint: Color

    func body(content: Content) -> some View {
        content
            .background(AppPalette.panelSurface, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .background(tint, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(AppPalette.border, lineWidth: 1)
            }
            .overlay(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.56),
                                Color.white.opacity(0.12),
                                Color.clear,
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
                    .allowsHitTesting(false)
            }
            .shadow(color: AppPalette.shadow, radius: 16, x: 0, y: 8)
    }
}

private extension View {
    func liquidGlassPanel(cornerRadius: CGFloat = 14, tint: Color = .clear) -> some View {
        modifier(LiquidGlassPanelModifier(cornerRadius: cornerRadius, tint: tint))
    }
}

private struct EnvPilotTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .textFieldStyle(.plain)
            .padding(.horizontal, 11)
            .frame(minHeight: 36)
            .background(AppPalette.controlSurface, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.62), lineWidth: 1.2)
            }
            .shadow(color: Color.black.opacity(0.06), radius: 4, x: 0, y: 1)
    }
}

private struct ProfileInputRow<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            content
        }
    }
}

private struct LiquidGlassGroupBoxStyle: GroupBoxStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            configuration.label
                .font(.headline)
            configuration.content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlassPanel(cornerRadius: 16, tint: Color.white.opacity(0.08))
    }
}

private struct SettingsDetailHeader: View {
    let section: SettingsSection
    let isLoading: Bool
    let refreshAction: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: section.systemImage)
                .font(.title2.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 38, height: 38)
                .background(AppPalette.selectedSurface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(AppPalette.borderStrong, lineWidth: 1)
                }

            VStack(alignment: .leading, spacing: 3) {
                Text(section.title)
                    .font(.title2.weight(.semibold))
                Text(section.subtitle)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isLoading {
                ProgressView()
                    .controlSize(.small)
            }

            Button {
                refreshAction()
            } label: {
                Label("刷新", systemImage: "arrow.clockwise")
            }
            .controlSize(.large)
            .buttonStyle(.bordered)
            .disabled(isLoading)
        }
        .padding(16)
        .background(AppPalette.panelSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(AppPalette.border, lineWidth: 1)
        }
        .shadow(color: AppPalette.shadow, radius: 14, x: 0, y: 7)
    }
}

private enum SettingsSection: String, CaseIterable, Identifiable, Hashable {
    case overview
    case node
    case jdk
    case python
    case project
    case profiles

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .overview:
            return "概览"
        case .node:
            return "Node"
        case .jdk:
            return "JDK"
        case .python:
            return "Python"
        case .project:
            return "项目策略"
        case .profiles:
            return "环境配置"
        }
    }

    var subtitle: String {
        switch self {
        case .overview:
            return "查看当前已选版本、安装路径与终端生效配置。"
        case .node:
            return "查询、安装、切换和卸载 ENVPilot 管理的 Node。"
        case .jdk:
            return "查询、安装、切换和卸载 ENVPilot 管理的 JDK。"
        case .python:
            return "查询、安装、切换和卸载 ENVPilot 管理的 Python。"
        case .project:
            return "配置进入项目目录时的版本选择规则。"
        case .profiles:
            return "管理 registry、NODE_OPTIONS 与自定义环境变量。"
        }
    }

    var systemImage: String {
        switch self {
        case .overview:
            return "gauge.with.dots.needle.67percent"
        case .node:
            return "shippingbox"
        case .jdk:
            return "cup.and.saucer"
        case .python:
            return "curlybraces"
        case .project:
            return "folder.badge.gearshape"
        case .profiles:
            return "slider.horizontal.3"
        }
    }
}

private struct StatusBadgeModel: Identifiable {
    let id = UUID()
    let text: String
    let systemImage: String
    let color: Color
}

private struct RuntimeMenuRow: View {
    let title: String
    let value: String
    let detail: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(title)
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Text(value)
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                }
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }
}

private struct QuickRuntimeMenu<Item: Identifiable>: View {
    let title: String
    let emptyTitle: String
    let items: [Item]
    let isSelected: (Item) -> Bool
    let version: (Item) -> String
    let path: (Item) -> String
    let action: (Item) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)

            if items.isEmpty {
                Text(emptyTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            } else {
                ForEach(items) { item in
                    Button {
                        action(item)
                    } label: {
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(version(item))
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
                                Text(path(item))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer()
                            if isSelected(item) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(8)
                    .background(isSelected(item) ? Color.green.opacity(0.10) : AppPalette.rowSurface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(isSelected(item) ? Color.green.opacity(0.34) : AppPalette.border, lineWidth: 1)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }
}

private struct ProgressRow: View {
    let message: String

    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(12)
    }
}

private struct MessageRow: View {
    let message: String
    let systemImage: String
    let color: Color

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(color)
            Text(message)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(12)
    }
}

private struct ProgressBanner: View {
    let message: String

    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text(message)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(10)
        .liquidGlassPanel(cornerRadius: 12, tint: Color.orange.opacity(0.06))
    }
}

private struct InlineMessage: View {
    let message: String
    let systemImage: String
    let color: Color

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(color)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(10)
        .liquidGlassPanel(cornerRadius: 12, tint: color.opacity(0.08))
    }
}

private struct SectionHeader: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.title3.weight(.semibold))
                Text(subtitle)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct MetricTile: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.title3.monospacedDigit().weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(AppPalette.controlSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(AppPalette.border, lineWidth: 1)
        }
    }
}

private struct PathRow: View {
    let title: String
    let value: String

    var body: some View {
        LabeledContent(title) {
            Text(value)
                .font(.callout.monospaced())
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

private struct RuntimeListRow: View {
    let title: String
    let path: String
    let badges: [StatusBadgeModel]
    let primaryTitle: String
    let primarySystemImage: String
    let primaryStatusBadge: StatusBadgeModel?
    let destructiveTitle: String
    let primaryAction: () -> Void
    let destructiveAction: () -> Void
    let isDisabled: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.subheadline.weight(.medium))
                    ForEach(badges) { badge in
                        StatusBadge(text: badge.text, systemImage: badge.systemImage, color: badge.color)
                    }
                }
                Text(path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            if let primaryStatusBadge {
                StatusBadge(
                    text: primaryStatusBadge.text,
                    systemImage: primaryStatusBadge.systemImage,
                    color: primaryStatusBadge.color
                )
            } else if !primaryTitle.isEmpty {
                Button {
                    primaryAction()
                } label: {
                    Label(primaryTitle, systemImage: primarySystemImage)
                }
                .disabled(isDisabled)
            }

            if !destructiveTitle.isEmpty {
                Button(role: .destructive) {
                    destructiveAction()
                } label: {
                    Label(destructiveTitle, systemImage: "trash")
                }
                .disabled(isDisabled)
            }
        }
        .padding(12)
        .background(AppPalette.rowSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(AppPalette.border, lineWidth: 1)
        }
    }
}

private struct DownloadCandidateRow: View {
    let title: String
    let subtitle: String
    let badges: [StatusBadgeModel]
    let progressMessage: String?
    let actionTitle: String
    let actionSystemImage: String
    let action: () -> Void
    let isDisabled: Bool

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.subheadline.weight(.medium))
                    ForEach(badges) { badge in
                        StatusBadge(text: badge.text, systemImage: badge.systemImage, color: badge.color)
                    }
                }
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let progressMessage, !progressMessage.isEmpty {
                    Text(progressMessage)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.blue)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer()
            Button {
                action()
            } label: {
                Label(actionTitle, systemImage: actionSystemImage)
            }
            .disabled(isDisabled)
        }
        .padding(12)
        .background(progressMessage == nil ? AppPalette.rowSurface : Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(progressMessage == nil ? AppPalette.border : Color.blue.opacity(0.34), lineWidth: 1)
        }
    }
}

private struct EmptyState: View {
    let title: String
    let message: String
    let systemImage: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(.vertical, 8)
    }
}

private struct StatusBadge: View {
    let text: String
    let systemImage: String
    let color: Color

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption2.weight(.medium))
            .labelStyle(.titleAndIcon)
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background {
                Capsule()
                    .fill(.thinMaterial)
                Capsule()
                    .fill(color.opacity(0.10))
            }
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(0.28), lineWidth: 0.8)
            )
            .clipShape(Capsule())
    }
}
