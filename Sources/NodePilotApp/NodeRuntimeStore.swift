import Foundation
import ENVPilotCore

@MainActor
final class NodeRuntimeStore: ObservableObject {
    @Published private(set) var snapshot: NodeRuntimeSnapshot?
    @Published private(set) var nodeDownloadCandidates: [NodeDownloadCandidate] = []
    @Published private(set) var javaDownloadCandidates: [JavaDownloadCandidate] = []
    @Published private(set) var pythonDownloadCandidates: [PythonDownloadCandidate] = []
    @Published private(set) var isLoading = false
    @Published private(set) var loadingMessage: String?
    @Published private(set) var installingCandidateID: String?
    @Published private(set) var installingCandidateMessage: String?
    @Published private(set) var installationProgress: RuntimeInstallationProgress?
    @Published private(set) var latestNotice: String?
    @Published var latestError: String?

    private let service: any NodeRuntimeServicing

    init(service: any NodeRuntimeServicing) {
        self.service = service
        Task { await refresh() }
    }

    var configuredNodeVersion: String {
        snapshot?.settings.selectedVersion ?? "--"
    }

    var configuredNodeInstallation: NodeInstallation? {
        guard let settings = snapshot?.settings else {
            return nil
        }
        if let selectedNodePath = settings.selectedNodePath {
            return snapshot?.installations.first(where: { $0.installPath == selectedNodePath })
        }
        guard let selectedVersion = settings.selectedVersion else {
            return nil
        }
        return snapshot?.installations.first(where: { $0.version == selectedVersion })
    }

    var configuredNodeStatus: String {
        guard snapshot?.settings.selectedVersion != nil else {
            return "尚未选择"
        }
        if configuredNodeInstallation != nil {
            return "当前使用"
        }
        return "配置缺失"
    }

    var displayNodeVersion: String {
        snapshot?.activeVersion ?? snapshot?.settings.selectedVersion ?? "--"
    }

    var displayJavaVersion: String {
        RuntimeDisplayFormatter.javaVersion(
            snapshot?.settings.selectedJavaVersion ?? snapshot?.activeJavaVersion
        )
    }

    var displayPythonVersion: String {
        snapshot?.settings.selectedPythonVersion ?? snapshot?.activePythonVersion ?? "--"
    }

    var displayNodePath: String {
        if let installation = configuredNodeInstallation {
            return installation.installPath
        }
        return snapshot?.activeNodePath ?? "--"
    }

    var menuBarTitle: String {
        guard snapshot != nil else { return "ENVPilot" }
        let node = displayNodeVersion
        let java = displayJavaVersion
        let python = displayPythonVersion

        if python != "--" {
            return "Node \(node) | JDK \(java) | Python \(python)"
        }
        if java != "--" {
            return "Node \(node) | JDK \(java)"
        }
        return "Node \(node)"
    }

    func refresh() async {
        let progress = makeProgressUpdater()
        await runOperation(message: "正在刷新运行时信息...") { [self] in
            try await self.runBackground { [service] in
                try service.loadSnapshot(progress: progress)
            }
        } onError: { error in
            "刷新失败：\(error.localizedDescription)"
        }
    }

    func setDefaultNode(version: String) async {
        let progress = makeProgressUpdater()
        let succeeded = await runOperation(message: "正在切换 Node \(version)...") { [self] in
            try await self.runBackground { [service] in
                try service.setDefaultNode(version: version, progress: progress)
                return try service.loadSnapshot(progress: progress)
            }
        } onError: { error in
            "设置 Node 版本失败：\(error.localizedDescription)"
        }
        if succeeded {
            latestNotice = "已切换到 Node \(version)，新打开的终端将自动生效。"
        }
    }

    func installNode(version: String) async {
        let progress = makeProgressUpdater(candidateID: "node-\(version)")
        let succeeded = await runOperation(message: "正在安装 Node \(version)...") { [self] in
            try await self.runBackground { [service] in
                try service.installNode(version: version, progress: progress)
                return try service.loadSnapshot(progress: progress)
            }
        } onError: { error in
            "安装 Node 版本失败：\(error.localizedDescription)"
        }
        if succeeded {
            latestNotice = "Node \(version) 安装完成，已可设为当前版本。"
        }
    }

    func queryNodeDownloadCandidates(ltsOnly: Bool) async {
        isLoading = true
        loadingMessage = "正在获取 Node 可安装版本..."
        latestNotice = nil
        defer {
            isLoading = false
            loadingMessage = nil
        }

        do {
            nodeDownloadCandidates = try await runBackground { [service] in
                try service.listAvailableNodeVersions(ltsOnly: ltsOnly)
            }
            latestError = nil
        } catch {
            latestError = "获取 Node 可安装版本失败：\(error.localizedDescription)"
        }
    }

    func uninstallNode(version: String) async {
        let progress = makeProgressUpdater()
        let succeeded = await runOperation(message: "正在卸载 Node \(version)...") { [self] in
            try await self.runBackground { [service] in
                try service.uninstallNode(version: version, progress: progress)
                return try service.loadSnapshot(progress: progress)
            }
        } onError: { error in
            "卸载 Node 版本失败：\(error.localizedDescription)"
        }
        if succeeded {
            latestNotice = "Node \(version) 已卸载。"
        }
    }

    func setDefaultJava(version: String, homePath: String) async {
        let succeeded = await runOperation(message: "正在切换 JDK \(version)...") { [self] in
            try await self.runBackground { [service] in
                try service.setDefaultJava(version: version, homePath: homePath)
                return try service.loadSnapshot(progress: nil)
            }
        } onError: { error in
            "设置 JDK 版本失败：\(error.localizedDescription)"
        }
        if succeeded {
            latestNotice = "已切换到 JDK \(version)，新打开的终端将自动生效。"
        }
    }

    func installJava(featureVersion: Int) async {
        let progress = makeProgressUpdater(candidateID: "java-\(featureVersion)")
        let succeeded = await runOperation(message: "正在安装 JDK \(featureVersion)...") { [self] in
            try await self.runBackground { [service] in
                try service.installJava(featureVersion: featureVersion, progress: progress)
                return try service.loadSnapshot(progress: progress)
            }
        } onError: { error in
            "安装 JDK 失败：\(error.localizedDescription)"
        }
        if succeeded {
            latestNotice = "JDK \(featureVersion) 安装完成，已可设为当前版本。"
        }
    }

    func queryJavaDownloadCandidates(ltsOnly: Bool) async {
        isLoading = true
        loadingMessage = "正在获取 JDK 可安装版本..."
        latestNotice = nil
        defer {
            isLoading = false
            loadingMessage = nil
        }

        do {
            javaDownloadCandidates = try await runBackground { [service] in
                try service.listAvailableJavaVersions(ltsOnly: ltsOnly)
            }
            latestError = nil
        } catch {
            latestError = "获取 JDK 可安装版本失败：\(error.localizedDescription)"
        }
    }

    func setDefaultPython(version: String, homePath: String) async {
        let succeeded = await runOperation(message: "正在切换 Python \(version)...") { [self] in
            try await self.runBackground { [service] in
                try service.setDefaultPython(version: version, homePath: homePath)
                return try service.loadSnapshot(progress: nil)
            }
        } onError: { error in
            "设置 Python 版本失败：\(error.localizedDescription)"
        }
        if succeeded {
            latestNotice = "已切换到 Python \(version)，新打开的终端将自动生效。"
        }
    }

    func installPython(version: String) async {
        let progress = makeProgressUpdater(candidateID: "python-\(version)")
        let succeeded = await runOperation(message: "正在安装 Python \(version)...") { [self] in
            try await self.runBackground { [service] in
                try service.installPython(version: version, progress: progress)
                return try service.loadSnapshot(progress: progress)
            }
        } onError: { error in
            "安装 Python 失败：\(error.localizedDescription)"
        }
        if succeeded {
            latestNotice = "Python \(version) 安装完成，已可设为当前版本。"
        }
    }

    func queryPythonDownloadCandidates(stableOnly: Bool) async {
        isLoading = true
        loadingMessage = "正在获取 Python 可安装版本..."
        latestNotice = nil
        defer {
            isLoading = false
            loadingMessage = nil
        }

        do {
            pythonDownloadCandidates = try await runBackground { [service] in
                try service.listAvailablePythonVersions(stableOnly: stableOnly)
            }
            latestError = nil
        } catch {
            latestError = "获取 Python 可安装版本失败：\(error.localizedDescription)"
        }
    }

    func clearDownloadCandidates() {
        nodeDownloadCandidates = []
        javaDownloadCandidates = []
        pythonDownloadCandidates = []
    }

    func uninstallJava(version: String, homePath: String) async {
        let progress = makeProgressUpdater()
        let succeeded = await runOperation(message: "正在卸载 JDK \(version)...") { [self] in
            try await self.runBackground { [service] in
                try service.uninstallJava(homePath: homePath, progress: progress)
                return try service.loadSnapshot(progress: progress)
            }
        } onError: { error in
            "卸载 JDK 失败：\(error.localizedDescription)"
        }
        if succeeded {
            latestNotice = "JDK \(version) 已卸载。"
        }
    }

    func uninstallPython(version: String, homePath: String) async {
        let progress = makeProgressUpdater()
        let succeeded = await runOperation(message: "正在卸载 Python \(version)...") { [self] in
            try await self.runBackground { [service] in
                try service.uninstallPython(homePath: homePath, progress: progress)
                return try service.loadSnapshot(progress: progress)
            }
        } onError: { error in
            "卸载 Python 失败：\(error.localizedDescription)"
        }
        if succeeded {
            latestNotice = "Python \(version) 已卸载。"
        }
    }

    func setSelectedProfile(id: UUID) async {
        let succeeded = await runOperation(message: "正在切换环境预设...") { [self] in
            try await self.runBackground { [service] in
                try service.setSelectedProfile(id: id)
                return try service.loadSnapshot(progress: nil)
            }
        } onError: { error in
            "切换环境预设失败：\(error.localizedDescription)"
        }
        if succeeded,
           let profileName = snapshot?.settings.profiles.first(where: { $0.id == id })?.name {
            latestNotice = "已切换到环境预设“\(profileName)”。"
        }
    }

    @discardableResult
    func saveProfile(_ profile: EnvironmentProfile) async -> Bool {
        let succeeded = await runOperation(message: "正在保存环境预设...") { [self] in
            try await self.runBackground { [service] in
                try service.saveProfile(profile)
                return try service.loadSnapshot(progress: nil)
            }
        } onError: { error in
            "保存环境预设失败：\(error.localizedDescription)"
        }
        if succeeded {
            latestNotice = "环境预设“\(profile.name)”已保存。"
        }
        return succeeded
    }

    func createProfile(named name: String) async {
        let succeeded = await runOperation(message: "正在创建环境预设...") { [self] in
            try await self.runBackground { [service] in
                _ = try service.createProfile(named: name)
                return try service.loadSnapshot(progress: nil)
            }
        } onError: { error in
            "创建环境预设失败：\(error.localizedDescription)"
        }
        if succeeded {
            latestNotice = "环境预设已创建。"
        }
    }

    func setProjectVersionPreference(_ preference: ProjectVersionPreference) async {
        await runOperation(message: "正在更新项目版本策略...") { [self] in
            try await self.runBackground { [service] in
                try service.setProjectVersionPreference(preference)
                return try service.loadSnapshot(progress: nil)
            }
        } onError: { error in
            "更新项目版本策略失败：\(error.localizedDescription)"
        }
    }

    private func runBackground<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await Task.detached(priority: .userInitiated, operation: work).value
    }

    private func makeProgressUpdater(candidateID: String? = nil) -> @Sendable (String) -> Void {
        if let candidateID {
            installingCandidateID = candidateID
            installingCandidateMessage = nil
            installationProgress = RuntimeInstallationProgress(
                candidateID: candidateID,
                message: "正在准备安装..."
            )
        }
        return { [weak self] message in
            Task { @MainActor [weak self] in
                self?.loadingMessage = message
                if let candidateID {
                    self?.installingCandidateMessage = message
                    self?.installationProgress = RuntimeInstallationProgress(
                        candidateID: candidateID,
                        message: message
                    )
                }
            }
        }
    }

    @discardableResult
    private func runOperation(
        message: String,
        _ operation: @escaping () async throws -> NodeRuntimeSnapshot,
        onError: (Error) -> String
    ) async -> Bool {
        isLoading = true
        loadingMessage = message
        latestNotice = nil
        defer {
            isLoading = false
            loadingMessage = nil
            installingCandidateID = nil
            installingCandidateMessage = nil
            installationProgress = nil
        }

        do {
            snapshot = try await operation()
            latestError = nil
            return true
        } catch {
            latestError = onError(error)
            return false
        }
    }
}
