import Foundation

public enum PackageManagerKind: String, CaseIterable, Identifiable, Codable, Sendable {
    case npm
    case pnpm
    case homebrew
    case uv

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .npm:
            return "npm"
        case .pnpm:
            return "pnpm"
        case .homebrew:
            return "Homebrew"
        case .uv:
            return "uv"
        }
    }

    var executableName: String {
        switch self {
        case .npm:
            return "npm"
        case .pnpm:
            return "pnpm"
        case .homebrew:
            return "brew"
        case .uv:
            return "uv"
        }
    }

    var homebrewPackageName: String {
        switch self {
        case .npm:
            return "node"
        case .pnpm:
            return "pnpm"
        case .homebrew:
            return "brew"
        case .uv:
            return "uv"
        }
    }

    var npmRegistryPackageName: String? {
        switch self {
        case .npm:
            return "npm"
        case .pnpm:
            return "pnpm"
        case .homebrew, .uv:
            return nil
        }
    }

    var githubRepository: String? {
        switch self {
        case .homebrew:
            return "Homebrew/brew"
        case .uv:
            return "astral-sh/uv"
        case .npm, .pnpm:
            return nil
        }
    }
}

public enum PackageManagerInstallMethod: Equatable, Sendable {
    case homebrew
    case envPilot
    case envPilotNode
    case npm
    case pnpm
    case standalone
    case native
    case unknown

    public var label: String {
        switch self {
        case .homebrew:
            return "Homebrew"
        case .envPilot:
            return "ENVPilot"
        case .envPilotNode:
            return "ENVPilot Node"
        case .npm:
            return "npm"
        case .pnpm:
            return "pnpm"
        case .standalone:
            return "独立安装"
        case .native:
            return "原生安装"
        case .unknown:
            return "本机安装"
        }
    }
}

public struct PackageManagerStatus: Identifiable, Equatable, Sendable {
    public let kind: PackageManagerKind
    public let executablePath: String?
    public let resolvedExecutablePath: String?
    public let currentVersion: String?
    public let latestVersion: String?
    public let installMethod: PackageManagerInstallMethod
    public let errorMessage: String?
    /// 操作成功后需要额外告知用户的副作用（目前只有「原独立安装被移到废纸篓」）。
    ///
    /// 单独一个字段而不是塞进 `errorMessage`：这不是错误，App 层可以把它追加在成功
    /// 提示后面，用户才不会以为自己是「凭空」发现 `~/.local/bin/pnpm` 不见了。
    public var cleanupNotice: String?

    public init(
        kind: PackageManagerKind,
        executablePath: String? = nil,
        resolvedExecutablePath: String? = nil,
        currentVersion: String? = nil,
        latestVersion: String? = nil,
        installMethod: PackageManagerInstallMethod = .unknown,
        errorMessage: String? = nil,
        cleanupNotice: String? = nil
    ) {
        self.kind = kind
        self.executablePath = executablePath
        self.resolvedExecutablePath = resolvedExecutablePath
        self.currentVersion = currentVersion
        self.latestVersion = latestVersion
        self.installMethod = installMethod
        self.errorMessage = errorMessage
        self.cleanupNotice = cleanupNotice
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
        guard isInstalled else {
            return false
        }
        switch kind {
        case .pnpm:
            return installMethod != .envPilotNode
        case .uv:
            return installMethod != .envPilot
        case .npm, .homebrew:
            return false
        }
    }
}

public protocol PackageManagerServicing: Sendable {
    func loadStatuses() async -> [PackageManagerStatus]
    func switchToEnvPilot(
        _ kind: PackageManagerKind,
        cancellation: ShellCommandCancellation?,
        progress: (@Sendable (AIEnvironmentUpdateStage) -> Void)?
    ) async throws -> PackageManagerStatus
    func install(
        _ kind: PackageManagerKind,
        cancellation: ShellCommandCancellation?,
        progress: (@Sendable (AIEnvironmentUpdateStage) -> Void)?
    ) async throws -> PackageManagerStatus
    func update(
        _ kind: PackageManagerKind,
        cancellation: ShellCommandCancellation?,
        progress: (@Sendable (AIEnvironmentUpdateStage) -> Void)?
    ) async throws -> PackageManagerStatus
}

public extension PackageManagerServicing {
    func switchToEnvPilot(_ kind: PackageManagerKind) async throws -> PackageManagerStatus {
        try await switchToEnvPilot(kind, cancellation: nil, progress: nil)
    }

    func install(_ kind: PackageManagerKind) async throws -> PackageManagerStatus {
        try await install(kind, cancellation: nil, progress: nil)
    }

    func update(_ kind: PackageManagerKind) async throws -> PackageManagerStatus {
        try await update(kind, cancellation: nil, progress: nil)
    }
}

public enum PackageManagerServiceError: LocalizedError {
    case executableNotFound(PackageManagerKind)
    case homebrewUnavailable
    case managedNodeUnavailable
    case switchUnsupported(PackageManagerKind)
    case installFailed(command: String, output: String)
    case updateFailed(command: String, output: String)

    public var errorDescription: String? {
        switch self {
        case .executableNotFound(let kind):
            return "没有找到 \(kind.displayName) 可执行文件。"
        case .homebrewUnavailable:
            return "没有找到 Homebrew，无法使用 brew 更新该工具。"
        case .managedNodeUnavailable:
            return "没有找到 ENVPilot Node，请先在运行时页安装或选择 Node 版本。"
        case .switchUnsupported(let kind):
            return "\(kind.displayName) 暂不支持切换到 ENVPilot 安装。"
        case .installFailed(let command, let output):
            let detail = output.trimmingCharacters(in: .whitespacesAndNewlines)
            return detail.isEmpty ? "\(command) 执行失败。" : "\(command) 执行失败：\(detail)"
        case .updateFailed(let command, let output):
            let detail = output.trimmingCharacters(in: .whitespacesAndNewlines)
            return detail.isEmpty ? "\(command) 执行失败。" : "\(command) 执行失败：\(detail)"
        }
    }
}

public protocol PackageManagerLatestVersionProviding: Sendable {
    func latestVersion(
        for kind: PackageManagerKind,
        registryURL: URL?
    ) async throws -> String?
}

public extension PackageManagerLatestVersionProviding {
    func latestVersion(for kind: PackageManagerKind) async throws -> String? {
        try await latestVersion(for: kind, registryURL: nil)
    }
}

public struct PackageManagerLatestVersionProvider: PackageManagerLatestVersionProviding, Sendable {
    public init() {}

    public func latestVersion(
        for kind: PackageManagerKind,
        registryURL: URL?
    ) async throws -> String? {
        if let packageName = kind.npmRegistryPackageName {
            return try await npmRegistryLatestVersion(
                packageName: packageName,
                registryURL: registryURL
            )
        }
        if let repository = kind.githubRepository {
            return try await githubLatestVersion(repository: repository)
        }
        return nil
    }

    private func npmRegistryLatestVersion(
        packageName: String,
        registryURL: URL?
    ) async throws -> String? {
        let encodedName = packageName.replacingOccurrences(of: "/", with: "%2F")
        let registry = registryURL?.absoluteString
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            ?? "https://registry.npmjs.org"
        guard let url = URL(string: "\(registry)/\(encodedName)/latest") else {
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

    private func githubLatestVersion(repository: String) async throws -> String? {
        guard let url = URL(string: "https://api.github.com/repos/\(repository)/releases/latest") else {
            return nil
        }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("ENVPilot", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            return nil
        }
        let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return (payload?["tag_name"] as? String)
            ?? (payload?["name"] as? String)
    }
}

public struct LocalPackageManagerService: PackageManagerServicing, Sendable {
    private let shellRunner: any ShellCommandRunning
    private let latestVersionProvider: any PackageManagerLatestVersionProviding
    private let environment: [String: String]

    public init(
        shellRunner: any ShellCommandRunning = ShellCommandRunner(),
        latestVersionProvider: any PackageManagerLatestVersionProviding = PackageManagerLatestVersionProvider(),
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.shellRunner = shellRunner
        self.latestVersionProvider = latestVersionProvider
        self.environment = environment
    }

    public func loadStatuses() async -> [PackageManagerStatus] {
        let executablePaths = resolveExecutablePaths()
        return await withTaskGroup(of: PackageManagerStatus.self) { group in
            for kind in PackageManagerKind.allCases {
                group.addTask {
                    await status(for: kind, executablePath: executablePaths[kind])
                }
            }

            var byKind: [PackageManagerKind: PackageManagerStatus] = [:]
            for await status in group {
                byKind[status.kind] = status
            }
            return PackageManagerKind.allCases.compactMap { byKind[$0] }
        }
    }

    public func install(
        _ kind: PackageManagerKind,
        cancellation: ShellCommandCancellation? = nil,
        progress: (@Sendable (AIEnvironmentUpdateStage) -> Void)? = nil
    ) async throws -> PackageManagerStatus {
        progress?(.connecting)
        let detection = DetectionCache()
        let current = await status(for: kind, cache: detection)
        guard !current.isInstalled else {
            return current
        }

        progress?(.fetchingPackage)
        let plan = Self.installPlan(for: kind)
        progress?(.installing)
        let stageProgress = StageDeduplicator(progress: progress)
        let result = try shellRunner.runShell(
            // 这里不能再加 `exec`：安装计划已经是「下载→校验→执行→清理」的多行脚本，
            // `exec` 只接得住单个简单命令。去掉它也不影响取消——取消现在杀的是整棵
            // 进程树，退出码仍由脚本最后一条命令决定。
            "\(shellPreamble)\n\(plan.command)",
            environment: environmentWithMirror(for: kind),
            cancellation: cancellation,
            onOutput: { stageProgress.emit(from: $0) }
        )
        try validate(result, cancellation: cancellation, plan: plan, isUpdate: false)

        progress?(.verifying)
        // 安装命令会把可执行文件写到新目录，路径表必须重算；最新版本沿用操作开始时
        // 查到的那一次，不为同一个 kind 再打一遍网络请求。
        detection.invalidateExecutablePaths()
        var updated = await status(for: kind, cache: detection)
        let trashed = Self.removeStandaloneInstallation(
            for: kind,
            currentPath: current.executablePath,
            managedPath: updated.executablePath,
            home: Self.nonEmpty(environment["HOME"]) ?? NSHomeDirectory()
        )
        updated.cleanupNotice = Self.cleanupNotice(forTrashedPaths: trashed)
        return updated
    }

    public func switchToEnvPilot(
        _ kind: PackageManagerKind,
        cancellation: ShellCommandCancellation? = nil,
        progress: (@Sendable (AIEnvironmentUpdateStage) -> Void)? = nil
    ) async throws -> PackageManagerStatus {
        guard kind == .pnpm || kind == .uv else {
            throw PackageManagerServiceError.switchUnsupported(kind)
        }

        progress?(.connecting)
        let detection = DetectionCache()
        // 切换前先看一眼当前可执行文件是谁：切换成功后要把它（以及同名伴随命令）
        // 从独立安装目录移到废纸篓，否则 `~/.local/bin/pnpm` 会继续在 PATH 里抢先。
        let current = await status(for: kind, cache: detection)
        let selectedNodePath = try? ConfigStore().load().selectedNodePath
        let managedNPMPath = managedNPMPath(selectedNodePath: selectedNodePath)
        let plan = try Self.switchToEnvPilotPlan(
            for: kind,
            managedNPMPath: managedNPMPath
        )
        progress?(.fetchingPackage)
        progress?(.installing)

        let preamble = managedNPMPath.map(commandPreamble(for:)) ?? shellPreamble
        let stageProgress = StageDeduplicator(progress: progress)
        let result = try shellRunner.runShell(
            // 同 `install`：计划是可能含下载校验的多行脚本，不能再用 `exec`。
            """
            \(preamble)
            \(plan.command)
            """,
            environment: environmentWithMirror(for: kind),
            cancellation: cancellation,
            onOutput: { stageProgress.emit(from: $0) }
        )
        try validate(result, cancellation: cancellation, plan: plan, isUpdate: false)

        progress?(.verifying)
        detection.invalidateExecutablePaths()
        var updated = await status(for: kind, cache: detection)
        let trashed = Self.removeStandaloneInstallation(
            for: kind,
            currentPath: current.executablePath,
            managedPath: updated.executablePath,
            home: Self.nonEmpty(environment["HOME"]) ?? NSHomeDirectory()
        )
        updated.cleanupNotice = Self.cleanupNotice(forTrashedPaths: trashed)
        return updated
    }

    public func update(
        _ kind: PackageManagerKind,
        cancellation: ShellCommandCancellation? = nil,
        progress: (@Sendable (AIEnvironmentUpdateStage) -> Void)? = nil
    ) async throws -> PackageManagerStatus {
        progress?(.connecting)
        let detection = DetectionCache()
        let current = await status(for: kind, cache: detection)
        guard current.isInstalled else {
            throw PackageManagerServiceError.executableNotFound(kind)
        }

        progress?(.fetchingPackage)
        let plan = try Self.updatePlan(
            for: current,
            brewExecutable: brewExecutablePath
        )
        let executablePath = current.executablePath ?? kind.executableName
        progress?(.installing)
        let stageProgress = StageDeduplicator(progress: progress)
        let result = try shellRunner.runShell(
            """
            \(commandPreamble(for: executablePath))
            \(plan.command)
            """,
            environment: environmentWithMirror(for: kind),
            cancellation: cancellation,
            onOutput: { stageProgress.emit(from: $0) }
        )
        try validate(result, cancellation: cancellation, plan: plan, isUpdate: true)

        progress?(.verifying)
        // 更新是原地替换，可执行文件路径不会变，直接复用操作开始时的解析结果，
        // 省掉一次 `zsh -lc command -v` + 目录扫描和一次「最新版本」请求。
        return await status(for: kind, cache: detection)
    }

    // MARK: Detection

    /// 单次查询：只为这一个 kind 解析一次路径（保持原有行为，不引入跨查询缓存）。
    func status(for kind: PackageManagerKind) async -> PackageManagerStatus {
        await status(for: kind, executablePath: resolveExecutablePaths()[kind])
    }

    /// 用调用方已经探测好的路径算状态。`latestVersion` 仍按需请求一次，不做缓存。
    private func status(
        for kind: PackageManagerKind,
        executablePath: String?
    ) async -> PackageManagerStatus {
        let cache = DetectionCache()
        cache.storeExecutablePaths(executablePath.map { [kind: $0] } ?? [:])
        return await status(for: kind, cache: cache)
    }

    /// 一次操作内共享探测结果的版本：同一份路径表、同一次「最新版本」请求。
    private func status(
        for kind: PackageManagerKind,
        cache: DetectionCache
    ) async -> PackageManagerStatus {
        let registryURL = packageManagerRegistryURL(for: kind)
        guard let executablePath = resolvedExecutablePaths(cache: cache)[kind] else {
            let latestVersion = await latestVersion(for: kind, registryURL: registryURL, cache: cache)
            return PackageManagerStatus(kind: kind, latestVersion: latestVersion)
        }

        let resolvedPath = canonicalPath(executablePath)
        let installMethod = Self.installMethod(for: kind, resolvedPath: resolvedPath)
        let versionOutput = runVersionCommand(executablePath: executablePath)
        let currentVersion = Self.version(from: versionOutput.combinedOutput)
        let latestVersion = await latestVersion(for: kind, registryURL: registryURL, cache: cache)

        let errorMessage: String?
        if currentVersion == nil {
            errorMessage = versionOutput.succeeded
                ? "无法从 \(kind.displayName) 的版本输出中识别版本。"
                : versionOutput.combinedOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            errorMessage = nil
        }

        return PackageManagerStatus(
            kind: kind,
            executablePath: executablePath,
            resolvedExecutablePath: resolvedPath,
            currentVersion: currentVersion,
            latestVersion: latestVersion,
            installMethod: installMethod,
            errorMessage: errorMessage
        )
    }

    /// 路径表只在第一次需要时解析，之后整次操作复用。
    private func resolvedExecutablePaths(cache: DetectionCache) -> [PackageManagerKind: String] {
        if let cached = cache.cachedExecutablePaths() {
            return cached
        }
        let paths = resolveExecutablePaths()
        cache.storeExecutablePaths(paths)
        return paths
    }

    /// 「最新版本」整个操作只查一次：同一个版本在操作前后不会有意义地变化。
    private func latestVersion(
        for kind: PackageManagerKind,
        registryURL: URL?,
        cache: DetectionCache
    ) async -> String? {
        let cached = cache.cachedLatestVersion(for: kind)
        if cached.found {
            return cached.value
        }
        let version = (try? await latestVersionProvider.latestVersion(
            for: kind,
            registryURL: registryURL
        )) ?? nil
        cache.storeLatestVersion(version, for: kind)
        return version
    }

    private func resolveExecutablePaths() -> [PackageManagerKind: String] {
        let selectedNodePath = try? ConfigStore().load().selectedNodePath
        let home = Self.nonEmpty(environment["HOME"]) ?? NSHomeDirectory()
        let managedNodeDirectories = managedNodeBinDirectories(selectedNodePath: selectedNodePath)
        var paths: [PackageManagerKind: String] = [:]
        if let npm = Self.executable(named: "npm", in: managedNodeDirectories) {
            paths[.npm] = npm
        }
        if let pnpm = Self.executable(named: "pnpm", in: managedNodeDirectories) {
            paths[.pnpm] = pnpm
        }
        let managedUV = URL(fileURLWithPath: home, isDirectory: true)
            .appendingPathComponent(".envpilot/tools/uv")
            .standardizedFileURL
            .path
        if Self.isExecutableFile(managedUV, fileManager: .default) {
            paths[.uv] = managedUV
        }

        let command = """
        \(shellPreamble)
        for tool in npm pnpm brew uv; do
          tool_path="$(command -v "$tool" 2>/dev/null || true)"
          if [ -n "$tool_path" ]; then
            printf '%s\\t%s\\n' "$tool" "$tool_path"
          fi
        done
        """

        let names = Dictionary(uniqueKeysWithValues: PackageManagerKind.allCases.map {
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

        for kind in PackageManagerKind.allCases where paths[kind] == nil {
            if let path = Self.fallbackExecutablePath(
                for: kind,
                environment: environment,
                selectedNodePath: selectedNodePath,
                home: home
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

    private func managedNPMPath(selectedNodePath: String?) -> String? {
        Self.executable(
            named: "npm",
            in: managedNodeBinDirectories(selectedNodePath: selectedNodePath)
        )
    }

    private func managedNodeBinDirectories(selectedNodePath: String?) -> [String] {
        let home = Self.nonEmpty(environment["HOME"]) ?? NSHomeDirectory()
        let envPilotNodeHome = Self.nonEmpty(environment["ENVPILOT_NODE_HOME"])
        var directories = [
            envPilotNodeHome.map { "\($0)/bin" },
            Self.nonEmpty(selectedNodePath).map { "\($0)/bin" },
        ].compactMap { $0 }

        let root = URL(fileURLWithPath: home, isDirectory: true)
            .appendingPathComponent(".envpilot/runtimes/node", isDirectory: true)
        let versions = (try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        directories.append(contentsOf: versions
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .sorted {
                $0.lastPathComponent.compare(
                    $1.lastPathComponent,
                    options: [.numeric, .caseInsensitive]
                ) == .orderedDescending
            }
            .map { $0.appendingPathComponent("bin", isDirectory: true).path })

        var seen: Set<String> = []
        return directories.filter { seen.insert($0).inserted }
    }

    // MARK: Plans

    struct ActionPlan: Equatable {
        let command: String
        let displayCommand: String
    }

    static func installPlan(for kind: PackageManagerKind) -> ActionPlan {
        switch kind {
        case .npm:
            return remoteScriptPlan(url: "https://www.npmjs.com/install.sh")
        case .pnpm:
            return remoteScriptPlan(url: "https://get.pnpm.io/install.sh")
        case .homebrew:
            // Homebrew 官方脚本必须用 /bin/bash 跑；NONINTERACTIVE=1 关掉所有交互提问。
            return remoteScriptPlan(
                url: "https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh",
                interpreter: "/bin/bash",
                environment: ["NONINTERACTIVE=1"]
            )
        case .uv:
            return remoteScriptPlan(url: "https://astral.sh/uv/install.sh")
        }
    }

    /// 远程安装脚本的统一执行方式：先下载到临时文件、确认内容像脚本，再交给解释器执行。
    ///
    /// 以前是 `curl ... | sh`：HTTP 层拿到的错误页会被当成脚本直接执行（npm 那条连 `-f`
    /// 都没有）。这些 URL 全是 `latest`/`HEAD` 引用，上游内容随时变，无法固定 SHA 校验；
    /// 这里能给出的保证是「下载完整、且内容确实是一段脚本之后，才执行任何东西」。
    static func remoteScriptPlan(
        url: String,
        interpreter: String = "sh",
        environment: [String] = []
    ) -> ActionPlan {
        let prefix = environment.isEmpty ? "" : "env " + environment.joined(separator: " ") + " "
        return ActionPlan(
            command: """
            installer="$(mktemp -t envpilot-installer)"
            trap 'rm -f "$installer"' EXIT
            curl -fsSL \(singleQuoted(url)) -o "$installer" || exit 1
            [ -s "$installer" ] || { echo "ENVPilot: 安装脚本下载为空" >&2; exit 1; }
            head -c 2 "$installer" | grep -q '#!' || { echo "ENVPilot: 下载内容不是脚本" >&2; exit 1; }
            \(prefix)\(interpreter) "$installer"
            """,
            displayCommand: "curl -fsSL \(url) -o <临时文件> && \(prefix)\(interpreter) <临时文件>"
        )
    }

    static func switchToEnvPilotPlan(
        for kind: PackageManagerKind,
        managedNPMPath: String?
    ) throws -> ActionPlan {
        switch kind {
        case .pnpm:
            guard let managedNPMPath else {
                throw PackageManagerServiceError.managedNodeUnavailable
            }
            return ActionPlan(
                command: "\(singleQuoted(managedNPMPath)) install --global pnpm@latest",
                displayCommand: "npm install -g pnpm@latest"
            )
        case .uv:
            // uv 官方脚本同样先落盘再执行；UV_INSTALL_DIR 让它装进 ENVPilot 私有目录。
            return remoteScriptPlan(
                url: "https://astral.sh/uv/install.sh",
                environment: [
                    #"UV_INSTALL_DIR="$HOME/.envpilot/tools""#,
                    "UV_NO_MODIFY_PATH=1",
                ]
            )
        case .npm, .homebrew:
            throw PackageManagerServiceError.switchUnsupported(kind)
        }
    }

    static func updatePlan(
        for status: PackageManagerStatus,
        brewExecutable: String?
    ) throws -> ActionPlan {
        if status.kind == .homebrew {
            let executable = status.executablePath ?? status.kind.executableName
            return ActionPlan(
                command: "\(singleQuoted(executable)) update",
                displayCommand: "brew update"
            )
        }
        if status.installMethod == .homebrew, let brewExecutable {
            let command = "HOMEBREW_NO_AUTO_UPDATE=1 \(singleQuoted(brewExecutable)) upgrade \(singleQuoted(status.kind.homebrewPackageName))"
            return ActionPlan(
                command: command,
                displayCommand: "brew upgrade \(status.kind.homebrewPackageName)"
            )
        }
        if status.installMethod == .homebrew {
            throw PackageManagerServiceError.homebrewUnavailable
        }

        let executable = status.executablePath ?? status.kind.executableName
        switch status.kind {
        case .npm:
            return ActionPlan(
                command: "\(singleQuoted(executable)) install --global npm@latest",
                displayCommand: "npm install -g npm@latest"
            )
        case .pnpm:
            return ActionPlan(
                command: "\(singleQuoted(executable)) self-update",
                displayCommand: "pnpm self-update"
            )
        case .homebrew:
            return ActionPlan(
                command: "\(singleQuoted(executable)) update",
                displayCommand: "brew update"
            )
        case .uv:
            return ActionPlan(
                command: "\(singleQuoted(executable)) self update",
                displayCommand: "uv self update"
            )
        }
    }

    static func updateStage(from output: String) -> AIEnvironmentUpdateStage? {
        let lowercased = output.lowercased()
        if lowercased.contains("installing")
            || lowercased.contains("installation")
            || lowercased.contains("linking")
            || lowercased.contains("adding") {
            return .installing
        }
        if lowercased.contains("downloading")
            || lowercased.contains("fetching")
            || lowercased.contains("resolving")
            || lowercased.contains("updating") {
            return .fetchingPackage
        }
        return nil
    }

    // MARK: Helpers

    private func validate(
        _ result: ShellCommandResult,
        cancellation: ShellCommandCancellation?,
        plan: ActionPlan,
        isUpdate: Bool
    ) throws {
        if cancellation?.isCancelled == true {
            throw CancellationError()
        }
        guard result.succeeded else {
            let output = [result.standardOutput, result.standardError]
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if isUpdate {
                throw PackageManagerServiceError.updateFailed(command: plan.displayCommand, output: output)
            }
            throw PackageManagerServiceError.installFailed(command: plan.displayCommand, output: output)
        }
    }

    private var shellPreamble: String {
        """
        export ENVPILOT_ACTIVATING=1
        if [ -f "$HOME/.zshrc" ]; then
          . "$HOME/.zshrc" >/dev/null 2>&1 || true
        fi
        """
    }

    private func packageManagerRegistryURL(for kind: PackageManagerKind) -> URL? {
        let settings = try? ConfigStore().load()
        guard let address = settings?.packageManagerMirrors.address(for: kind) else {
            return nil
        }
        return URL(string: address)
    }

    private func environmentWithMirror(for kind: PackageManagerKind) -> [String: String] {
        guard let address = (try? ConfigStore().load())?
            .packageManagerMirrors
            .address(for: kind) else {
            return environment
        }
        return Self.environment(environment, applyingMirror: address, for: kind)
    }

    static func environment(
        _ environment: [String: String],
        applyingMirror address: String,
        for kind: PackageManagerKind
    ) -> [String: String] {
        var values = environment
        switch kind {
        case .npm:
            values["NPM_CONFIG_REGISTRY"] = address
            values["npm_config_registry"] = address
        case .pnpm:
            values["PNPM_CONFIG_REGISTRY"] = address
            values["pnpm_config_registry"] = address
            values["NPM_CONFIG_REGISTRY"] = address
            values["npm_config_registry"] = address
        case .homebrew:
            values["HOMEBREW_API_DOMAIN"] = Self.homebrewAPIDomain(from: address)
            values["HOMEBREW_BOTTLE_DOMAIN"] = Self.homebrewBottleDomain(from: address)
        case .uv:
            values["UV_DEFAULT_INDEX"] = address
            values["UV_INDEX_URL"] = address
        }
        return values
    }

    private func commandPreamble(for executablePath: String) -> String {
        let executableDirectory = URL(fileURLWithPath: executablePath)
            .deletingLastPathComponent()
            .standardizedFileURL
            .path
        return """
        \(shellPreamble)
        export PATH=\(Self.singleQuoted(executableDirectory)):"$PATH"
        """
    }

    private var brewExecutablePath: String? {
        ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static func installMethod(
        for kind: PackageManagerKind,
        resolvedPath: String
    ) -> PackageManagerInstallMethod {
        if kind == .homebrew {
            return .homebrew
        }
        if resolvedPath.contains("/Cellar/") || resolvedPath.contains("/homebrew/opt/") {
            return .homebrew
        }
        if resolvedPath.contains("/.envpilot/tools/") {
            return .envPilot
        }
        if resolvedPath.contains("/.envpilot/runtimes/node/") {
            return .envPilotNode
        }
        if resolvedPath.lowercased().contains("/.pnpm/")
            || resolvedPath.lowercased().contains("/pnpm/global/")
            || resolvedPath.lowercased().contains("/library/pnpm/")
            || resolvedPath.lowercased().contains("/.local/share/pnpm/") {
            return .pnpm
        }
        if resolvedPath.contains("/node_modules/npm/") {
            return .npm
        }
        if kind == .uv,
           resolvedPath.contains("/.local/bin/") || resolvedPath.contains("/.cargo/bin/") {
            return .standalone
        }
        if kind == .pnpm {
            return .standalone
        }
        if resolvedPath.hasPrefix("/") {
            return .native
        }
        return .unknown
    }

    static func homebrewAPIDomain(from address: String) -> String {
        let trimmed = address.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return trimmed.lowercased().hasSuffix("/api") ? trimmed : "\(trimmed)/api"
    }

    static func homebrewBottleDomain(from address: String) -> String {
        let trimmed = address.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard trimmed.lowercased().hasSuffix("/api") else {
            return trimmed
        }
        return String(trimmed.dropLast(4))
    }

    static func fallbackExecutablePath(
        for kind: PackageManagerKind,
        environment: [String: String],
        selectedNodePath: String? = nil,
        home: String,
        fileManager: FileManager = .default
    ) -> String? {
        let envPilotNodeHome = Self.nonEmpty(environment["ENVPILOT_NODE_HOME"])
        let pnpmHome = Self.nonEmpty(environment["PNPM_HOME"])
        let directories: [String?]

        switch kind {
        case .npm, .pnpm:
            directories = [
                envPilotNodeHome.map { "\($0)/bin" },
                Self.nonEmpty(selectedNodePath).map { "\($0)/bin" },
                pnpmHome,
                "\(home)/Library/pnpm",
                "\(home)/.local/share/pnpm",
                "\(home)/.npm-global/bin",
                "/opt/homebrew/bin",
                "/usr/local/bin",
            ]
        case .homebrew:
            directories = ["/opt/homebrew/bin", "/usr/local/bin"]
        case .uv:
            directories = [
                "\(home)/.envpilot/tools",
                "\(home)/.local/bin",
                "\(home)/.cargo/bin",
                "/opt/homebrew/bin",
                "/usr/local/bin",
            ]
        }

        var seen: Set<String> = []
        for directory in directories.compactMap({ $0 }) {
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

    /// 把 `kind` 在独立安装目录里的伴随二进制移到废纸篓，返回实际处理的路径。
    ///
    /// 以前是 `try? fileManager.removeItem`：错误被吞掉，用户也完全不知道自己的
    /// `pnpm`/`uvx` 被删了。现在优先移到「废纸篓」（用户可恢复），并把移走的路径返回给
    /// 调用方拼进成功提示里。
    @discardableResult
    static func removeStandaloneInstallation(
        for kind: PackageManagerKind,
        currentPath: String?,
        managedPath: String?,
        home: String,
        fileManager: FileManager = .default
    ) -> [String] {
        guard let currentPath, let managedPath, currentPath != managedPath else {
            return []
        }

        let homeURL = URL(fileURLWithPath: home, isDirectory: true).standardizedFileURL
        let currentURL = URL(fileURLWithPath: currentPath).standardizedFileURL
        let standaloneDirectories = [
            homeURL.appendingPathComponent(".local/bin", isDirectory: true).standardizedFileURL.path,
            homeURL.appendingPathComponent(".cargo/bin", isDirectory: true).standardizedFileURL.path,
        ]
        guard standaloneDirectories.contains(currentURL.deletingLastPathComponent().path) else {
            return []
        }

        let companionNames: [String]
        switch kind {
        case .pnpm:
            companionNames = ["pnpm", "pnpx"]
        case .uv:
            companionNames = ["uv", "uvx"]
        case .npm, .homebrew:
            return []
        }

        var trashed: [String] = []
        for name in companionNames {
            let path = currentURL.deletingLastPathComponent().appendingPathComponent(name)
            guard fileManager.fileExists(atPath: path.path) else {
                continue
            }
            do {
                try fileManager.trashItem(at: path, resultingItemURL: nil)
                trashed.append(path.path)
            } catch {
                // 没有可用废纸篓（外置卷、无 GUI 会话）时退化为删除：
                // 否则「切换到 ENVPilot 安装」会留下两个同名命令，反而更糟。
                if (try? fileManager.removeItem(at: path)) != nil {
                    trashed.append(path.path)
                }
            }
        }
        return trashed
    }

    /// 把「旧独立安装被移到废纸篓」变成一句用户能看到的补充说明。
    static func cleanupNotice(forTrashedPaths paths: [String]) -> String? {
        guard !paths.isEmpty else {
            return nil
        }
        let names = paths.map { URL(fileURLWithPath: $0).lastPathComponent }
        return "原独立安装已移到废纸篓：\(names.joined(separator: "、"))。"
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

    private static func executable(
        named name: String,
        in directories: [String],
        fileManager: FileManager = .default
    ) -> String? {
        for directory in directories {
            let path = URL(fileURLWithPath: directory, isDirectory: true)
                .appendingPathComponent(name)
                .standardizedFileURL
                .path
            if isExecutableFile(path, fileManager: fileManager) {
                return path
            }
        }
        return nil
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

/// 一次用户操作内的探测缓存。
///
/// `install` / `update` / `switchToEnvPilot` 以前在操作前后各调一次 `status(for:)`，
/// 每次都要重新跑 `zsh -lc command -v`、读配置、列目录，并为同一个 kind 再打一遍
/// 「最新版本」网络请求。把路径表和已经查到的最新版本在操作开始时算一次、之后复用，
/// 一次操作就只剩一次全量探测。
///
/// 操作本身是顺序执行的，用锁只是为了让这个 `@Sendable` 世界里的小盒子无懈可击。
private final class DetectionCache: @unchecked Sendable {
    private let lock = NSLock()
    private var executablePaths: [PackageManagerKind: String]?
    /// 值类型是 `String?`：`nil` 表示「查过但上游没有版本」，所以另用集合标记是否查过。
    private var latestVersions: [PackageManagerKind: String?] = [:]
    private var queriedLatestVersions: Set<PackageManagerKind> = []

    func cachedExecutablePaths() -> [PackageManagerKind: String]? {
        lock.lock()
        defer { lock.unlock() }
        return executablePaths
    }

    func storeExecutablePaths(_ paths: [PackageManagerKind: String]) {
        lock.lock()
        executablePaths = paths
        lock.unlock()
    }

    /// 安装/切换命令会改变磁盘上的可执行文件，重算前必须作废旧路径表。
    func invalidateExecutablePaths() {
        lock.lock()
        executablePaths = nil
        lock.unlock()
    }

    func cachedLatestVersion(for kind: PackageManagerKind) -> (found: Bool, value: String?) {
        lock.lock()
        defer { lock.unlock() }
        guard queriedLatestVersions.contains(kind) else {
            return (false, nil)
        }
        return (true, latestVersions[kind] ?? nil)
    }

    func storeLatestVersion(_ version: String?, for kind: PackageManagerKind) {
        lock.lock()
        queriedLatestVersions.insert(kind)
        latestVersions[kind] = version
        lock.unlock()
    }
}

/// 输出去重器。
///
/// `brew install` / `npm install` 会打出成百上千行，`updateStage(from:)` 对同一阶段
/// 反复命中；以前每一行都会回调 `progress`，App 层再为每一行跳一次主线程。这里只在
/// 阶段真正变化时上报。闭包是 `@Sendable`，stdout/stderr 两个读线程可能并发调用，
/// 所以用锁保护。
private final class StageDeduplicator: @unchecked Sendable {
    private let lock = NSLock()
    private let progress: (@Sendable (AIEnvironmentUpdateStage) -> Void)?
    private var lastStage: AIEnvironmentUpdateStage?

    init(progress: (@Sendable (AIEnvironmentUpdateStage) -> Void)?) {
        self.progress = progress
    }

    func emit(from output: String) {
        guard let stage = LocalPackageManagerService.updateStage(from: output) else {
            return
        }
        lock.lock()
        guard lastStage != stage else {
            lock.unlock()
            return
        }
        lastStage = stage
        lock.unlock()
        progress?(stage)
    }
}
