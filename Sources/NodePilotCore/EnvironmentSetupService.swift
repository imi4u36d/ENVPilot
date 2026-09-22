import Foundation

public enum EnvironmentSetupCheckKind: String, CaseIterable, Identifiable, Sendable {
    case runtime
    case commandLineTools
    case shellIntegration
    case aiTools

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .runtime:
            return "Node 运行时"
        case .commandLineTools:
            return "命令行工具"
        case .shellIntegration:
            return "终端自动激活"
        case .aiTools:
            return "AI 编码工具"
        }
    }
}

public enum EnvironmentSetupCheckStatus: Equatable, Sendable {
    case loading
    case ok
    case needsRepair
    case optional
    case failed
}

public struct EnvironmentSetupCheckResult: Identifiable, Equatable, Sendable {
    public let kind: EnvironmentSetupCheckKind
    public let status: EnvironmentSetupCheckStatus
    public let detail: String
    public let repairHint: String?

    public init(
        kind: EnvironmentSetupCheckKind,
        status: EnvironmentSetupCheckStatus,
        detail: String,
        repairHint: String? = nil
    ) {
        self.kind = kind
        self.status = status
        self.detail = detail
        self.repairHint = repairHint
    }

    public var id: String { kind.rawValue }

    public static func pending(_ kind: EnvironmentSetupCheckKind) -> EnvironmentSetupCheckResult {
        EnvironmentSetupCheckResult(
            kind: kind,
            status: .loading,
            detail: "等待检查"
        )
    }
}

public struct EnvironmentSetupReport: Equatable, Sendable {
    public let checks: [EnvironmentSetupCheckResult]
    public let message: String?

    public init(checks: [EnvironmentSetupCheckResult], message: String? = nil) {
        self.checks = checks
        self.message = message
    }

    public var needsRepair: Bool {
        checks.contains {
            $0.status == .needsRepair || $0.status == .failed
        }
    }
}

public protocol EnvironmentNodeRuntimeProviding: Sendable {
    func loadSnapshot(progress: (@Sendable (String) -> Void)?) throws -> NodeRuntimeSnapshot
    func listAvailableNodeVersions(ltsOnly: Bool) throws -> [NodeDownloadCandidate]
    func selectDefaultNode(version: String, progress: (@Sendable (String) -> Void)?) throws -> NodeRuntimeSnapshot
    func installNode(version: String, progress: (@Sendable (String) -> Void)?) throws -> NodeRuntimeSnapshot
}

extension NodeEnvironmentService: EnvironmentNodeRuntimeProviding {}

public struct EnvironmentSetupService: @unchecked Sendable {
    private static let shellStartMarker = "# >>> ENVPilot >>>"
    private static let shellEndMarker = "# <<< ENVPilot <<<"

    private let environment: [String: String]
    private let shellIntegration: ShellIntegrationService
    private let runtimeProvider: any EnvironmentNodeRuntimeProviding
    private let fileManager: FileManager
    private let homeURL: URL
    private let helperSourceURL: URL?
    /// 同一个服务实例只给 shell 配置留一次备份：repair 可能被连点多次，
    /// 没必要每秒都在用户 home 下留一份 `.zshrc.envpilot-backup-*`。
    private let shellConfigBackupGate = ShellConfigBackupGate()

    public init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        shellIntegration: ShellIntegrationService = ShellIntegrationService(),
        runtimeProvider: any EnvironmentNodeRuntimeProviding = NodeEnvironmentService(),
        fileManager: FileManager = .default,
        helperSourceURL: URL? = EnvironmentSetupService.defaultHelperSourceURL
    ) {
        self.environment = environment
        self.shellIntegration = shellIntegration
        self.runtimeProvider = runtimeProvider
        self.fileManager = fileManager

        let home = environment["HOME"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.homeURL = URL(
            fileURLWithPath: home?.isEmpty == false ? home! : NSHomeDirectory(),
            isDirectory: true
        )
        self.helperSourceURL = helperSourceURL
    }

    public static var defaultHelperSourceURL: URL? {
        let url = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Resources/bin/envpilot-helper")
        return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
    }

    public func check(aiStatuses: [AIEnvironmentStatus] = []) -> EnvironmentSetupReport {
        EnvironmentSetupReport(checks: [
            checkRuntime(),
            checkCommandLineTools(),
            checkShellIntegration(),
            checkAITools(aiStatuses: aiStatuses),
        ])
    }

    public func repair(
        aiStatuses: [AIEnvironmentStatus] = [],
        progress: (@Sendable (String) -> Void)? = nil
    ) -> EnvironmentSetupReport {
        var failures: [String] = []

        progress?("正在安装命令行工具…")
        do {
            try installCommandLineTools()
        } catch {
            failures.append("命令行工具：\(error.localizedDescription)")
        }

        progress?("正在更新终端自动激活…")
        do {
            try installShellIntegration()
        } catch {
            failures.append("终端自动激活：\(error.localizedDescription)")
        }

        progress?("正在检查 Node 运行时…")
        do {
            try repairRuntime(progress: progress)
        } catch {
            failures.append("Node 运行时：\(error.localizedDescription)")
        }

        progress?("重新检查环境…")
        let report = check(aiStatuses: aiStatuses)
        let message: String?
        if failures.isEmpty {
            message = report.needsRepair
                ? "自动配置已完成，但仍有项目需要处理。"
                : "环境配置完成。"
        } else {
            message = "部分步骤失败：\(failures.joined(separator: "；"))"
        }
        return EnvironmentSetupReport(checks: report.checks, message: message)
    }

    static func updatedZshrc(_ contents: String, snippet: String) -> String {
        var updated = contents
        while let start = updated.range(of: shellStartMarker),
              let end = updated.range(of: shellEndMarker, range: start.upperBound..<updated.endIndex) {
            updated.removeSubrange(start.lowerBound..<end.upperBound)
        }

        updated = updated.trimmingCharacters(in: .newlines)
        if !updated.isEmpty {
            updated += "\n\n"
        }
        updated += snippet.trimmingCharacters(in: .newlines)
        updated += "\n"
        return updated
    }

    private var helperURL: URL {
        homeURL
            .appendingPathComponent(".local/bin", isDirectory: true)
            .appendingPathComponent("envpilot-helper")
    }

    private var epURL: URL {
        homeURL
            .appendingPathComponent(".local/bin", isDirectory: true)
            .appendingPathComponent("ep")
    }

    private var zshrcURL: URL {
        homeURL.appendingPathComponent(".zshrc")
    }

    private func checkRuntime() -> EnvironmentSetupCheckResult {
        do {
            let snapshot = try runtimeProvider.loadSnapshot(progress: nil)
            guard !snapshot.installations.isEmpty else {
                return EnvironmentSetupCheckResult(
                    kind: .runtime,
                    status: .needsRepair,
                    detail: "未安装 ENVPilot 管理的 Node",
                    repairHint: "自动安装最新 LTS Node"
                )
            }

            if isRuntimeSelected(snapshot), let selectedVersion = snapshot.settings.selectedVersion {
                return EnvironmentSetupCheckResult(
                    kind: .runtime,
                    status: .ok,
                    detail: "已选择 Node \(selectedVersion)"
                )
            }

            return EnvironmentSetupCheckResult(
                kind: .runtime,
                status: .needsRepair,
                detail: "已安装 Node，但还没有设为默认版本",
                repairHint: "自动选择最新已安装版本"
            )
        } catch {
            return EnvironmentSetupCheckResult(
                kind: .runtime,
                status: .failed,
                detail: "读取 Node 运行时失败：\(error.localizedDescription)",
                repairHint: "重新检查或手动打开运行时页面"
            )
        }
    }

    private func checkCommandLineTools() -> EnvironmentSetupCheckResult {
        let helperReady = isExecutable(helperURL.path)
        let epReady = resolvesToHelper(epURL)
        switch (helperReady, epReady) {
        case (true, true):
            return EnvironmentSetupCheckResult(
                kind: .commandLineTools,
                status: .ok,
                detail: "envpilot-helper 与 ep 已就绪"
            )
        case (false, _):
            return EnvironmentSetupCheckResult(
                kind: .commandLineTools,
                status: .needsRepair,
                detail: "缺少 ~/.local/bin/envpilot-helper",
                repairHint: "从应用包安装命令行工具"
            )
        case (true, false):
            return EnvironmentSetupCheckResult(
                kind: .commandLineTools,
                status: .needsRepair,
                detail: "缺少 ep 快捷命令或它没有指向 envpilot-helper",
                repairHint: "重新创建 ep 快捷命令"
            )
        }
    }

    private func checkShellIntegration() -> EnvironmentSetupCheckResult {
        let expectedSnippet = shellIntegration
            .renderInstallSnippet(helperPath: helperURL.path)
            .trimmingCharacters(in: .newlines)
        let contents = (try? String(contentsOf: zshrcURL, encoding: .utf8)) ?? ""
        if contents.contains(expectedSnippet) {
            return EnvironmentSetupCheckResult(
                kind: .shellIntegration,
                status: .ok,
                detail: "~/.zshrc 已安装 ENVPilot 自动激活片段"
            )
        }

        return EnvironmentSetupCheckResult(
            kind: .shellIntegration,
            status: .needsRepair,
            detail: contents.isEmpty ? "尚未配置 ~/.zshrc" : "~/.zshrc 中的 ENVPilot 片段缺失或需要更新",
            repairHint: "写入或更新标记块，不改动其他 shell 配置"
        )
    }

    private func checkAITools(aiStatuses: [AIEnvironmentStatus]) -> EnvironmentSetupCheckResult {
        let installed = aiStatuses.filter(\.isInstalled)
        guard !installed.isEmpty else {
            return EnvironmentSetupCheckResult(
                kind: .aiTools,
                status: .optional,
                detail: "暂未检测到 AI CLI，可稍后在「AI 环境」中安装",
                repairHint: nil
            )
        }

        let names = installed.map(\.kind.displayName).joined(separator: "、")
        return EnvironmentSetupCheckResult(
            kind: .aiTools,
            status: .ok,
            detail: "已检测到 \(names)"
        )
    }

    private func installCommandLineTools() throws {
        let directory = helperURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let helperSourceURL else {
            throw EnvironmentSetupError.helperUnavailable
        }
        try installHelper(from: helperSourceURL)

        if fileManager.fileExists(atPath: epURL.path) {
            try fileManager.removeItem(at: epURL)
        }
        try fileManager.createSymbolicLink(atPath: epURL.path, withDestinationPath: "envpilot-helper")
    }

    /// 先把 helper 拷到同目录的临时文件，最后一步整体替换。
    ///
    /// 以前是 `removeItem(helperURL)` 再 `copyItem(...)`：拷贝一旦失败（磁盘满、来源
    /// 被删），用户就既没有旧 helper 也没有新的，`ep` 直接不可用。同目录保证
    /// `replaceItemAt` 是同一卷内的原子替换，失败时旧文件仍在。
    private func installHelper(from source: URL) throws {
        let directory = helperURL.deletingLastPathComponent()
        let temporaryURL = directory.appendingPathComponent(
            "envpilot-helper.tmp-\(UUID().uuidString)"
        )
        defer { try? fileManager.removeItem(at: temporaryURL) }

        try fileManager.copyItem(at: source, to: temporaryURL)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: temporaryURL.path)

        if fileManager.fileExists(atPath: helperURL.path) {
            _ = try fileManager.replaceItemAt(helperURL, withItemAt: temporaryURL)
        } else {
            try fileManager.moveItem(at: temporaryURL, to: helperURL)
        }
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helperURL.path)
    }

    private func installShellIntegration() throws {
        let existing: String
        if fileManager.fileExists(atPath: zshrcURL.path) {
            existing = (try? String(contentsOf: zshrcURL, encoding: .utf8)) ?? ""
        } else {
            existing = ""
        }
        let snippet = shellIntegration.renderInstallSnippet(helperPath: helperURL.path)
        let updated = Self.updatedZshrc(existing, snippet: snippet)

        // 内容没变就完全不写：既不会丢掉用户在此期间对 ~/.zshrc 的并发编辑，
        // 也不会用原子替换把文件模式/属主重置成默认值。
        guard updated != existing else {
            return
        }

        let originalAttributes = try? fileManager.attributesOfItem(atPath: zshrcURL.path)
        if originalAttributes != nil, shellConfigBackupGate.claim() {
            try backupShellConfig()
        }

        try Data(updated.utf8).write(to: zshrcURL, options: .atomic)
        if let originalAttributes {
            restoreFileAttributes(originalAttributes, at: zshrcURL)
        }
    }

    /// 整体重写之前先留一份带时间戳的副本，用户丢了配置还能自己找回来。
    private func backupShellConfig() throws {
        let stamp = Self.backupTimestampFormatter.string(from: Date())
        let backupURL = zshrcURL.deletingLastPathComponent()
            .appendingPathComponent("\(zshrcURL.lastPathComponent).envpilot-backup-\(stamp)")
        // 同一秒内重复备份会撞名，先删旧的，保证这一次的备份一定写得进去。
        if fileManager.fileExists(atPath: backupURL.path) {
            try fileManager.removeItem(at: backupURL)
        }
        try fileManager.copyItem(at: zshrcURL, to: backupURL)
    }

    /// `.atomic` 写盘会替换整个文件，权限/属主不会自动继承，这里显式写回。
    private func restoreFileAttributes(_ attributes: [FileAttributeKey: Any], at url: URL) {
        var restored: [FileAttributeKey: Any] = [:]
        for key in [FileAttributeKey.posixPermissions, .ownerAccountID, .groupOwnerAccountID] {
            if let value = attributes[key] {
                restored[key] = value
            }
        }
        guard !restored.isEmpty else {
            return
        }
        try? fileManager.setAttributes(restored, ofItemAtPath: url.path)
    }

    private static let backupTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()

    private func repairRuntime(progress: (@Sendable (String) -> Void)?) throws {
        var snapshot = try runtimeProvider.loadSnapshot(progress: progress)
        if snapshot.installations.isEmpty {
            guard let candidate = try runtimeProvider.listAvailableNodeVersions(ltsOnly: true).first else {
                throw EnvironmentSetupError.nodeCandidateUnavailable
            }
            snapshot = try runtimeProvider.installNode(version: candidate.version, progress: progress)
        }

        if !isRuntimeSelected(snapshot) {
            guard let latest = newestInstallation(in: snapshot.installations) else {
                throw EnvironmentSetupError.nodeCandidateUnavailable
            }
            _ = try runtimeProvider.selectDefaultNode(version: latest.version, progress: progress)
        }
    }

    private func isRuntimeSelected(_ snapshot: NodeRuntimeSnapshot) -> Bool {
        guard let selectedVersion = snapshot.settings.selectedVersion,
              let installation = snapshot.installations.first(where: { $0.version == selectedVersion }) else {
            return false
        }
        if let selectedPath = snapshot.settings.selectedNodePath,
           !selectedPath.isEmpty,
           selectedPath != installation.installPath {
            return false
        }
        return true
    }

    private func newestInstallation(in installations: [NodeInstallation]) -> NodeInstallation? {
        installations.sorted { lhs, rhs in
            let left = AppVersion(lhs.version)
            let right = AppVersion(rhs.version)
            switch (left, right) {
            case let (left?, right?):
                return left > right
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            case (.none, .none):
                return lhs.version > rhs.version
            }
        }.first
    }

    private func isExecutable(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory),
              !isDirectory.boolValue else {
            return false
        }
        return fileManager.isExecutableFile(atPath: path)
    }

    private func resolvesToHelper(_ url: URL) -> Bool {
        guard fileManager.fileExists(atPath: url.path) else {
            return false
        }
        return url.resolvingSymlinksInPath().standardizedFileURL.path
            == helperURL.resolvingSymlinksInPath().standardizedFileURL.path
    }
}

public enum EnvironmentSetupError: LocalizedError {
    case helperUnavailable
    case nodeCandidateUnavailable

    public var errorDescription: String? {
        switch self {
        case .helperUnavailable:
            return "应用包中没有可用的 envpilot-helper。"
        case .nodeCandidateUnavailable:
            return "没有找到可安装的 Node LTS 版本。"
        }
    }
}

/// 「这次实例是否已经备份过」的一次性开关。`EnvironmentSetupService` 是
/// `@unchecked Sendable`，repair 可能被并发触发，所以用锁保护。
private final class ShellConfigBackupGate: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    /// 返回 true 表示本次调用应该执行备份；同一个实例只有第一次为 true。
    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !claimed else {
            return false
        }
        claimed = true
        return true
    }
}
