import Foundation
import ENVPilotCore

@MainActor
final class NodeRuntimeStore: ObservableObject {
    @Published private(set) var snapshot: NodeRuntimeSnapshot?
    @Published private(set) var sdkmanJavaCandidates: [SDKMANJavaCandidate] = []
    @Published private(set) var isLoading = false
    @Published private(set) var loadingMessage: String?
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
        guard let selectedVersion = snapshot?.settings.selectedVersion else {
            return nil
        }
        return snapshot?.installations.first(where: { $0.version == selectedVersion })
    }

    var configuredNodeStatus: String {
        guard snapshot?.settings.selectedVersion != nil else {
            return "未配置"
        }
        if configuredNodeInstallation != nil {
            return "已通过 NVM 检测到"
        }
        return "已配置，但未通过 NVM 检测到安装"
    }

    var displayNodeVersion: String {
        snapshot?.activeVersion ?? snapshot?.settings.selectedVersion ?? "--"
    }

    var displayJavaVersion: String {
        snapshot?.settings.selectedJavaVersion ?? snapshot?.activeJavaVersion ?? "--"
    }

    var sdkmanStatus: SDKMANRuntimeStatus {
        snapshot?.sdkmanStatus ?? .init()
    }

    var sdkmanStatusText: String {
        let status = sdkmanStatus
        if status.isInstalled {
            return status.hasManagedJavaInstallations ? "已安装（检测到 SDKMAN 管理的 JDK）" : "已安装"
        }
        if status.canInstall {
            return "未安装（可自动安装）"
        }
        return "未安装（当前环境不可自动安装）"
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
        let progress = makeProgressUpdater()
        await runOperation(message: "正在安装 Node \(version)...") { [self] in
            try await self.runBackground { [service] in
                try service.installNode(version: version, progress: progress)
                return try service.loadSnapshot(progress: progress)
            }
        } onError: { error in
            "安装 Node 版本失败：\(error.localizedDescription)"
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

    func installSDKMAN() async {
        let progress = makeProgressUpdater()
        await runOperation(message: "正在安装 SDKMAN...") { [self] in
            try await self.runBackground { [service] in
                try service.installSDKMAN(progress: progress)
                return try service.loadSnapshot(progress: progress)
            }
        } onError: { error in
            "安装 SDKMAN 失败：\(error.localizedDescription)"
        }
    }

    func installJavaWithSDKMAN(identifier: String) async {
        let progress = makeProgressUpdater()
        await runOperation(message: "正在通过 SDKMAN 安装 JDK \(identifier)...") { [self] in
            try await self.runBackground { [service] in
                try service.installJavaWithSDKMAN(identifier: identifier, progress: progress)
                return try service.loadSnapshot(progress: progress)
            }
        } onError: { error in
            "通过 SDKMAN 安装 JDK 失败：\(error.localizedDescription)"
        }
        if sdkmanStatus.isInstalled {
            await querySDKMANJavaCandidates()
        }
    }

    func querySDKMANJavaCandidates() async {
        isLoading = true
        loadingMessage = "正在查询 SDKMAN JDK 列表..."
        defer {
            isLoading = false
            loadingMessage = nil
        }

        do {
            sdkmanJavaCandidates = try await runBackground { [service] in
                try service.listAvailableJavaCandidatesWithSDKMAN()
            }
            latestError = nil
        } catch {
            latestError = "查询 SDKMAN JDK 列表失败：\(error.localizedDescription)"
        }
    }

    func uninstallJavaWithSDKMAN(identifier: String) async {
        let progress = makeProgressUpdater()
        await runOperation(message: "正在通过 SDKMAN 卸载 JDK \(identifier)...") { [self] in
            try await self.runBackground { [service] in
                try service.uninstallJavaWithSDKMAN(identifier: identifier, progress: progress)
                return try service.loadSnapshot(progress: progress)
            }
        } onError: { error in
            "通过 SDKMAN 卸载 JDK 失败：\(error.localizedDescription)"
        }
        await querySDKMANJavaCandidates()
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

    private func makeProgressUpdater() -> @Sendable (String) -> Void {
        { [weak self] message in
            Task { @MainActor [weak self] in
                self?.loadingMessage = message
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
        }

        do {
            snapshot = try await operation()
            latestError = nil
        } catch {
            latestError = onError(error)
        }
    }
}
