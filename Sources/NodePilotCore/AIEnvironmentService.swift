import Foundation

public enum AIEnvironmentKind: String, CaseIterable, Identifiable, Codable, Sendable {
    case codex
    case claudeCode = "claude-code"
    case pi
    case openCode = "opencode"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .codex:
            return "Codex"
        case .claudeCode:
            return "Claude Code"
        case .pi:
            return "Pi"
        case .openCode:
            return "OpenCode"
        }
    }

    var executableName: String {
        switch self {
        case .codex:
            return "codex"
        case .claudeCode:
            return "claude"
        case .pi:
            return "pi"
        case .openCode:
            return "opencode"
        }
    }

    var npmPackageName: String {
        switch self {
        case .codex:
            return "@openai/codex"
        case .claudeCode:
            return "@anthropic-ai/claude-code"
        case .pi:
            return "@earendil-works/pi-coding-agent"
        case .openCode:
            return "opencode-ai"
        }
    }

    var brewPackageName: String {
        switch self {
        case .codex:
            return "codex"
        case .claudeCode:
            return "claude-code"
        case .pi:
            return "pi-coding-agent"
        case .openCode:
            return "opencode"
        }
    }
}

public enum AIEnvironmentInstallMethod: Equatable, Sendable {
    case homebrewCask(String)
    case homebrewFormula(String)
    case envPilotNode
    case npm
    case pnpm
    case native
    case unknown

    public var label: String {
        switch self {
        case .homebrewCask:
            return "Homebrew Cask"
        case .homebrewFormula:
            return "Homebrew"
        case .envPilotNode:
            return "ENVPilot Node"
        case .npm:
            return "npm"
        case .pnpm:
            return "pnpm"
        case .native:
            return "原生安装"
        case .unknown:
            return "本机安装"
        }
    }
}

enum AIEnvironmentPackageManager: Equatable, Sendable {
    case npm(String)
    case pnpm(String)

    var executablePath: String {
        switch self {
        case .npm(let path), .pnpm(let path):
            return path
        }
    }
}

public enum AIEnvironmentUpdateStage: Int, Sendable {
    case connecting
    case fetchingPackage
    case installing
    case verifying
    case cancelling

    public var message: String {
        switch self {
        case .connecting:
            return "正在连接网络"
        case .fetchingPackage:
            return "正在获取软件包"
        case .installing:
            return "正在安装"
        case .verifying:
            return "正在核对版本"
        case .cancelling:
            return "正在取消"
        }
    }
}

public struct AIEnvironmentStatus: Identifiable, Equatable, Sendable {
    public let kind: AIEnvironmentKind
    public let executablePath: String?
    public let resolvedExecutablePath: String?
    public let currentVersion: String?
    public let latestVersion: String?
    public let installMethod: AIEnvironmentInstallMethod
    public let errorMessage: String?

    public init(
        kind: AIEnvironmentKind,
        executablePath: String? = nil,
        resolvedExecutablePath: String? = nil,
        currentVersion: String? = nil,
        latestVersion: String? = nil,
        installMethod: AIEnvironmentInstallMethod = .unknown,
        errorMessage: String? = nil
    ) {
        self.kind = kind
        self.executablePath = executablePath
        self.resolvedExecutablePath = resolvedExecutablePath
        self.currentVersion = currentVersion
        self.latestVersion = latestVersion
        self.installMethod = installMethod
        self.errorMessage = errorMessage
    }

    public var id: String { kind.rawValue }

    public var isInstalled: Bool {
        executablePath != nil
    }

    public var updateAvailable: Bool {
        guard let currentVersion = AppVersion(currentVersion ?? ""),
              let latestVersion = AppVersion(latestVersion ?? "") else {
            return false
        }
        return currentVersion < latestVersion
    }

    public var canSwitchToEnvPilot: Bool {
        isInstalled && installMethod != .envPilotNode
    }
}

public protocol AIEnvironmentServicing: Sendable {
    func loadStatuses() async -> [AIEnvironmentStatus]
    func switchToEnvPilot(
        _ kind: AIEnvironmentKind,
        cancellation: ShellCommandCancellation?,
        progress: (@Sendable (AIEnvironmentUpdateStage) -> Void)?
    ) async throws -> AIEnvironmentStatus
    func install(
        _ kind: AIEnvironmentKind,
        cancellation: ShellCommandCancellation?,
        progress: (@Sendable (AIEnvironmentUpdateStage) -> Void)?
    ) async throws -> AIEnvironmentStatus
    func update(
        _ kind: AIEnvironmentKind,
        cancellation: ShellCommandCancellation?,
        progress: (@Sendable (AIEnvironmentUpdateStage) -> Void)?
    ) async throws -> AIEnvironmentStatus
}

public extension AIEnvironmentServicing {
    func switchToEnvPilot(_ kind: AIEnvironmentKind) async throws -> AIEnvironmentStatus {
        try await switchToEnvPilot(kind, cancellation: nil, progress: nil)
    }

    func install(_ kind: AIEnvironmentKind) async throws -> AIEnvironmentStatus {
        try await install(kind, cancellation: nil, progress: nil)
    }

    func update(_ kind: AIEnvironmentKind) async throws -> AIEnvironmentStatus {
        try await update(kind, cancellation: nil, progress: nil)
    }
}

public enum AIEnvironmentServiceError: LocalizedError {
    case executableNotFound(AIEnvironmentKind)
    case packageManagerUnavailable
    case managedNodeUnavailable
    case installFailed(command: String, output: String)
    case updateFailed(command: String, output: String)

    public var errorDescription: String? {
        switch self {
        case .executableNotFound(let kind):
            return "没有找到 \(kind.displayName) 可执行文件。"
        case .packageManagerUnavailable:
            return "未找到 npm 或 pnpm，请先安装 ENVPilot Node。"
        case .managedNodeUnavailable:
            return "没有找到当前 ENVPilot Node，请先在运行时页安装或选择 Node 版本。"
        case .installFailed(let command, let output):
            let detail = output.trimmingCharacters(in: .whitespacesAndNewlines)
            return detail.isEmpty ? "\(command) 执行失败。" : "\(command) 执行失败：\(detail)"
        case .updateFailed(let command, let output):
            let detail = output.trimmingCharacters(in: .whitespacesAndNewlines)
            return detail.isEmpty ? "\(command) 执行失败。" : "\(command) 执行失败：\(detail)"
        }
    }
}

public protocol AIEnvironmentLatestVersionProviding: Sendable {
    func latestVersion(for packageName: String) async throws -> String?
}

public struct NPMRegistryLatestVersionProvider: AIEnvironmentLatestVersionProviding, Sendable {
    public init() {}

    public func latestVersion(for packageName: String) async throws -> String? {
        let encodedName = packageName.replacingOccurrences(of: "/", with: "%2F")
        guard let url = URL(string: "https://registry.npmjs.org/\(encodedName)/latest") else {
            return nil
        }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            return nil
        }
        let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return payload?["version"] as? String
    }
}

public struct LocalAIEnvironmentService: AIEnvironmentServicing, Sendable {
    private let shellRunner: any ShellCommandRunning
    private let latestVersionProvider: any AIEnvironmentLatestVersionProviding
    private let settingsStore: any AppSettingsStoring
    private let environment: [String: String]

    public init(
        shellRunner: any ShellCommandRunning = ShellCommandRunner(),
        latestVersionProvider: any AIEnvironmentLatestVersionProviding = NPMRegistryLatestVersionProvider(),
        settingsStore: any AppSettingsStoring = ConfigStore(),
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.shellRunner = shellRunner
        self.latestVersionProvider = latestVersionProvider
        self.settingsStore = settingsStore
        self.environment = environment
    }

    public func loadStatuses() async -> [AIEnvironmentStatus] {
        let executablePaths = resolveExecutablePaths()
        return await withTaskGroup(of: AIEnvironmentStatus.self) { group in
            for kind in AIEnvironmentKind.allCases {
                group.addTask {
                    await status(for: kind, executablePath: executablePaths[kind])
                }
            }

            var byKind: [AIEnvironmentKind: AIEnvironmentStatus] = [:]
            for await status in group {
                byKind[status.kind] = status
            }
            return AIEnvironmentKind.allCases.compactMap { byKind[$0] }
        }
    }

    public func switchToEnvPilot(
        _ kind: AIEnvironmentKind,
        cancellation: ShellCommandCancellation? = nil,
        progress: (@Sendable (AIEnvironmentUpdateStage) -> Void)? = nil
    ) async throws -> AIEnvironmentStatus {
        progress?(.connecting)
        let current = await status(for: kind)
        guard current.isInstalled else {
            throw AIEnvironmentServiceError.executableNotFound(kind)
        }
        guard current.installMethod != .envPilotNode else {
            return current
        }

        progress?(.fetchingPackage)
        let selectedNodePath = try? settingsStore.load().selectedNodePath
        guard let packageManager = resolveManagedPackageManager(selectedNodePath: selectedNodePath) else {
            throw AIEnvironmentServiceError.managedNodeUnavailable
        }
        let plan = Self.installPlan(for: kind, packageManager: packageManager)

        progress?(.installing)
        let result = try shellRunner.runShell(
            """
            \(commandPreamble(
                for: packageManager.executablePath,
                additionalDirectories: managedNodeBinDirectories(selectedNodePath: selectedNodePath)
            ))
            exec \(plan.command)
            """,
            environment: environment,
            cancellation: cancellation,
            onOutput: { output in
                guard let stage = Self.updateStage(from: output) else {
                    return
                }
                progress?(stage)
            }
        )
        if cancellation?.isCancelled == true {
            throw CancellationError()
        }
        guard result.succeeded else {
            let output = [result.standardOutput, result.standardError]
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw AIEnvironmentServiceError.installFailed(command: plan.displayCommand, output: output)
        }

        progress?(.verifying)
        return await status(for: kind)
    }

    public func install(
        _ kind: AIEnvironmentKind,
        cancellation: ShellCommandCancellation? = nil,
        progress: (@Sendable (AIEnvironmentUpdateStage) -> Void)? = nil
    ) async throws -> AIEnvironmentStatus {
        progress?(.connecting)
        let current = await status(for: kind)
        guard !current.isInstalled else {
            return current
        }

        progress?(.fetchingPackage)
        let selectedNodePath = try? settingsStore.load().selectedNodePath
        guard let packageManager = resolvePackageManager(selectedNodePath: selectedNodePath) else {
            throw AIEnvironmentServiceError.packageManagerUnavailable
        }
        let plan = Self.installPlan(for: kind, packageManager: packageManager)

        progress?(.installing)
        let result = try shellRunner.runShell(
            """
            \(commandPreamble(
                for: packageManager.executablePath,
                additionalDirectories: managedNodeBinDirectories(selectedNodePath: selectedNodePath)
            ))
            exec \(plan.command)
            """,
            environment: environment,
            cancellation: cancellation,
            onOutput: { output in
                guard let stage = Self.updateStage(from: output) else {
                    return
                }
                progress?(stage)
            }
        )
        if cancellation?.isCancelled == true {
            throw CancellationError()
        }
        guard result.succeeded else {
            let output = [result.standardOutput, result.standardError]
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw AIEnvironmentServiceError.installFailed(command: plan.displayCommand, output: output)
        }

        progress?(.verifying)
        return await status(for: kind)
    }

    public func update(
        _ kind: AIEnvironmentKind,
        cancellation: ShellCommandCancellation? = nil,
        progress: (@Sendable (AIEnvironmentUpdateStage) -> Void)? = nil
    ) async throws -> AIEnvironmentStatus {
        progress?(.connecting)
        let current = await status(for: kind)
        guard current.isInstalled else {
            throw AIEnvironmentServiceError.executableNotFound(kind)
        }

        progress?(.fetchingPackage)
        let plan = Self.updatePlan(for: current, brewExecutable: brewExecutablePath)
        progress?(.installing)
        let result = try shellRunner.runShell(
            "\(commandPreamble(for: current.executablePath ?? kind.executableName))\nexec \(plan.command)",
            environment: environment,
            cancellation: cancellation,
            onOutput: { output in
                guard let stage = Self.updateStage(from: output) else {
                    return
                }
                progress?(stage)
            }
        )
        if cancellation?.isCancelled == true {
            throw CancellationError()
        }
        guard result.succeeded else {
            let output = [result.standardOutput, result.standardError]
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw AIEnvironmentServiceError.updateFailed(command: plan.displayCommand, output: output)
        }
        progress?(.verifying)
        return await status(for: kind)
    }

    // MARK: Detection

    func status(for kind: AIEnvironmentKind) async -> AIEnvironmentStatus {
        await status(for: kind, executablePath: resolveExecutablePaths()[kind])
    }

    private func status(
        for kind: AIEnvironmentKind,
        executablePath: String?
    ) async -> AIEnvironmentStatus {
        guard let executablePath else {
            let latestVersion = try? await latestVersion(for: kind, installMethod: .unknown)
            return AIEnvironmentStatus(kind: kind, latestVersion: latestVersion)
        }

        let resolvedPath = canonicalPath(executablePath)
        let installMethod = Self.installMethod(for: kind, resolvedPath: resolvedPath)
        let versionOutput = runVersionCommand(executablePath: executablePath)
        let currentVersion = Self.version(from: versionOutput.combinedOutput)
        let latestVersion = try? await latestVersion(for: kind, installMethod: installMethod)

        let errorMessage: String?
        if currentVersion == nil {
            errorMessage = versionOutput.succeeded
                ? "无法从 \(kind.displayName) 的版本输出中识别版本。"
                : versionOutput.combinedOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            errorMessage = nil
        }

        return AIEnvironmentStatus(
            kind: kind,
            executablePath: executablePath,
            resolvedExecutablePath: resolvedPath,
            currentVersion: currentVersion,
            latestVersion: latestVersion,
            installMethod: installMethod,
            errorMessage: errorMessage
        )
    }

    private func resolveExecutablePaths() -> [AIEnvironmentKind: String] {
        let selectedNodePath = try? settingsStore.load().selectedNodePath
        let preferredDirectories = preferredNodeBinDirectories(selectedNodePath: selectedNodePath)
        var paths: [AIEnvironmentKind: String] = [:]
        for kind in AIEnvironmentKind.allCases {
            if let path = Self.executable(named: kind.executableName, in: preferredDirectories) {
                paths[kind] = path
            }
        }

        let command = """
        \(shellPreamble)
        for tool in codex claude pi opencode; do
          tool_path="$(command -v "$tool" 2>/dev/null || true)"
          if [ -n "$tool_path" ]; then
            printf '%s\\t%s\\n' "$tool" "$tool_path"
          fi
        done
        """

        let names = Dictionary(uniqueKeysWithValues: AIEnvironmentKind.allCases.map {
            ($0.executableName, $0)
        })
        if let result = try? shellRunner.runShell(command, environment: environment) {
            for line in result.standardOutput.split(separator: "\n") {
                let parts = line.split(separator: "\t", maxSplits: 1).map(String.init)
                guard parts.count == 2, let kind = names[parts[0]] else {
                    continue
                }
                let path = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                if path.hasPrefix("/"), paths[kind] == nil {
                    paths[kind] = path
                }
            }
        }

        for kind in AIEnvironmentKind.allCases where paths[kind] == nil {
            if let path = Self.fallbackExecutablePath(
                for: kind,
                environment: environment,
                selectedNodePath: selectedNodePath
            ) {
                paths[kind] = path
            }
        }
        return paths
    }

    private func runVersionCommand(executablePath: String) -> ShellCommandResult {
        let command = "\(commandPreamble(for: executablePath))\n\(Self.singleQuoted(executablePath)) --version"
        guard let result = try? shellRunner.runShell(command, environment: environment) else {
            return ShellCommandResult(standardOutput: "", standardError: "", exitCode: 1)
        }
        return result
    }

    // MARK: Latest version

    private func latestVersion(
        for kind: AIEnvironmentKind,
        installMethod: AIEnvironmentInstallMethod
    ) async throws -> String? {
        switch installMethod {
        case .homebrewCask:
            if let version = latestHomebrewVersion(for: kind, cask: true) {
                return version
            }
        case .homebrewFormula:
            if let version = latestHomebrewVersion(for: kind, cask: false) {
                return version
            }
        case .envPilotNode, .npm, .pnpm, .native, .unknown:
            break
        }
        return try await latestVersionProvider.latestVersion(for: kind.npmPackageName)
    }

    private func latestHomebrewVersion(for kind: AIEnvironmentKind, cask: Bool) -> String? {
        guard let brewExecutablePath else {
            return nil
        }
        let typeArgument = cask ? "--cask" : ""
        let command = """
        HOMEBREW_NO_AUTO_UPDATE=1 \(Self.singleQuoted(brewExecutablePath)) info --json=v2 \(typeArgument) \(Self.singleQuoted(kind.brewPackageName))
        """
        guard let result = try? shellRunner.runShell(command, environment: environment),
              result.succeeded,
              let data = result.standardOutput.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        if cask, let casks = root["casks"] as? [[String: Any]] {
            return casks.first?["version"] as? String
        }
        if let formulae = root["formulae"] as? [[String: Any]],
           let versions = formulae.first?["versions"] as? [String: Any] {
            return versions["stable"] as? String
        }
        return nil
    }

    // MARK: Install plan

    struct InstallPlan: Equatable {
        let command: String
        let displayCommand: String
    }

    static func installPlan(
        for kind: AIEnvironmentKind,
        packageManager: AIEnvironmentPackageManager
    ) -> InstallPlan {
        switch packageManager {
        case .npm(let executablePath):
            return InstallPlan(
                command: [
                    singleQuoted(executablePath),
                    "install",
                    "--global",
                    singleQuoted(kind.npmPackageName),
                ].joined(separator: " "),
                displayCommand: "npm install -g \(kind.npmPackageName)"
            )
        case .pnpm(let executablePath):
            return InstallPlan(
                command: [
                    singleQuoted(executablePath),
                    "add",
                    "--global",
                    singleQuoted(kind.npmPackageName),
                ].joined(separator: " "),
                displayCommand: "pnpm add -g \(kind.npmPackageName)"
            )
        }
    }

    // MARK: Update plan

    struct UpdatePlan: Equatable {
        let command: String
        let displayCommand: String
    }

    static func updatePlan(
        for status: AIEnvironmentStatus,
        brewExecutable: String?
    ) -> UpdatePlan {
        switch status.installMethod {
        case .homebrewCask(let package):
            if let brewExecutable {
                let command = "HOMEBREW_NO_AUTO_UPDATE=1 \(singleQuoted(brewExecutable)) upgrade --cask \(singleQuoted(package))"
                return UpdatePlan(command: command, displayCommand: "brew upgrade --cask \(package)")
            }
        case .homebrewFormula(let package):
            if let brewExecutable {
                let command = "HOMEBREW_NO_AUTO_UPDATE=1 \(singleQuoted(brewExecutable)) upgrade \(singleQuoted(package))"
                return UpdatePlan(command: command, displayCommand: "brew upgrade \(package)")
            }
        case .envPilotNode, .npm, .pnpm, .native, .unknown:
            break
        }

        let executable = status.executablePath ?? status.kind.executableName
        let arguments: [String]
        switch status.kind {
        case .codex:
            arguments = ["update"]
        case .claudeCode:
            arguments = ["update"]
        case .pi:
            arguments = ["update", "pi"]
        case .openCode:
            arguments = ["upgrade"]
        }
        let command = ([singleQuoted(executable)] + arguments.map(singleQuoted)).joined(separator: " ")
        return UpdatePlan(
            command: command,
            displayCommand: "\(status.kind.executableName) \(arguments.joined(separator: " "))"
        )
    }

    static func updateStage(from output: String) -> AIEnvironmentUpdateStage? {
        let lowercased = output.lowercased()
        if lowercased.contains("installing")
            || lowercased.contains("installation")
            || lowercased.contains("linking") {
            return .installing
        }
        if lowercased.contains("downloading")
            || lowercased.contains("fetching")
            || lowercased.contains("resolving") {
            return .fetchingPackage
        }
        return nil
    }

    // MARK: Helpers

    private var shellPreamble: String {
        """
        export ENVPILOT_ACTIVATING=1
        if [ -f "$HOME/.zshrc" ]; then
          . "$HOME/.zshrc" >/dev/null 2>&1 || true
        fi
        """
    }

    private func commandPreamble(for executablePath: String) -> String {
        commandPreamble(for: executablePath, additionalDirectories: [])
    }

    private func commandPreamble(
        for executablePath: String,
        additionalDirectories: [String]
    ) -> String {
        let executableDirectory = URL(fileURLWithPath: executablePath)
            .deletingLastPathComponent()
            .standardizedFileURL
            .path
        let directories = ([executableDirectory] + additionalDirectories).reduce(into: [String]()) {
            guard !$0.contains($1) else {
                return
            }
            $0.append($1)
        }
        let path = directories.map(Self.singleQuoted).joined(separator: ":")
        return """
        \(shellPreamble)
        export PATH=\(path):"$PATH"
        """
    }

    private var brewExecutablePath: String? {
        ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static func installMethod(for kind: AIEnvironmentKind, resolvedPath: String) -> AIEnvironmentInstallMethod {
        let lowercasedPath = resolvedPath.lowercased()
        if resolvedPath.contains("/Caskroom/") {
            return .homebrewCask(kind.brewPackageName)
        }
        if resolvedPath.contains("/Cellar/") || resolvedPath.contains("/homebrew/opt/") {
            return .homebrewFormula(kind.brewPackageName)
        }
        if resolvedPath.contains("/.envpilot/runtimes/node/") {
            return .envPilotNode
        }
        if lowercasedPath.contains("/.pnpm/")
            || lowercasedPath.contains("/pnpm/global/")
            || lowercasedPath.contains("/library/pnpm/")
            || lowercasedPath.contains("/.local/share/pnpm/") {
            return .pnpm
        }
        if resolvedPath.contains("/node_modules/") {
            return .npm
        }
        if resolvedPath.hasPrefix("/") {
            return .native
        }
        return .unknown
    }

    private func resolvePackageManager(selectedNodePath: String?) -> AIEnvironmentPackageManager? {
        if let packageManager = resolveManagedPackageManager(selectedNodePath: selectedNodePath) {
            return packageManager
        }

        let managedDirectories = managedNodeBinDirectories(selectedNodePath: selectedNodePath)
        if let npm = Self.executable(named: "npm", in: managedDirectories) {
            return .npm(npm)
        }
        if let pnpm = Self.executable(named: "pnpm", in: managedDirectories) {
            return .pnpm(pnpm)
        }

        let command = """
        \(shellPreamble)
        for tool in npm pnpm; do
          tool_path="$(command -v "$tool" 2>/dev/null || true)"
          if [ -n "$tool_path" ] && [ -x "$tool_path" ]; then
            printf '%s\\t%s\\n' "$tool" "$tool_path"
          fi
        done
        """
        guard let result = try? shellRunner.runShell(command, environment: environment) else {
            return nil
        }

        var paths: [String: String] = [:]
        for line in result.standardOutput.split(separator: "\n") {
            let parts = line.split(separator: "\t", maxSplits: 1).map(String.init)
            guard parts.count == 2 else {
                continue
            }
            paths[parts[0]] = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let npm = paths["npm"] {
            return .npm(npm)
        }
        if let pnpm = paths["pnpm"] {
            return .pnpm(pnpm)
        }
        return nil
    }

    private func resolveManagedPackageManager(selectedNodePath: String?) -> AIEnvironmentPackageManager? {
        let directories = preferredNodeBinDirectories(selectedNodePath: selectedNodePath)
        if let npm = Self.executable(named: "npm", in: directories) {
            return .npm(npm)
        }
        if let pnpm = Self.executable(named: "pnpm", in: directories) {
            return .pnpm(pnpm)
        }
        return nil
    }

    private func preferredNodeBinDirectories(selectedNodePath: String?) -> [String] {
        let envPilotNodeHome = Self.nonEmpty(environment["ENVPILOT_NODE_HOME"])
        var directories = [
            envPilotNodeHome.map { "\($0)/bin" },
            Self.nonEmpty(selectedNodePath).map { "\($0)/bin" },
        ].compactMap { $0 }

        var seen: Set<String> = []
        directories = directories.filter { seen.insert($0).inserted }
        return directories
    }

    private func managedNodeBinDirectories(selectedNodePath: String?) -> [String] {
        let home = Self.nonEmpty(environment["HOME"]) ?? NSHomeDirectory()
        var directories = preferredNodeBinDirectories(selectedNodePath: selectedNodePath)
        directories.append(contentsOf: Self.managedNodeBinDirectories(home: home, fileManager: .default))
        var seen: Set<String> = []
        return directories.filter { seen.insert($0).inserted }
    }

    private static func executable(named name: String, in directories: [String]) -> String? {
        for directory in directories {
            let path = URL(fileURLWithPath: directory, isDirectory: true)
                .appendingPathComponent(name)
                .standardizedFileURL
                .path
            if isExecutableFile(path, fileManager: .default) {
                return path
            }
        }
        return nil
    }

    static func fallbackExecutablePath(
        for kind: AIEnvironmentKind,
        environment: [String: String],
        selectedNodePath: String? = nil,
        fileManager: FileManager = .default
    ) -> String? {
        let home = Self.nonEmpty(environment["HOME"]) ?? NSHomeDirectory()
        let envPilotNodeHome = Self.nonEmpty(environment["ENVPILOT_NODE_HOME"])
        let pnpmHome = Self.nonEmpty(environment["PNPM_HOME"])
        let npmPrefix = Self.nonEmpty(environment["NPM_CONFIG_PREFIX"])
            ?? Self.nonEmpty(environment["NPM_PREFIX"])

        var directoryCandidates: [String?] = [
            envPilotNodeHome.map { "\($0)/bin" },
            Self.nonEmpty(selectedNodePath).map { "\($0)/bin" },
        ]
        directoryCandidates.append(contentsOf: Self.managedNodeBinDirectories(home: home, fileManager: fileManager).map(Optional.some))
        directoryCandidates.append(contentsOf: [
            pnpmHome,
            "\(home)/Library/pnpm",
            "\(home)/.local/share/pnpm",
            "\(home)/.pnpm",
            npmPrefix.map { "\($0)/bin" },
            "\(home)/.npm-global/bin",
            "\(home)/.local/bin",
            "\(home)/.volta/bin",
            "\(home)/.bun/bin",
            "/opt/homebrew/bin",
            "/usr/local/bin",
        ])

        var seen: Set<String> = []
        for directory in directoryCandidates.compactMap({ $0 }) {
            let path = URL(fileURLWithPath: directory, isDirectory: true)
                .appendingPathComponent(kind.executableName)
                .standardizedFileURL
                .path
            guard seen.insert(path).inserted else {
                continue
            }
            if Self.isExecutableFile(path, fileManager: fileManager) {
                return path
            }
        }
        return nil
    }

    private static func managedNodeBinDirectories(
        home: String,
        fileManager: FileManager
    ) -> [String] {
        let roots = [
            "\(home)/.envpilot/runtimes/node",
            "\(home)/.envpilot/node",
            "\(home)/.local/share/envpilot/node",
            "\(home)/.local/node",
        ]
        var directories: [String] = []

        for root in roots {
            let versionDirectories = (try? fileManager.contentsOfDirectory(
                at: URL(fileURLWithPath: root, isDirectory: true),
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )) ?? []

            directories.append(contentsOf: versionDirectories
                .filter { url in
                    (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                }
                .sorted {
                    $0.lastPathComponent.compare(
                        $1.lastPathComponent,
                        options: [.numeric, .caseInsensitive]
                    ) == .orderedDescending
                }
                .map { $0.appendingPathComponent("bin", isDirectory: true).path })
        }

        return directories
    }

    static func version(from output: String) -> String? {
        let pattern = #"(?<![0-9A-Za-z])(\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                  in: output,
                  range: NSRange(output.startIndex..<output.endIndex, in: output)
              ),
              let range = Range(match.range(at: 1), in: output) else {
            return nil
        }
        return String(output[range])
    }

    private func canonicalPath(_ path: String) -> String {
        URL(fileURLWithPath: path)
            .resolvingSymlinksInPath()
            .standardizedFileURL
            .path
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func isExecutableFile(_ path: String, fileManager: FileManager) -> Bool {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory),
              !isDirectory.boolValue else {
            return false
        }
        return fileManager.isExecutableFile(atPath: path)
    }

    private static func singleQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\"'\"'"))'"
    }
}

private extension ShellCommandResult {
    var combinedOutput: String {
        [standardOutput, standardError]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}
