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
    /// `cancellation` 一路传到 Core 的命令执行层：下载、解压、源码构建都能被杀掉，
    /// `nil` 表示这次操作不可取消。
    func installNode(
        version: String,
        cancellation: ShellCommandCancellation?,
        progress: (@Sendable (String) -> Void)?
    ) throws -> NodeRuntimeSnapshot
    func uninstallNode(
        version: String,
        cancellation: ShellCommandCancellation?,
        progress: (@Sendable (String) -> Void)?
    ) throws -> NodeRuntimeSnapshot
    func installJava(
        featureVersion: Int,
        cancellation: ShellCommandCancellation?,
        progress: (@Sendable (String) -> Void)?
    ) throws -> NodeRuntimeSnapshot
    func uninstallJava(
        homePath: String,
        cancellation: ShellCommandCancellation?,
        progress: (@Sendable (String) -> Void)?
    ) throws -> NodeRuntimeSnapshot
    func setDefaultJava(version: String, homePath: String) throws -> NodeRuntimeSnapshot
    func installPython(
        version: String,
        cancellation: ShellCommandCancellation?,
        progress: (@Sendable (String) -> Void)?
    ) throws -> NodeRuntimeSnapshot
    func uninstallPython(
        homePath: String,
        cancellation: ShellCommandCancellation?,
        progress: (@Sendable (String) -> Void)?
    ) throws -> NodeRuntimeSnapshot
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

    func installNode(
        version: String,
        cancellation: ShellCommandCancellation?,
        progress: (@Sendable (String) -> Void)? = nil
    ) throws -> NodeRuntimeSnapshot {
        try environmentService.installNode(
            version: version,
            cancellation: cancellation,
            progress: progress
        )
    }

    func uninstallNode(
        version: String,
        cancellation: ShellCommandCancellation?,
        progress: (@Sendable (String) -> Void)? = nil
    ) throws -> NodeRuntimeSnapshot {
        try throwIfCancelled(cancellation)
        return try environmentService.uninstallNode(version: version, progress: progress)
    }

    func installJava(
        featureVersion: Int,
        cancellation: ShellCommandCancellation?,
        progress: (@Sendable (String) -> Void)? = nil
    ) throws -> NodeRuntimeSnapshot {
        try environmentService.installJava(
            featureVersion: featureVersion,
            cancellation: cancellation,
            progress: progress
        )
    }

    func uninstallJava(
        homePath: String,
        cancellation: ShellCommandCancellation?,
        progress: (@Sendable (String) -> Void)? = nil
    ) throws -> NodeRuntimeSnapshot {
        try throwIfCancelled(cancellation)
        return try environmentService.uninstallJava(homePath: homePath, progress: progress)
    }

    func setDefaultJava(version: String, homePath: String) throws -> NodeRuntimeSnapshot {
        try environmentService.selectDefaultJava(version: version, homePath: homePath)
    }

    func installPython(
        version: String,
        cancellation: ShellCommandCancellation?,
        progress: (@Sendable (String) -> Void)? = nil
    ) throws -> NodeRuntimeSnapshot {
        try environmentService.installPython(
            version: version,
            cancellation: cancellation,
            progress: progress
        )
    }

    func uninstallPython(
        homePath: String,
        cancellation: ShellCommandCancellation?,
        progress: (@Sendable (String) -> Void)? = nil
    ) throws -> NodeRuntimeSnapshot {
        try throwIfCancelled(cancellation)
        return try environmentService.uninstallPython(homePath: homePath, progress: progress)
    }

    func setDefaultPython(version: String, homePath: String) throws -> NodeRuntimeSnapshot {
        try environmentService.selectDefaultPython(version: version, homePath: homePath)
    }

    /// 取消已经在调用前发生时就别再启动卸载。
    ///
    /// 安装路径（`installNode` / `installJava` / `installPython`）已经把令牌一路透传到
    /// Core 的命令执行层；Core 的卸载入口还没有 `cancellation:` 参数，所以卸载目前只能
    /// 覆盖「开始前已被取消」。等 Core 的卸载也接上令牌，这里换成透传即可。
    private func throwIfCancelled(_ cancellation: ShellCommandCancellation?) throws {
        if cancellation?.isCancelled == true {
            throw CancellationError()
        }
    }
}
