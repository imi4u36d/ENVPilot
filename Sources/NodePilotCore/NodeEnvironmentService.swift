import Foundation

public protocol AppSettingsStoring: Sendable {
    func load() throws -> AppSettings
    func save(_ settings: AppSettings) throws
}

extension ConfigStore: AppSettingsStoring {}

public final class NodeEnvironmentService: Sendable {
    private let configStore: any AppSettingsStoring
    private let detector: any NodeInstallationDetecting
    private let javaDetector: any JavaRuntimeDetecting
    private let componentInstaller: any RuntimeComponentInstalling
    private let shellRunner: any ShellCommandRunning

    public init(
        configStore: any AppSettingsStoring = ConfigStore(),
        detector: (any NodeInstallationDetecting)? = nil,
        javaDetector: (any JavaRuntimeDetecting)? = nil,
        componentInstaller: (any RuntimeComponentInstalling)? = nil,
        shellRunner: any ShellCommandRunning = ShellCommandRunner()
    ) {
        self.configStore = configStore
        self.shellRunner = shellRunner
        self.detector = detector ?? NodeInstallationDetector(shellRunner: shellRunner)
        self.javaDetector = javaDetector ?? JavaRuntimeDetector(shellRunner: shellRunner)
        self.componentInstaller = componentInstaller ?? RuntimeComponentInstaller(shellRunner: shellRunner)
    }

    public func loadSnapshot() throws -> NodeRuntimeSnapshot {
        try loadSnapshot(progress: nil)
    }

    public func loadSnapshot(progress: (@Sendable (String) -> Void)?) throws -> NodeRuntimeSnapshot {
        // Best-effort only: the app should still load and expose runtime state
        // even if automatic Homebrew/NVM installation fails.
        try? ensureNVMInstalledIfPossible(progress: progress)

        let settings = try configStore.load()
        let installations = mergeDefaultSelection(
            installations: detector.detectInstallations(),
            selectedVersion: settings.selectedVersion
        )
        let activeVersion = detector.detectActiveVersion()
        let activeNodePath = detector.detectActiveNodePath()
        let javaInstallations = mergeDefaultJavaSelection(
            installations: javaDetector.detectInstallations(),
            selectedJavaHome: settings.selectedJavaHome
        )
        let activeJavaVersion = javaDetector.detectActiveVersion()
        let activeJavaHome = javaDetector.detectActiveJavaHome()
        let sdkmanStatus = SDKMANRuntimeStatus(
            isInstalled: componentInstaller.isSDKMANInstalled(),
            canInstall: componentInstaller.canInstallSDKMAN(),
            hasManagedJavaInstallations: javaInstallations.contains {
                JavaRuntimeDetector.sdkmanJavaIdentifier(fromHomePath: $0.homePath) != nil
            }
        )

        return NodeRuntimeSnapshot(
            installations: installations,
            activeVersion: activeVersion,
            activeNodePath: activeNodePath,
            javaInstallations: javaInstallations,
            activeJavaVersion: activeJavaVersion,
            activeJavaHome: activeJavaHome,
            sdkmanStatus: sdkmanStatus,
            settings: settings
        )
    }

    @discardableResult
    public func selectDefaultNode(version: String) throws -> NodeRuntimeSnapshot {
        try selectDefaultNode(version: version, progress: nil)
    }

    @discardableResult
    public func selectDefaultNode(version: String, progress: (@Sendable (String) -> Void)?) throws -> NodeRuntimeSnapshot {
        try ensureNVMInstalled(progress: progress)

        let normalizedVersion = try normalizeOrThrow(version)
        let installations = detector.detectInstallations()
        guard installations.contains(where: { $0.version == normalizedVersion }) else {
            throw NodeEnvironmentServiceError.nodeVersionNotInstalled(normalizedVersion)
        }

        try runNVMCommand("nvm alias default \(Self.shellQuoted(normalizedVersion))")

        var settings = try configStore.load()
        settings.selectedVersion = normalizedVersion
        try configStore.save(settings)

        return try loadSnapshot(progress: progress)
    }

    @discardableResult
    public func installNode(version: String) throws -> NodeRuntimeSnapshot {
        try installNode(version: version, progress: nil)
    }

    @discardableResult
    public func installNode(version: String, progress: (@Sendable (String) -> Void)?) throws -> NodeRuntimeSnapshot {
        try ensureNVMInstalled(progress: progress)

        let requestedVersion = try normalizeInstallSpecOrThrow(version)
        let installCommand = """
        nvm install \(Self.shellQuoted(requestedVersion))
        nvm version \(Self.shellQuoted(requestedVersion))
        """

        let result: ShellCommandResult
        do {
            progress?("正在通过 NVM 安装 Node \(requestedVersion)...")
            result = try runNVMCommand(installCommand)
        } catch NodeEnvironmentServiceError.nvmCommandFailed(let message) where shouldRetryInstallWithRosetta(message: message) {
            do {
                progress?("正在通过 Rosetta/x64 安装兼容版本 Node \(requestedVersion)...")
                result = try runNVMCommand(installCommand, useRosetta: true)
            } catch NodeEnvironmentServiceError.nvmCommandFailed(let retryMessage) {
                throw NodeEnvironmentServiceError.nvmCommandFailed(
                    message: Self.legacyNodeInstallFailureMessage(
                        requestedVersion: requestedVersion,
                        fallbackMessage: retryMessage
                    )
                )
            }
        } catch NodeEnvironmentServiceError.nvmCommandFailed(let message) {
            throw NodeEnvironmentServiceError.nvmCommandFailed(
                message: Self.userFacingInstallFailureMessage(for: requestedVersion, rawMessage: message)
            )
        }
        let resolvedVersion = Self.extractInstalledVersion(from: result) ?? NodeInstallationDetector.normalizeVersion(requestedVersion)

        var settings = try configStore.load()
        settings.selectedVersion = resolvedVersion
        try configStore.save(settings)

        return try loadSnapshot(progress: progress)
    }

    @discardableResult
    public func uninstallNode(version: String) throws -> NodeRuntimeSnapshot {
        try uninstallNode(version: version, progress: nil)
    }

    @discardableResult
    public func uninstallNode(version: String, progress: (@Sendable (String) -> Void)?) throws -> NodeRuntimeSnapshot {
        try ensureNVMInstalled(progress: progress)

        let normalizedVersion = try normalizeOrThrow(version)
        let installations = detector.detectInstallations()
        guard installations.contains(where: { $0.version == normalizedVersion }) else {
            throw NodeEnvironmentServiceError.nodeVersionNotInstalled(normalizedVersion)
        }

        try runNVMCommand("nvm uninstall \(Self.shellQuoted(normalizedVersion))")

        var settings = try configStore.load()
        if settings.selectedVersion == normalizedVersion {
            settings.selectedVersion = nil
        }
        try configStore.save(settings)

        return try loadSnapshot(progress: progress)
    }

    @discardableResult
    public func updateSelectedProfile(_ profileID: UUID?) throws -> NodeRuntimeSnapshot {
        var settings = try configStore.load()
        settings.selectedProfileID = profileID
        try configStore.save(settings)
        return try loadSnapshot()
    }

    @discardableResult
    public func selectDefaultJava(version: String, homePath: String) throws -> NodeRuntimeSnapshot {
        let installations = javaDetector.detectInstallations()
        guard installations.contains(where: { $0.homePath == homePath }) else {
            throw NodeEnvironmentServiceError.javaHomeNotInstalled(homePath)
        }

        if let sdkmanIdentifier = JavaRuntimeDetector.sdkmanJavaIdentifier(fromHomePath: homePath) {
            do {
                try componentInstaller.setSDKMANDefaultJava(identifier: sdkmanIdentifier)
            } catch {
                throw NodeEnvironmentServiceError.sdkmanCommandFailed(message: error.localizedDescription)
            }
        }

        var settings = try configStore.load()
        settings.selectedJavaVersion = version
        settings.selectedJavaHome = homePath
        try configStore.save(settings)
        return try loadSnapshot()
    }

    @discardableResult
    public func installSDKMAN() throws -> NodeRuntimeSnapshot {
        try installSDKMAN(progress: nil)
    }

    @discardableResult
    public func installSDKMAN(progress: (@Sendable (String) -> Void)?) throws -> NodeRuntimeSnapshot {
        if componentInstaller.isSDKMANInstalled() {
            return try loadSnapshot(progress: progress)
        }
        guard componentInstaller.canInstallSDKMAN() else {
            throw NodeEnvironmentServiceError.sdkmanUnavailable
        }
        do {
            progress?("正在安装 SDKMAN...")
            try componentInstaller.installSDKMAN()
        } catch {
            throw NodeEnvironmentServiceError.sdkmanCommandFailed(message: error.localizedDescription)
        }
        return try loadSnapshot(progress: progress)
    }

    @discardableResult
    public func installJavaWithSDKMAN(identifier: String) throws -> NodeRuntimeSnapshot {
        try installJavaWithSDKMAN(identifier: identifier, progress: nil)
    }

    @discardableResult
    public func installJavaWithSDKMAN(
        identifier: String,
        progress: (@Sendable (String) -> Void)?
    ) throws -> NodeRuntimeSnapshot {
        let normalizedIdentifier = try normalizeJavaIdentifierOrThrow(identifier)

        if !componentInstaller.isSDKMANInstalled() {
            _ = try installSDKMAN(progress: progress)
        }

        do {
            progress?("正在通过 SDKMAN 安装 JDK \(normalizedIdentifier)...")
            try componentInstaller.installJavaWithSDKMAN(identifier: normalizedIdentifier)
        } catch {
            throw NodeEnvironmentServiceError.sdkmanCommandFailed(message: error.localizedDescription)
        }

        return try loadSnapshot(progress: progress)
    }

    public func listAvailableJavaCandidatesWithSDKMAN() throws -> [SDKMANJavaCandidate] {
        guard componentInstaller.isSDKMANInstalled() else {
            throw NodeEnvironmentServiceError.sdkmanUnavailable
        }

        do {
            let installedIdentifiers = Set(
                javaDetector.detectInstallations().compactMap {
                    JavaRuntimeDetector.sdkmanJavaIdentifier(fromHomePath: $0.homePath)
                }
            )
            return try componentInstaller.listAvailableJavaCandidatesWithSDKMAN().map { candidate in
                var updated = candidate
                updated.isInstalled = installedIdentifiers.contains(candidate.identifier)
                return updated
            }
        } catch {
            throw NodeEnvironmentServiceError.sdkmanCommandFailed(message: error.localizedDescription)
        }
    }

    @discardableResult
    public func uninstallJava(
        homePath: String,
        progress: (@Sendable (String) -> Void)?
    ) throws -> NodeRuntimeSnapshot {
        let normalizedHomePath = homePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedHomePath.isEmpty else {
            throw NodeEnvironmentServiceError.javaHomeNotInstalled(homePath)
        }

        let installations = javaDetector.detectInstallations()
        guard installations.contains(where: { $0.homePath == normalizedHomePath }) else {
            throw NodeEnvironmentServiceError.javaHomeNotInstalled(normalizedHomePath)
        }

        if let sdkmanIdentifier = JavaRuntimeDetector.sdkmanJavaIdentifier(fromHomePath: normalizedHomePath) {
            return try uninstallJavaWithSDKMAN(identifier: sdkmanIdentifier, progress: progress)
        }

        progress?("正在卸载 JDK \(normalizedHomePath)...")
        do {
            let removalTarget = try removalTargetForNonSDKMANJava(homePath: normalizedHomePath)
            let fileManager = FileManager.default
            guard fileManager.fileExists(atPath: removalTarget.path) else {
                throw NodeEnvironmentServiceError.javaHomeNotInstalled(normalizedHomePath)
            }
            do {
                try fileManager.removeItem(at: removalTarget)
            } catch {
                guard shouldUsePrivilegedJavaRemoval(path: removalTarget.path) else {
                    throw error
                }
                progress?("检测到系统目录 JDK，正在请求管理员权限卸载...")
                try runPrivilegedJavaUninstall(path: removalTarget.path)
            }
        } catch let error as NodeEnvironmentServiceError {
            throw error
        } catch {
            throw NodeEnvironmentServiceError.javaUninstallFailed(
                path: normalizedHomePath,
                message: error.localizedDescription
            )
        }

        var settings = try configStore.load()
        if settings.selectedJavaHome == normalizedHomePath {
            settings.selectedJavaHome = nil
            settings.selectedJavaVersion = nil
            try configStore.save(settings)
        }

        return try loadSnapshot(progress: progress)
    }

    @discardableResult
    public func uninstallJavaWithSDKMAN(
        identifier: String,
        progress: (@Sendable (String) -> Void)?
    ) throws -> NodeRuntimeSnapshot {
        let normalizedIdentifier = try normalizeJavaIdentifierOrThrow(identifier)
        guard componentInstaller.isSDKMANInstalled() else {
            throw NodeEnvironmentServiceError.sdkmanUnavailable
        }

        do {
            progress?("正在通过 SDKMAN 卸载 JDK \(normalizedIdentifier)...")
            try componentInstaller.uninstallJavaWithSDKMAN(identifier: normalizedIdentifier)
        } catch {
            let errorMessage = error.localizedDescription
            if shouldRetrySDKMANUninstallBySwitchingDefault(message: errorMessage),
               try retrySDKMANUninstallAfterSwitchingDefault(
                    identifier: normalizedIdentifier,
                    progress: progress
               ) {
                // Uninstall succeeded after switching SDKMAN default Java.
            } else if shouldForceSDKMANUninstall(message: errorMessage) {
                progress?("SDKMAN 报告目标为当前版本，按提示尝试 --force 卸载 \(normalizedIdentifier)...")
                try runSDKMANForceUninstall(identifier: normalizedIdentifier)
            } else {
                throw NodeEnvironmentServiceError.sdkmanCommandFailed(message: errorMessage)
            }
        }

        var settings = try configStore.load()
        if let selectedJavaHome = settings.selectedJavaHome,
           JavaRuntimeDetector.sdkmanJavaIdentifier(fromHomePath: selectedJavaHome) == normalizedIdentifier {
            settings.selectedJavaHome = nil
            settings.selectedJavaVersion = nil
            try configStore.save(settings)
        }

        return try loadSnapshot(progress: progress)
    }

    func ensureNVMInstalledIfPossible(progress: (@Sendable (String) -> Void)?) throws {
        if !componentInstaller.isHomebrewInstalled() {
            progress?("正在安装 Homebrew...")
            try componentInstaller.installHomebrew()
        }

        guard !detector.isNVMInstalled(), componentInstaller.canInstallNVM() else {
            return
        }
        progress?("正在安装 NVM...")
        try componentInstaller.installNVM()
    }

    func ensureNVMInstalled(progress: (@Sendable (String) -> Void)?) throws {
        try ensureNVMInstalledIfPossible(progress: progress)
        guard detector.isNVMInstalled() else {
            throw NodeEnvironmentServiceError.nvmUnavailable
        }
    }

    @discardableResult
    func runNVMCommand(_ command: String, useRosetta: Bool = false) throws -> ShellCommandResult {
        let bootstrapCommand = NodeInstallationDetector.nvmBootstrap(command)
        let result: ShellCommandResult
        if useRosetta {
            result = try shellRunner.run(
                "/usr/bin/arch",
                arguments: ["-x86_64", "/bin/zsh", "-lc", bootstrapCommand],
                environment: ProcessInfo.processInfo.environment
            )
        } else {
            result = try shellRunner.runShell(
                bootstrapCommand,
                environment: ProcessInfo.processInfo.environment
            )
        }
        guard result.succeeded else {
            throw NodeEnvironmentServiceError.nvmCommandFailed(message: Self.preferErrorOutput(result))
        }
        return result
    }

    func normalizeOrThrow(_ version: String) throws -> String {
        if let normalized = NodeInstallationDetector.normalizeVersion(version) {
            return normalized
        }
        throw NodeEnvironmentServiceError.invalidVersion(version)
    }

    func normalizeInstallSpecOrThrow(_ version: String) throws -> String {
        let trimmed = version.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw NodeEnvironmentServiceError.invalidVersion(version)
        }

        let compact = trimmed.replacingOccurrences(of: " ", with: "")
        guard !compact.isEmpty else {
            throw NodeEnvironmentServiceError.invalidVersion(version)
        }

        if let normalized = NodeInstallationDetector.normalizeVersion(compact) {
            return normalized
        }

        if compact.hasPrefix("v"), compact.count > 1 {
            return String(compact.dropFirst())
        }

        return compact
    }

    func normalizeJavaIdentifierOrThrow(_ identifier: String) throws -> String {
        let normalized = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            throw NodeEnvironmentServiceError.invalidJavaIdentifier(identifier)
        }
        return normalized
    }

    func mergeDefaultSelection(
        installations: [NodeInstallation],
        selectedVersion: String?
    ) -> [NodeInstallation] {
        let normalizedSelection = NodeInstallationDetector.normalizeVersion(selectedVersion)

        return installations.map { installation in
            let isSelected = installation.version == normalizedSelection
            if isSelected && !installation.isDefault {
                return NodeInstallation(
                    version: installation.version,
                    installPath: installation.installPath,
                    executablePath: installation.executablePath,
                    isDefault: true
                )
            }
            return installation
        }
    }

    func mergeDefaultJavaSelection(
        installations: [JavaInstallation],
        selectedJavaHome: String?
    ) -> [JavaInstallation] {
        guard let selectedJavaHome, !selectedJavaHome.isEmpty else {
            return installations
        }
        return installations.map {
            JavaInstallation(version: $0.version, homePath: $0.homePath, isDefault: $0.homePath == selectedJavaHome)
        }
    }

    func shouldRetryInstallWithRosetta(message: String) -> Bool {
        #if arch(arm64)
        let normalized = message.lowercased()
        return normalized.contains("darwin-arm64")
            && (normalized.contains("404") || normalized.contains("binary download failed"))
        #else
        false
        #endif
    }

    func resolveSelectedJavaAfterSDKMANInstall(
        identifier: String,
        snapshot: NodeRuntimeSnapshot
    ) -> JavaInstallation? {
        if let activeHome = snapshot.activeJavaHome,
           let active = snapshot.javaInstallations.first(where: { $0.homePath == activeHome }) {
            return active
        }

        return snapshot.javaInstallations.first {
            JavaRuntimeDetector.sdkmanJavaIdentifier(fromHomePath: $0.homePath) == identifier
        }
    }

    func shouldRetrySDKMANUninstallBySwitchingDefault(message: String) -> Bool {
        let normalized = message.lowercased()
        return normalized.contains("in use")
            || normalized.contains("currently in use")
            || normalized.contains("is current")
            || normalized.contains("is default")
            || normalized.contains("cannot uninstall")
    }

    func shouldForceSDKMANUninstall(message: String) -> Bool {
        let normalized = message.lowercased()
        return normalized.contains("override with --force")
            || normalized.contains("should not be removed")
            || normalized.contains("current version")
            || normalized.contains("is the current")
            || normalized.contains("is current")
    }

    func retrySDKMANUninstallAfterSwitchingDefault(
        identifier: String,
        progress: (@Sendable (String) -> Void)?
    ) throws -> Bool {
        let fallbackIdentifier = javaDetector.detectInstallations()
            .compactMap { JavaRuntimeDetector.sdkmanJavaIdentifier(fromHomePath: $0.homePath) }
            .first { $0 != identifier }

        guard let fallbackIdentifier else {
            return false
        }

        do {
            progress?("检测到目标版本可能为 SDKMAN 当前默认，尝试切换默认到 \(fallbackIdentifier)...")
            try componentInstaller.setSDKMANDefaultJava(identifier: fallbackIdentifier)
            progress?("正在重试卸载 SDKMAN JDK \(identifier)...")
            try componentInstaller.uninstallJavaWithSDKMAN(identifier: identifier)
            return true
        } catch {
            throw NodeEnvironmentServiceError.sdkmanCommandFailed(message: error.localizedDescription)
        }
    }

    func runSDKMANForceUninstall(identifier: String) throws {
        let command = RuntimeComponentInstaller.sdkmanBootstrap(
            "sdk uninstall java \(Self.shellQuoted(identifier)) --force"
        )
        let result = try shellRunner.runShell(
            command,
            environment: ProcessInfo.processInfo.environment
        )
        guard result.succeeded else {
            throw NodeEnvironmentServiceError.sdkmanCommandFailed(message: Self.preferErrorOutput(result))
        }
    }

    func shouldUsePrivilegedJavaRemoval(path: String) -> Bool {
        path.hasPrefix("/Library/Java/JavaVirtualMachines/")
    }

    func runPrivilegedJavaUninstall(path: String) throws {
        let removeCommand = "/bin/rm -rf \(Self.shellQuoted(path))"
        let appleScript = "do shell script \"\(Self.escapeForAppleScript(removeCommand))\" with administrator privileges"
        let result = try shellRunner.run(
            "/usr/bin/osascript",
            arguments: ["-e", appleScript],
            environment: ProcessInfo.processInfo.environment
        )
        guard result.succeeded else {
            throw NodeEnvironmentServiceError.javaUninstallFailed(
                path: path,
                message: Self.preferErrorOutput(result)
            )
        }
    }

    func removalTargetForNonSDKMANJava(homePath: String) throws -> URL {
        let homeURL = URL(fileURLWithPath: homePath).standardizedFileURL
        let path = homeURL.path

        if path.contains("/Cellar/openjdk"),
           let cellarRange = path.range(of: #"/(opt/homebrew|usr/local)/Cellar/openjdk[^/]*/[^/]+"#, options: .regularExpression) {
            return URL(fileURLWithPath: String(path[cellarRange]), isDirectory: true)
        }

        if path.hasSuffix("/Contents/Home") {
            let bundleURL = homeURL.deletingLastPathComponent().deletingLastPathComponent()
            if bundleURL.path.hasSuffix(".jdk") {
                return bundleURL
            }
        }

        let userHomePrefix = NSHomeDirectory() + "/"
        if path.hasPrefix(userHomePrefix) {
            return homeURL
        }

        if path.hasPrefix("/Library/Java/JavaVirtualMachines/") && path.hasSuffix("/Contents/Home") {
            let bundleURL = homeURL.deletingLastPathComponent().deletingLastPathComponent()
            if bundleURL.path.hasSuffix(".jdk") {
                return bundleURL
            }
        }

        throw NodeEnvironmentServiceError.javaUninstallUnsupported(path)
    }

    static func shellQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\"'\"'"))'"
    }

    static func escapeForAppleScript(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    static func preferErrorOutput(_ result: ShellCommandResult) -> String {
        let stderr = result.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
        if !stderr.isEmpty {
            return stderr
        }
        let stdout = result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        return stdout.isEmpty ? "Unknown shell error" : stdout
    }

    static func extractInstalledVersion(from result: ShellCommandResult) -> String? {
        let combined = [result.standardOutput, result.standardError]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        return NodeInstallationDetector.normalizeVersion(combined)
    }

    static func userFacingInstallFailureMessage(for requestedVersion: String, rawMessage: String) -> String {
        let normalized = rawMessage.lowercased()
        if normalized.contains("darwin-arm64") && normalized.contains("404") {
            return legacyNodeInstallFailureMessage(requestedVersion: requestedVersion, fallbackMessage: rawMessage)
        }
        return rawMessage
    }

    static func legacyNodeInstallFailureMessage(requestedVersion: String, fallbackMessage: String) -> String {
        let detail = fallbackMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        return """
        Node \(requestedVersion) 在 Apple Silicon 上没有可用的 arm64 预编译包，已自动改用 Rosetta/x64 兼容安装，但仍然失败。
        详细原因：\(detail)
        """
    }
}

public enum NodeEnvironmentServiceError: Error, LocalizedError {
    case invalidVersion(String)
    case invalidJavaIdentifier(String)
    case nvmUnavailable
    case nvmCommandFailed(message: String)
    case nodeVersionNotInstalled(String)
    case javaHomeNotInstalled(String)
    case javaUninstallUnsupported(String)
    case javaUninstallFailed(path: String, message: String)
    case sdkmanUnavailable
    case sdkmanCommandFailed(message: String)

    public var errorDescription: String? {
        switch self {
        case .invalidVersion(let version):
            return "Invalid Node version: \(version)"
        case .invalidJavaIdentifier(let identifier):
            return "Invalid Java identifier: \(identifier)"
        case .nvmUnavailable:
            return "NVM is not available."
        case .nvmCommandFailed(let message):
            return "NVM command failed: \(message)"
        case .nodeVersionNotInstalled(let version):
            return "Node \(version) is not installed in NVM."
        case .javaHomeNotInstalled(let homePath):
            return "JDK home is not installed: \(homePath)"
        case .javaUninstallUnsupported(let path):
            return "Uninstall for this JDK path is not supported automatically: \(path)"
        case .javaUninstallFailed(let path, let message):
            return "Failed to uninstall JDK at \(path): \(message)"
        case .sdkmanUnavailable:
            return "SDKMAN is not available."
        case .sdkmanCommandFailed(let message):
            return "SDKMAN command failed: \(message)"
        }
    }
}
