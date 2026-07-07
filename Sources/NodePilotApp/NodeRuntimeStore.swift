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
            return "未配置"
        }
        if configuredNodeInstallation != nil {
            return "已通过 ENVPilot 环境变量接管"
        }
        return "已配置，但未检测到对应 ENVPilot Node 路径"
    }

    var displayNodeVersion: String {
        snapshot?.activeVersion ?? snapshot?.settings.selectedVersion ?? "--"
    }

    var displayJavaVersion: String {
        snapshot?.settings.selectedJavaVersion ?? snapshot?.activeJavaVersion ?? "--"
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
        await runOperation(message: "正在切换 Node \(version)...") { [self] in
            try await self.runBackground { [service] in
                try service.setDefaultNode(version: version, progress: progress)
                return try service.loadSnapshot(progress: progress)
            }
        } onError: { error in
            "设置 Node 版本失败：\(error.localizedDescription)"
        }
    }

    func installNode(version: String) async {
        let progress = makeProgressUpdater(candidateID: "node-\(version)")
        await runOperation(message: "正在安装 Node \(version)...") { [self] in
            try await self.runBackground { [service] in
                try service.installNode(version: version, progress: progress)
                return try service.loadSnapshot(progress: progress)
            }
        } onError: { error in
            "安装 Node 版本失败：\(error.localizedDescription)"
        }
    }

    func queryNodeDownloadCandidates(ltsOnly: Bool) async {
        isLoading = true
        loadingMessage = "正在查询 Node 可安装版本..."
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
            latestError = "查询 Node 可安装版本失败：\(error.localizedDescription)"
        }
    }

    func uninstallNode(version: String) async {
        let progress = makeProgressUpdater()
        await runOperation(message: "正在卸载 Node \(version)...") { [self] in
            try await self.runBackground { [service] in
                try service.uninstallNode(version: version, progress: progress)
                return try service.loadSnapshot(progress: progress)
            }
        } onError: { error in
            "卸载 Node 版本失败：\(error.localizedDescription)"
        }
    }

    func setDefaultJava(version: String, homePath: String) async {
        await runOperation(message: "正在切换 JDK \(version)...") { [self] in
            try await self.runBackground { [service] in
                try service.setDefaultJava(version: version, homePath: homePath)
                return try service.loadSnapshot(progress: nil)
            }
        } onError: { error in
            "设置 JDK 版本失败：\(error.localizedDescription)"
        }
    }

    func installJava(featureVersion: Int) async {
        let progress = makeProgressUpdater(candidateID: "java-\(featureVersion)")
        await runOperation(message: "正在安装 Temurin JDK \(featureVersion)...") { [self] in
            try await self.runBackground { [service] in
                try service.installJava(featureVersion: featureVersion, progress: progress)
                return try service.loadSnapshot(progress: progress)
            }
        } onError: { error in
            "安装 JDK 失败：\(error.localizedDescription)"
        }
    }

    func queryJavaDownloadCandidates(ltsOnly: Bool) async {
        isLoading = true
        loadingMessage = "正在查询 JDK 可安装版本..."
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
            latestError = "查询 JDK 可安装版本失败：\(error.localizedDescription)"
        }
    }

    func setDefaultPython(version: String, homePath: String) async {
        await runOperation(message: "正在切换 Python \(version)...") { [self] in
            try await self.runBackground { [service] in
                try service.setDefaultPython(version: version, homePath: homePath)
                return try service.loadSnapshot(progress: nil)
            }
        } onError: { error in
            "设置 Python 版本失败：\(error.localizedDescription)"
        }
    }

    func installPython(version: String) async {
        let progress = makeProgressUpdater(candidateID: "python-\(version)")
        await runOperation(message: "正在安装 Python \(version)...") { [self] in
            try await self.runBackground { [service] in
                try service.installPython(version: version, progress: progress)
                return try service.loadSnapshot(progress: progress)
            }
        } onError: { error in
            "安装 Python 失败：\(error.localizedDescription)"
        }
    }

    func queryPythonDownloadCandidates(stableOnly: Bool) async {
        isLoading = true
        loadingMessage = "正在查询 Python 可安装版本..."
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
            latestError = "查询 Python 可安装版本失败：\(error.localizedDescription)"
        }
    }

    func clearDownloadCandidates() {
        nodeDownloadCandidates = []
        javaDownloadCandidates = []
        pythonDownloadCandidates = []
    }

    func uninstallJava(version: String, homePath: String) async {
        let progress = makeProgressUpdater()
        await runOperation(message: "正在卸载 JDK \(version)...") { [self] in
            try await self.runBackground { [service] in
                try service.uninstallJava(homePath: homePath, progress: progress)
                return try service.loadSnapshot(progress: progress)
            }
        } onError: { error in
            "卸载 JDK 失败：\(error.localizedDescription)"
        }
    }

    func uninstallPython(version: String, homePath: String) async {
        let progress = makeProgressUpdater()
        await runOperation(message: "正在卸载 Python \(version)...") { [self] in
            try await self.runBackground { [service] in
                try service.uninstallPython(homePath: homePath, progress: progress)
                return try service.loadSnapshot(progress: progress)
            }
        } onError: { error in
            "卸载 Python 失败：\(error.localizedDescription)"
        }
    }

    func setSelectedProfile(id: UUID) async {
        await runOperation(message: "正在切换环境配置...") { [self] in
            try await self.runBackground { [service] in
                try service.setSelectedProfile(id: id)
                return try service.loadSnapshot(progress: nil)
            }
        } onError: { error in
            "切换配置失败：\(error.localizedDescription)"
        }
    }

    func saveProfile(_ profile: EnvironmentProfile) async {
        await runOperation(message: "正在保存环境配置...") { [self] in
            try await self.runBackground { [service] in
                try service.saveProfile(profile)
                return try service.loadSnapshot(progress: nil)
            }
        } onError: { error in
            "保存配置失败：\(error.localizedDescription)"
        }
    }

    func createProfile(named name: String) async {
        await runOperation(message: "正在创建环境配置...") { [self] in
            try await self.runBackground { [service] in
                _ = try service.createProfile(named: name)
                return try service.loadSnapshot(progress: nil)
            }
        } onError: { error in
            "创建配置失败：\(error.localizedDescription)"
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
        }
        return { [weak self] message in
            Task { @MainActor [weak self] in
                self?.loadingMessage = message
                if candidateID != nil {
                    self?.installingCandidateMessage = message
                }
            }
        }
    }

    private func runOperation(
        message: String,
        _ operation: @escaping () async throws -> NodeRuntimeSnapshot,
        onError: (Error) -> String
    ) async {
        isLoading = true
        loadingMessage = message
        defer {
            isLoading = false
            loadingMessage = nil
            installingCandidateID = nil
            installingCandidateMessage = nil
        }

        do {
            snapshot = try await operation()
            latestError = nil
        } catch {
            latestError = onError(error)
        }
    }
}
