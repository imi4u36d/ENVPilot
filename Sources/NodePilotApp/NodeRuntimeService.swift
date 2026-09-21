import Foundation
import ENVPilotCore

/// 界面用到的一层运行时操作。只有「读取」与「按全局选择改动」两类，
/// 没有环境预设与项目作用域相关的入口。
protocol NodeRuntimeServicing: Sendable {
    func loadSnapshot(progress: (@Sendable (String) -> Void)?) throws -> NodeRuntimeSnapshot
    func listAvailableNodeVersions(ltsOnly: Bool) throws -> [NodeDownloadCandidate]
    func listAvailableJavaVersions(ltsOnly: Bool) throws -> [JavaDownloadCandidate]
    func listAvailablePythonVersions(stableOnly: Bool) throws -> [PythonDownloadCandidate]
    func setDefaultNode(version: String, progress: (@Sendable (String) -> Void)?) throws -> NodeRuntimeSnapshot
    func installNode(version: String, progress: (@Sendable (String) -> Void)?) throws -> NodeRuntimeSnapshot
    func uninstallNode(version: String, progress: (@Sendable (String) -> Void)?) throws -> NodeRuntimeSnapshot
    func installJava(featureVersion: Int, progress: (@Sendable (String) -> Void)?) throws -> NodeRuntimeSnapshot
    func uninstallJava(homePath: String, progress: (@Sendable (String) -> Void)?) throws -> NodeRuntimeSnapshot
    func setDefaultJava(version: String, homePath: String) throws -> NodeRuntimeSnapshot
    func installPython(version: String, progress: (@Sendable (String) -> Void)?) throws -> NodeRuntimeSnapshot
    func uninstallPython(homePath: String, progress: (@Sendable (String) -> Void)?) throws -> NodeRuntimeSnapshot
    func setDefaultPython(version: String, homePath: String) throws -> NodeRuntimeSnapshot
}

struct LocalNodeRuntimeService: NodeRuntimeServicing {
    private let environmentService: NodeEnvironmentService

    init(
        configStore: ConfigStore = ConfigStore(),
        commandRunner: any ShellCommandRunning = ShellCommandRunner()
    ) {
        self.environmentService = NodeEnvironmentService(
            configStore: configStore,
            shellRunner: commandRunner
        )
    }

    func loadSnapshot(progress: (@Sendable (String) -> Void)? = nil) throws -> NodeRuntimeSnapshot {
        try environmentService.loadSnapshot(progress: progress)
    }

    func listAvailableNodeVersions(ltsOnly: Bool) throws -> [NodeDownloadCandidate] {
        try environmentService.listAvailableNodeVersions(ltsOnly: ltsOnly)
    }

    func listAvailableJavaVersions(ltsOnly: Bool) throws -> [JavaDownloadCandidate] {
        try environmentService.listAvailableJavaVersions(ltsOnly: ltsOnly)
    }

    func listAvailablePythonVersions(stableOnly: Bool) throws -> [PythonDownloadCandidate] {
        try environmentService.listAvailablePythonVersions(stableOnly: stableOnly)
    }

    func setDefaultNode(version: String, progress: (@Sendable (String) -> Void)? = nil) throws -> NodeRuntimeSnapshot {
        try environmentService.selectDefaultNode(version: version, progress: progress)
    }

    func installNode(version: String, progress: (@Sendable (String) -> Void)? = nil) throws -> NodeRuntimeSnapshot {
        try environmentService.installNode(version: version, progress: progress)
    }

    func uninstallNode(version: String, progress: (@Sendable (String) -> Void)? = nil) throws -> NodeRuntimeSnapshot {
        try environmentService.uninstallNode(version: version, progress: progress)
    }

    func installJava(featureVersion: Int, progress: (@Sendable (String) -> Void)? = nil) throws -> NodeRuntimeSnapshot {
        try environmentService.installJava(featureVersion: featureVersion, progress: progress)
    }

    func uninstallJava(homePath: String, progress: (@Sendable (String) -> Void)? = nil) throws -> NodeRuntimeSnapshot {
        try environmentService.uninstallJava(homePath: homePath, progress: progress)
    }

    func setDefaultJava(version: String, homePath: String) throws -> NodeRuntimeSnapshot {
        try environmentService.selectDefaultJava(version: version, homePath: homePath)
    }

    func installPython(version: String, progress: (@Sendable (String) -> Void)? = nil) throws -> NodeRuntimeSnapshot {
        try environmentService.installPython(version: version, progress: progress)
    }

    func uninstallPython(homePath: String, progress: (@Sendable (String) -> Void)? = nil) throws -> NodeRuntimeSnapshot {
        try environmentService.uninstallPython(homePath: homePath, progress: progress)
    }

    func setDefaultPython(version: String, homePath: String) throws -> NodeRuntimeSnapshot {
        try environmentService.selectDefaultPython(version: version, homePath: homePath)
    }
}
