import SwiftUI
import AppKit
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
                Divider()
                if store.isLoading {
                    ProgressRow(message: store.loadingMessage ?? "正在处理...")
                    Divider()
                }
                if let message = store.latestError {
                    MessageRow(message: message, systemImage: "exclamationmark.triangle.fill", color: .red)
                    Divider()
                }
                quickActions
                Divider()
                footerActions
            }
            .frame(width: 360)
            .liquidGlassPanel(cornerRadius: 14, tint: Color.clear)
            .padding(10)
        }
        .frame(width: 380)
    }

    private var menuHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "terminal.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text("ENVPilot")
                    .font(.headline)
                Text(store.isLoading ? "正在同步运行时" : "开发环境已就绪")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                Task { await store.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("刷新运行时信息")
            .help("刷新运行时信息")
            .disabled(store.isLoading)
        }
        .padding(12)
    }

    private var runtimeSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            RuntimeMenuRow(
                title: "Node",
                value: store.displayNodeVersion,
                detail: store.displayNodePath,
                systemImage: "shippingbox"
            )
            RuntimeMenuRow(
                title: "JDK",
                value: store.displayJavaVersion,
                detail: store.snapshot?.settings.selectedJavaHome ?? store.snapshot?.activeJavaHome ?? "未配置 JAVA_HOME",
                systemImage: "cup.and.saucer"
            )
            RuntimeMenuRow(
                title: "Python",
                value: store.displayPythonVersion,
                detail: store.snapshot?.settings.selectedPythonHome ?? store.snapshot?.activePythonHome ?? "未配置 Python",
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
                    version: { RuntimeDisplayFormatter.javaVersion($0.version) },
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
    private enum PendingProfileNavigation {
        case profile(UUID?)
        case section(SettingsSection?)
    }

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
    @State private var pendingUninstallRequest: RuntimeUninstallRequest?
    @State private var pendingProfileNavigation: PendingProfileNavigation?
    @State private var isEnvironmentDetailsExpanded = false

    var body: some View {
        settingsRoot
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
            .onChange(of: store.snapshot?.settings.profiles ?? []) { _ in
                synchronizeFromSnapshot()
            }
            .onChange(of: projectPreference) { newValue in
                guard !isSynchronizing else {
                    return
                }
                Task { await store.setProjectVersionPreference(newValue) }
            }
            .confirmationDialog(
                pendingUninstallRequest?.isCurrent == true ? "无法卸载当前使用版本" : "确认卸载运行时？",
                isPresented: uninstallConfirmationBinding,
                titleVisibility: .visible,
                presenting: pendingUninstallRequest
            ) { request in
                if request.isCurrent {
                    Button("知道了", role: .cancel) {}
                } else {
                    Button("卸载 \(request.displayName)", role: .destructive) {
                        performUninstall(request)
                    }
                    Button("取消", role: .cancel) {}
                }
            } message: { request in
                if request.isCurrent {
                    Text("\(request.displayName) 正在使用。请先切换到其他版本，再执行卸载。")
                } else {
                    Text("将从本机移除 \(request.displayName)。路径：\(request.path)。此操作无法撤销。")
                }
            }
            .confirmationDialog(
                "有未保存的环境预设更改",
                isPresented: pendingProfileNavigationBinding,
                titleVisibility: .visible
            ) {
                Button("保存并继续") {
                    saveProfileAndContinue()
                }
                .disabled(profileValidationMessage != nil)
                Button("放弃更改", role: .destructive) {
                    discardProfileChangesAndContinue()
                }
                Button("取消", role: .cancel) {
                    pendingProfileNavigation = nil
                }
            } message: {
                Text("离开当前环境预设前，请保存或放弃更改。")
            }
    }

    private var settingsRoot: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 220)

            Divider()

            ZStack {
                LiquidGlassBackground()
                detailPanel
            }
        }
    }

    private var sidebar: some View {
        ZStack {
            AppPalette.sidebarBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack(spacing: 11) {
                    Image(systemName: "terminal.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(Color.accentColor.gradient, in: RoundedRectangle(cornerRadius: 9, style: .continuous))

                    VStack(alignment: .leading, spacing: 1) {
                        Text("ENVPilot")
                            .font(.headline)
                        Text("开发环境管理")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .padding(.bottom, 14)

                sidebarList

                sidebarFooter
            }
        }
    }

    private var sidebarList: some View {
        List(selection: sectionSelectionBinding) {
            Section("运行时") {
                sidebarItem(.overview)
                sidebarItem(.node)
                sidebarItem(.jdk)
                sidebarItem(.python)
            }

            Section("项目与环境") {
                sidebarItem(.project)
                sidebarItem(.profiles)
            }

            Section("应用") {
                sidebarItem(.settings)
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
    }

    private func sidebarItem(_ section: SettingsSection) -> some View {
        Label(section.title, systemImage: section.systemImage)
            .tag(section)
    }

    private var sidebarFooter: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()

            HStack(spacing: 8) {
                Circle()
                    .fill(store.isLoading ? Color.orange : Color.green)
                    .frame(width: 7, height: 7)
                    .shadow(color: (store.isLoading ? Color.orange : Color.green).opacity(0.45), radius: 3)
                Text(store.isLoading ? (store.loadingMessage ?? "正在同步") : "环境状态已同步")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            HStack(spacing: 6) {
                Image(systemName: "person.crop.circle")
                    .foregroundStyle(.secondary)
                Text(currentProfileName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var detailPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SettingsDetailHeader(
                    section: selectedSection ?? .overview,
                    isLoading: store.isLoading,
                    refreshAction: selectedSection == .settings ? nil : { Task { await store.refresh() } }
                )

                if let message = store.latestError {
                    InlineMessage(message: message, systemImage: "exclamationmark.triangle.fill", color: .red)
                }
                if let message = store.latestNotice {
                    InlineMessage(message: message, systemImage: "checkmark.circle.fill", color: .green)
                }
                detailContent
            }
            .frame(maxWidth: 1080, alignment: .leading)
            .padding(.horizontal, 32)
            .padding(.vertical, 28)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        case .settings:
            AppSettingsView()
        }
    }

    private var profiles: [EnvironmentProfile] {
        store.snapshot?.settings.profiles ?? []
    }

    private var configuredNodeOverviewStatus: StatusBadgeModel {
        guard store.snapshot?.settings.selectedVersion != nil else {
            let hasInstallations = store.snapshot?.installations.isEmpty == false
            return StatusBadgeModel(
                text: hasInstallations ? "尚未选择" : "尚未安装",
                systemImage: hasInstallations ? "circle.dashed" : "square.and.arrow.down",
                color: .orange
            )
        }
        if store.configuredNodeInstallation != nil {
            return StatusBadgeModel(text: "当前使用", systemImage: "checkmark.circle.fill", color: .green)
        }
        return StatusBadgeModel(text: "配置缺失", systemImage: "exclamationmark.triangle.fill", color: .red)
    }

    private var configuredJavaOverviewStatus: StatusBadgeModel {
        guard let selectedJavaHome = store.snapshot?.settings.selectedJavaHome, !selectedJavaHome.isEmpty else {
            let hasInstallations = store.snapshot?.javaInstallations.isEmpty == false
            return StatusBadgeModel(
                text: hasInstallations ? "尚未选择" : "尚未安装",
                systemImage: hasInstallations ? "circle.dashed" : "square.and.arrow.down",
                color: .orange
            )
        }
        let isInstalled = store.snapshot?.javaInstallations.contains { $0.homePath == selectedJavaHome } == true
        return isInstalled
            ? StatusBadgeModel(text: "当前使用", systemImage: "checkmark.circle.fill", color: .green)
            : StatusBadgeModel(text: "配置缺失", systemImage: "exclamationmark.triangle.fill", color: .red)
    }

    private var configuredPythonOverviewStatus: StatusBadgeModel {
        guard let selectedPythonHome = store.snapshot?.settings.selectedPythonHome, !selectedPythonHome.isEmpty else {
            let hasInstallations = store.snapshot?.pythonInstallations.isEmpty == false
            return StatusBadgeModel(
                text: hasInstallations ? "尚未选择" : "尚未安装",
                systemImage: hasInstallations ? "circle.dashed" : "square.and.arrow.down",
                color: .orange
            )
        }
        let isInstalled = store.snapshot?.pythonInstallations.contains { $0.homePath == selectedPythonHome } == true
        return isInstalled
            ? StatusBadgeModel(text: "当前使用", systemImage: "checkmark.circle.fill", color: .green)
            : StatusBadgeModel(text: "配置缺失", systemImage: "exclamationmark.triangle.fill", color: .red)
    }

    private var nodeOverviewActionTitle: String {
        if store.configuredNodeInstallation != nil {
            return "管理版本"
        }
        return store.snapshot?.installations.isEmpty == false ? "选择版本" : "安装 Node"
    }

    private var javaOverviewActionTitle: String {
        let selectedHome = store.snapshot?.settings.selectedJavaHome
        let isSelectedInstalled = store.snapshot?.javaInstallations.contains { $0.homePath == selectedHome } == true
        if isSelectedInstalled {
            return "管理版本"
        }
        return store.snapshot?.javaInstallations.isEmpty == false ? "选择版本" : "安装 JDK"
    }

    private var pythonOverviewActionTitle: String {
        let selectedHome = store.snapshot?.settings.selectedPythonHome
        let isSelectedInstalled = store.snapshot?.pythonInstallations.contains { $0.homePath == selectedHome } == true
        if isSelectedInstalled {
            return "管理版本"
        }
        return store.snapshot?.pythonInstallations.isEmpty == false ? "选择版本" : "安装 Python"
    }

    private var overviewSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
                RuntimeOverviewCard(
                    title: "Node.js",
                    version: store.configuredNodeVersion,
                    status: configuredNodeOverviewStatus,
                    path: store.configuredNodeInstallation?.installPath ?? "尚未选择运行时",
                    systemImage: "shippingbox.fill",
                    color: .green,
                    actionTitle: nodeOverviewActionTitle,
                    action: { selectedSection = .node }
                )
                RuntimeOverviewCard(
                    title: "Java",
                    version: RuntimeDisplayFormatter.javaVersion(store.snapshot?.settings.selectedJavaVersion),
                    status: configuredJavaOverviewStatus,
                    path: store.snapshot?.settings.selectedJavaHome ?? "尚未选择运行时",
                    systemImage: "cup.and.saucer.fill",
                    color: .orange,
                    actionTitle: javaOverviewActionTitle,
                    action: { selectedSection = .jdk }
                )
                RuntimeOverviewCard(
                    title: "Python",
                    version: store.snapshot?.settings.selectedPythonVersion ?? "--",
                    status: configuredPythonOverviewStatus,
                    path: store.snapshot?.settings.selectedPythonHome ?? "尚未选择运行时",
                    systemImage: "chevron.left.forwardslash.chevron.right",
                    color: .blue,
                    actionTitle: pythonOverviewActionTitle,
                    action: { selectedSection = .python }
                )
            }

            GroupBox("环境解析结果") {
                VStack(alignment: .leading, spacing: 10) {
                    LabeledContent("版本来源") {
                        Text(projectPreferenceText(store.snapshot?.settings.projectVersionPreference ?? .followProjectFiles))
                    }
                    LabeledContent("Node 请求版本") {
                        Text(store.configuredNodeVersion)
                            .font(.body.monospacedDigit())
                    }
                    LabeledContent("环境预设") {
                        Text(currentProfileName)
                    }
                    LabeledContent("生效范围") {
                        Text("新打开的终端会读取 ENVPilot 环境变量")
                    }
                }
            }

            GroupBox {
                DisclosureGroup(isExpanded: $isEnvironmentDetailsExpanded) {
                    VStack(alignment: .leading, spacing: 11) {
                        Divider()
                        PathRow(title: "Node 安装目录", value: store.configuredNodeInstallation?.installPath ?? "未选择")
                        Divider()
                        PathRow(title: "Node 可执行文件", value: store.configuredNodeInstallation?.executablePath ?? "未选择")
                        Divider()
                        PathRow(title: "JAVA_HOME", value: store.snapshot?.settings.selectedJavaHome ?? "未选择")
                        Divider()
                        PathRow(title: "PYTHON_HOME", value: store.snapshot?.settings.selectedPythonHome ?? "未选择")
                    }
                    .padding(.top, 8)
                } label: {
                    HStack {
                        Label("环境详情", systemImage: "terminal")
                            .font(.headline)
                        Spacer()
                        Text("复制或在 Finder 中定位运行时路径")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var nodeSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox("已安装 Node") {
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
                                primaryStatusBadge: isSelected ? StatusBadgeModel(text: "当前使用", systemImage: "checkmark.circle.fill", color: .green) : nil,
                                destructiveTitle: canUninstall ? "卸载" : "",
                                primaryAction: { Task { await store.setDefaultNode(version: item.version) } },
                                destructiveAction: {
                                    pendingUninstallRequest = RuntimeUninstallRequest(
                                        target: .node(version: item.version, path: item.installPath, isCurrent: isSelected)
                                    )
                                },
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

            GroupBox {
                VStack(alignment: .leading, spacing: 16) {
                    SectionHeader(
                        title: "获取与安装 Node",
                        subtitle: "从 Node 官方分发获取版本，并安装到 ENVPilot 管理目录。",
                        systemImage: "square.and.arrow.down"
                    )

                    installNodePanel
                }
            }
        }
    }

    private var jdkSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox("已安装 JDK") {
                if let javaInstallations = store.snapshot?.javaInstallations, !javaInstallations.isEmpty {
                    VStack(spacing: 8) {
                        ForEach(javaInstallations) { jdk in
                            let canUninstall = isManagedJavaPath(jdk.homePath)
                            let isSelected = store.snapshot?.settings.selectedJavaHome == jdk.homePath
                            RuntimeListRow(
                                title: "JDK \(RuntimeDisplayFormatter.javaVersion(jdk.version))",
                                path: jdk.homePath,
                                badges: javaBadges(for: jdk),
                                primaryTitle: isSelected ? "" : "切换",
                                primarySystemImage: "arrow.triangle.2.circlepath",
                                primaryStatusBadge: isSelected ? StatusBadgeModel(text: "当前使用", systemImage: "checkmark.circle.fill", color: .green) : nil,
                                destructiveTitle: canUninstall ? "卸载" : "",
                                primaryAction: { Task { await store.setDefaultJava(version: jdk.version, homePath: jdk.homePath) } },
                                destructiveAction: {
                                    pendingUninstallRequest = RuntimeUninstallRequest(
                                        target: .java(version: jdk.version, path: jdk.homePath, isCurrent: isSelected)
                                    )
                                },
                                isDisabled: store.isLoading
                            )
                        }
                    }
                } else {
                    EmptyState(
                        title: "未发现 ENVPilot JDK",
                        message: "可以在上方获取 JDK 候选版本并安装到 ENVPilot 目录。",
                        systemImage: "cup.and.saucer"
                    )
                }
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 16) {
                    SectionHeader(
                        title: "获取与安装 JDK",
                        subtitle: "从可用供应商获取 JDK，并安装到 ENVPilot 管理目录。",
                        systemImage: "square.and.arrow.down"
                    )
                    installJavaPanel
                }
            }
        }
    }

    private var pythonSection: some View {
        VStack(alignment: .leading, spacing: 16) {
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
                                primaryStatusBadge: isSelected ? StatusBadgeModel(text: "当前使用", systemImage: "checkmark.circle.fill", color: .green) : nil,
                                destructiveTitle: isManagedPythonPath(python.homePath) ? "卸载" : "",
                                primaryAction: { Task { await store.setDefaultPython(version: python.version, homePath: python.homePath) } },
                                destructiveAction: {
                                    pendingUninstallRequest = RuntimeUninstallRequest(
                                        target: .python(version: python.version, path: python.homePath, isCurrent: isSelected)
                                    )
                                },
                                isDisabled: store.isLoading
                            )
                        }
                    }
                } else {
                    EmptyState(
                        title: "未发现 ENVPilot Python",
                        message: "可以在上方获取 Python 官方候选版本并安装到 ENVPilot 目录。",
                        systemImage: "curlybraces"
                    )
                }
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 16) {
                    SectionHeader(
                        title: "获取与安装 Python",
                        subtitle: "从 Python 官方源码构建并安装到 ENVPilot 管理目录。",
                        systemImage: "square.and.arrow.down"
                    )
                    installPythonPanel
                }
            }
        }
    }

    private var installNodePanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("筛选 Node 版本")
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
                    Label("获取版本", systemImage: "arrow.clockwise")
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .disabled(store.isLoading)
            }
            .settingsControlGroup()

            if store.nodeDownloadCandidates.isEmpty {
                InlineMessage(message: "点击“获取版本”后展示 Node 官方可安装版本；输入框用于筛选结果。", systemImage: "info.circle", color: .blue)
            } else {
                VStack(spacing: 8) {
                    ForEach(filteredNodeDownloadCandidates.prefix(12)) { candidate in
                        let isInstalled = isNodeCandidateInstalled(candidate)
                        let isInstalling = store.installingCandidateID == nodeCandidateID(candidate)
                        DownloadCandidateRow(
                            title: "Node \(candidate.version)",
                            subtitle: candidate.lts.map { "LTS \($0)" } ?? "Current",
                            badges: nodeCandidateBadges(candidate, isInstalled: isInstalled),
                            installationProgress: isInstalling ? store.installationProgress : nil,
                            actionTitle: isInstalled ? "已安装" : (isInstalling ? "安装中" : "安装"),
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
                    Text("筛选 JDK 版本")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.primary)
                    TextField("过滤版本，例如 21、17、Temurin 或 Zulu", text: $javaCandidateSearchText)
                        .textFieldStyle(EnvPilotTextFieldStyle())
                        .disabled(store.isLoading)
                }
                Toggle("仅 LTS", isOn: $javaCandidatesLTSOnly)
                    .toggleStyle(.switch)
                    .disabled(store.isLoading)
                Button {
                    Task { await store.queryJavaDownloadCandidates(ltsOnly: javaCandidatesLTSOnly) }
                } label: {
                    Label("获取版本", systemImage: "arrow.clockwise")
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .disabled(store.isLoading)
            }
            .settingsControlGroup()

            if store.javaDownloadCandidates.isEmpty {
                InlineMessage(message: "点击“获取版本”后展示 JDK 可安装版本；输入框用于筛选结果。", systemImage: "info.circle", color: .blue)
            } else {
                VStack(spacing: 8) {
                    ForEach(filteredJavaDownloadCandidates.prefix(12)) { candidate in
                        let isInstalled = isJavaCandidateInstalled(candidate)
                        let isInstalling = store.installingCandidateID == javaCandidateID(candidate)
                        DownloadCandidateRow(
                            title: "JDK \(candidate.featureVersion)",
                            subtitle: "\(candidate.vendor) \(candidate.version)",
                            badges: javaCandidateBadges(candidate, isInstalled: isInstalled),
                            installationProgress: isInstalling ? store.installationProgress : nil,
                            actionTitle: isInstalled ? "已安装" : (isInstalling ? "安装中" : "安装"),
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
                    Text("筛选 Python 版本")
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
                    Label("获取版本", systemImage: "arrow.clockwise")
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .disabled(store.isLoading)
            }
            .settingsControlGroup()

            if store.pythonDownloadCandidates.isEmpty {
                InlineMessage(message: "点击“获取版本”后展示 Python 官方源码版本；安装会在本机编译，耗时会比 Node/JDK 更长。", systemImage: "info.circle", color: .blue)
            } else {
                VStack(spacing: 8) {
                    ForEach(filteredPythonDownloadCandidates.prefix(12)) { candidate in
                        let isInstalled = isPythonCandidateInstalled(candidate)
                        let isInstalling = store.installingCandidateID == pythonCandidateID(candidate)
                        DownloadCandidateRow(
                            title: "Python \(candidate.version)",
                            subtitle: "CPython source · \(candidate.packageName)",
                            badges: pythonCandidateBadges(candidate, isInstalled: isInstalled),
                            installationProgress: isInstalling ? store.installationProgress : nil,
                            actionTitle: isInstalled ? "已安装" : (isInstalling ? "安装中" : "安装"),
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
                    title: "版本来源",
                    subtitle: "控制进入项目目录时的运行时版本选择规则。",
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
        EnvironmentProfilesView(
            profiles: profiles,
            selectedProfileID: selectedProfileID,
            draftProfile: $draftProfile,
            newProfileName: $newProfileName,
            isLoading: store.isLoading,
            isDirty: isProfileDirty,
            validationMessage: profileValidationMessage,
            onSelectProfile: requestProfileSelection,
            onCreateProfile: createProfile,
            onResetProfile: { synchronizeFromSnapshot(forceProfile: true) },
            onSaveProfile: { Task { await store.saveProfile(draftProfile) } }
        )
    }

    private var currentProfileName: String {
        guard let selectedID = store.snapshot?.settings.selectedProfileID,
              let profile = store.snapshot?.settings.profiles.first(where: { $0.id == selectedID }) else {
            return "未选择"
        }
        return profile.name
    }

    private var sectionSelectionBinding: Binding<SettingsSection?> {
        Binding(
            get: { selectedSection },
            set: { requestSectionSelection($0) }
        )
    }

    private var uninstallConfirmationBinding: Binding<Bool> {
        Binding(
            get: { pendingUninstallRequest != nil },
            set: { isPresented in
                if !isPresented {
                    pendingUninstallRequest = nil
                }
            }
        )
    }

    private var pendingProfileNavigationBinding: Binding<Bool> {
        Binding(
            get: { pendingProfileNavigation != nil },
            set: { isPresented in
                if !isPresented {
                    pendingProfileNavigation = nil
                }
            }
        )
    }

    private var isProfileDirty: Bool {
        guard let selectedProfileID,
              let savedProfile = profiles.first(where: { $0.id == selectedProfileID }) else {
            return false
        }
        return draftProfile != savedProfile
    }

    private var profileValidationMessage: String? {
        if draftProfile.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "环境预设名称不能为空。"
        }

        let registries = [
            ("npm registry", draftProfile.npmRegistry),
            ("pnpm registry", draftProfile.pnpmRegistry),
            ("yarn registry", draftProfile.yarnRegistry),
        ]
        for (label, value) in registries {
            let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty else {
                continue
            }
            guard let components = URLComponents(string: normalized),
                  let scheme = components.scheme?.lowercased(),
                  ["http", "https"].contains(scheme),
                  components.host?.isEmpty == false else {
                return "\(label) 需要填写完整的 http 或 https 地址。"
            }
        }

        let keys = draftProfile.variables.map { $0.key.trimmingCharacters(in: .whitespacesAndNewlines) }
        if keys.contains(where: { $0.isEmpty }) {
            return "自定义环境变量名称不能为空。"
        }
        if let invalidKey = keys.first(where: {
            $0.range(of: #"^[A-Za-z_][A-Za-z0-9_]*$"#, options: .regularExpression) == nil
        }) {
            return "环境变量“\(invalidKey)”格式无效，只能使用字母、数字和下划线，且不能以数字开头。"
        }
        if Set(keys).count != keys.count {
            return "自定义环境变量名称不能重复。"
        }
        return nil
    }

    private func requestSectionSelection(_ section: SettingsSection?) {
        guard section != selectedSection else {
            return
        }
        if selectedSection == .profiles, section != .profiles, isProfileDirty {
            pendingProfileNavigation = .section(section)
            return
        }
        selectedSection = section
    }

    private func requestProfileSelection(_ profileID: UUID?) {
        guard profileID != selectedProfileID else {
            return
        }
        if isProfileDirty {
            pendingProfileNavigation = .profile(profileID)
            return
        }
        commitProfileSelection(profileID)
    }

    private func createProfile() {
        let name = newProfileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            return
        }
        newProfileName = ""
        Task { await store.createProfile(named: name) }
    }

    private func commitProfileSelection(_ profileID: UUID?) {
        selectedProfileID = profileID
        if let profileID,
           let selected = profiles.first(where: { $0.id == profileID }) {
            draftProfile = selected
            Task { await store.setSelectedProfile(id: profileID) }
        }
    }

    private func saveProfileAndContinue() {
        guard let destination = pendingProfileNavigation,
              profileValidationMessage == nil else {
            return
        }
        let profile = draftProfile
        Task {
            guard await store.saveProfile(profile) else {
                return
            }
            pendingProfileNavigation = nil
            continueProfileNavigation(to: destination)
        }
    }

    private func discardProfileChangesAndContinue() {
        guard let destination = pendingProfileNavigation else {
            return
        }
        synchronizeFromSnapshot(forceProfile: true)
        pendingProfileNavigation = nil
        continueProfileNavigation(to: destination)
    }

    private func continueProfileNavigation(to destination: PendingProfileNavigation) {
        switch destination {
        case .profile(let profileID):
            commitProfileSelection(profileID)
        case .section(let section):
            selectedSection = section
        }
    }

    private func performUninstall(_ request: RuntimeUninstallRequest) {
        pendingUninstallRequest = nil
        guard !request.isCurrent else {
            return
        }
        Task {
            switch request.target {
            case .node(let version, _, _):
                await store.uninstallNode(version: version)
            case .java(let version, let homePath, _):
                await store.uninstallJava(version: version, homePath: homePath)
            case .python(let version, let homePath, _):
                await store.uninstallPython(version: version, homePath: homePath)
            }
        }
    }

    private var nodeEmptyMessage: String {
        var messages = ["可以在上方获取 Node 官方候选版本并安装到 ENVPilot 目录。"]
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
        let query = normalizedJavaCandidateSearchText
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

    private var normalizedJavaCandidateSearchText: String {
        javaCandidateSearchText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "jdk", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
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

    private func synchronizeFromSnapshot(forceProfile: Bool = false) {
        guard let snapshot = store.snapshot else {
            return
        }

        isSynchronizing = true
        defer { isSynchronizing = false }

        projectPreference = snapshot.settings.projectVersionPreference
        let availableProfiles = snapshot.settings.profiles

        let preferredID = snapshot.settings.selectedProfileID ?? availableProfiles.first?.id
        let profileSelectionChanged = selectedProfileID != preferredID
        selectedProfileID = preferredID

        if let preferredID,
           let selected = availableProfiles.first(where: { $0.id == preferredID }) {
            if forceProfile || profileSelectionChanged || !isProfileDirty {
                draftProfile = selected
            }
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
            badges.append(StatusBadgeModel(text: "已安装", systemImage: "checkmark.circle.fill", color: .green))
        }
        if candidate.lts != nil {
            badges.append(StatusBadgeModel(text: "LTS", systemImage: "clock.badge.checkmark", color: .blue))
        }
        return badges
    }

    private func javaCandidateBadges(_ candidate: JavaDownloadCandidate, isInstalled: Bool) -> [StatusBadgeModel] {
        var badges: [StatusBadgeModel] = []
        if isInstalled {
            badges.append(StatusBadgeModel(text: "已安装", systemImage: "checkmark.circle.fill", color: .green))
        }
        if candidate.version.contains("LTS") || [25, 21, 17, 11, 8].contains(candidate.featureVersion) {
            badges.append(StatusBadgeModel(text: "LTS", systemImage: "clock.badge.checkmark", color: .blue))
        }
        return badges
    }

    private func pythonCandidateBadges(_ candidate: PythonDownloadCandidate, isInstalled: Bool) -> [StatusBadgeModel] {
        var badges: [StatusBadgeModel] = []
        if isInstalled {
            badges.append(StatusBadgeModel(text: "已安装", systemImage: "checkmark.circle.fill", color: .green))
        }
        badges.append(StatusBadgeModel(text: "官方源码", systemImage: "curlybraces", color: .blue))
        return badges
    }

    private func javaVersion(_ version: String, matchesFeatureVersion featureVersion: Int) -> Bool {
        version == String(featureVersion) || version.hasPrefix("\(featureVersion).")
    }
}

enum AppPalette {
    static let windowBackground = Color(nsColor: .windowBackgroundColor)
    static let sidebarBackground = Color(nsColor: .windowBackgroundColor)
    static let panelSurface = Color(nsColor: .controlBackgroundColor)
    static let controlSurface = Color(nsColor: .textBackgroundColor)
    static let rowSurface = Color(nsColor: .textBackgroundColor).opacity(0.82)
    static let border = Color(nsColor: .separatorColor).opacity(0.52)
    static let borderStrong = Color(nsColor: .separatorColor).opacity(0.82)
    static let shadow = Color.black.opacity(0.03)
}

private struct LiquidGlassBackground: View {
    var body: some View {
        ZStack {
            AppPalette.windowBackground

            LinearGradient(
                colors: [
                    Color.accentColor.opacity(0.035),
                    Color.clear,
                    Color(nsColor: .systemTeal).opacity(0.015),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
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
            .shadow(color: AppPalette.shadow, radius: 2, x: 0, y: 1)
    }
}

extension View {
    func liquidGlassPanel(cornerRadius: CGFloat = 14, tint: Color = .clear) -> some View {
        modifier(LiquidGlassPanelModifier(cornerRadius: cornerRadius, tint: tint))
    }

    func settingsControlGroup() -> some View {
        padding(13)
            .background(AppPalette.controlSurface.opacity(0.72), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(AppPalette.border, lineWidth: 1)
            }
    }
}

struct EnvPilotTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .textFieldStyle(.plain)
            .padding(.horizontal, 10)
            .frame(minHeight: 32)
            .background(AppPalette.controlSurface, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(AppPalette.borderStrong, lineWidth: 1)
            }
    }
}

struct ProfileInputRow<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 116, alignment: .trailing)
            content
                .frame(maxWidth: .infinity)
        }
    }
}

private struct LiquidGlassGroupBoxStyle: GroupBoxStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            configuration.label
                .font(.headline)
            configuration.content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlassPanel(cornerRadius: 14, tint: Color.clear)
    }
}

private struct SettingsDetailHeader: View {
    let section: SettingsSection
    let isLoading: Bool
    let refreshAction: (() -> Void)?

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: section.systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 42, height: 42)
                .background(Color.accentColor.opacity(0.11), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(section.title)
                    .font(.title.weight(.semibold))
                Text(section.subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let refreshAction {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                }

                Button {
                    refreshAction()
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
                .controlSize(.regular)
                .buttonStyle(.bordered)
                .keyboardShortcut("r", modifiers: .command)
                .help("刷新运行时信息")
                .disabled(isLoading)
            }
        }
        .padding(.bottom, 4)
    }
}

private enum SettingsSection: String, CaseIterable, Identifiable, Hashable {
    case overview
    case node
    case jdk
    case python
    case project
    case profiles
    case settings

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
            return "项目环境"
        case .profiles:
            return "环境预设"
        case .settings:
            return "设置"
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
            return "查看并配置进入项目目录时的版本选择规则。"
        case .profiles:
            return "管理 registry、NODE_OPTIONS 与自定义环境变量预设。"
        case .settings:
            return "配置 ENVPilot 的应用行为与系统集成。"
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
        case .settings:
            return "gearshape"
        }
    }
}

private struct StatusBadgeModel: Identifiable {
    let id = UUID()
    let text: String
    let systemImage: String
    let color: Color
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
        if items.isEmpty {
            HStack(spacing: 8) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 48, alignment: .leading)
                Text(emptyTitle)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
        } else {
            Menu {
                ForEach(items) { item in
                    Button {
                        action(item)
                    } label: {
                        Label(version(item), systemImage: isSelected(item) ? "checkmark.circle.fill" : "circle")
                    }
                    .help(path(item))
                }
            } label: {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 48, alignment: .leading)
                    Text(selectedVersion)
                        .font(.subheadline.monospacedDigit().weight(.medium))
                    Spacer(minLength: 0)
                    Text("切换")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .frame(height: 34)
                .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .buttonStyle(.plain)
            .background(AppPalette.rowSurface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(AppPalette.border, lineWidth: 1)
            }
        }
    }

    private var selectedVersion: String {
        items.first(where: isSelected).map(version) ?? "未选择"
    }
}

private struct RuntimeMenuRow: View {
    let title: String
    let value: String
    let detail: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(value)
                        .font(.subheadline.monospacedDigit().weight(.medium))
                        .lineLimit(1)
                }
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

struct InlineMessage: View {
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
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(color.opacity(0.075), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(color.opacity(0.18), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }
}

struct SectionHeader: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 30, height: 30)
                .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct RuntimeOverviewCard: View {
    let title: String
    let version: String
    let status: StatusBadgeModel
    let path: String
    let systemImage: String
    let color: Color
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(alignment: .top) {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 38, height: 38)
                    .background(color.opacity(0.11), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                Spacer()

                StatusBadge(
                    text: status.text,
                    systemImage: status.systemImage,
                    color: status.color
                )
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Text(version)
                    .font(.title2.monospacedDigit().weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

            Text(path)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(path)

            Button {
                action()
            } label: {
                HStack(spacing: 5) {
                    Text(actionTitle)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 188, alignment: .leading)
        .background(AppPalette.panelSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(color.opacity(0.78))
                .frame(width: 3)
                .padding(.vertical, 14)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(AppPalette.border, lineWidth: 1)
        }
        .shadow(color: AppPalette.shadow, radius: 2.5, x: 0, y: 1)
    }
}

private struct PathRow: View {
    let title: String
    let value: String
    @State private var didCopy = false

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .frame(width: 132, alignment: .leading)

            Text(value)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(value)

            Spacer(minLength: 8)

            Button {
                DesktopPathActions.copy(value)
                didCopy = true
                Task {
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    didCopy = false
                }
            } label: {
                Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.borderless)
            .help(didCopy ? "已复制" : "复制路径")
            .accessibilityLabel(didCopy ? "路径已复制" : "复制路径")
            .disabled(!isAbsolutePath)

            Button {
                DesktopPathActions.revealInFinder(value)
            } label: {
                Image(systemName: "folder")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.borderless)
            .help("在 Finder 中显示")
            .accessibilityLabel("在 Finder 中显示路径")
            .disabled(!pathExists)
        }
    }

    private var isAbsolutePath: Bool {
        value.hasPrefix("/")
    }

    private var pathExists: Bool {
        isAbsolutePath && FileManager.default.fileExists(atPath: value)
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
                .buttonStyle(.bordered)
                .disabled(isDisabled)
            }

            if !destructiveTitle.isEmpty {
                Menu {
                    Button(role: .destructive) {
                        destructiveAction()
                    } label: {
                        Label(destructiveTitle, systemImage: "trash")
                    }
                } label: {
                    Label("更多", systemImage: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("更多版本操作")
                .disabled(isDisabled)
            }
        }
        .padding(13)
        .background(AppPalette.rowSurface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(AppPalette.border, lineWidth: 1)
        }
    }
}

private struct DownloadCandidateRow: View {
    let title: String
    let subtitle: String
    let badges: [StatusBadgeModel]
    let installationProgress: RuntimeInstallationProgress?
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
                if let installationProgress {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 6) {
                            Text(installationProgress.stage.rawValue)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.blue)
                            Spacer(minLength: 8)
                            if let fraction = installationProgress.fractionCompleted {
                                Text(fraction, format: .percent.precision(.fractionLength(0)))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        if let fraction = installationProgress.fractionCompleted {
                            ProgressView(value: fraction)
                                .progressViewStyle(.linear)
                        } else {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(installationProgress.message)
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .padding(.top, 3)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("安装阶段：\(installationProgress.stage.rawValue)")
                    .accessibilityValue(installationProgress.message)
                }
            }
            Spacer()
            Button {
                action()
            } label: {
                Label(actionTitle, systemImage: actionSystemImage)
            }
            .buttonStyle(.bordered)
            .disabled(isDisabled)
        }
        .padding(13)
        .background(installationProgress == nil ? AppPalette.rowSurface : Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(installationProgress == nil ? AppPalette.border : Color.blue.opacity(0.34), lineWidth: 1)
        }
    }
}

struct EmptyState: View {
    let title: String
    let message: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 9) {
            Image(systemName: systemImage)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 42, height: 42)
                .background(AppPalette.controlSurface.opacity(0.8), in: Circle())
            VStack(spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
    }
}

struct StatusBadge: View {
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
                    .stroke(AppPalette.border, lineWidth: 0.8)
            )
            .clipShape(Capsule())
            .accessibilityElement(children: .combine)
    }
}
