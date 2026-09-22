import XCTest
@testable import ENVPilotCore

final class PackageManagerServiceTests: XCTestCase {
    func testVersionParsingHandlesSupportedPackageManagerOutputs() {
        XCTAssertEqual(LocalPackageManagerService.version(from: "11.16.0\n"), "11.16.0")
        XCTAssertEqual(LocalPackageManagerService.version(from: "10.20.0"), "10.20.0")
        XCTAssertEqual(LocalPackageManagerService.version(from: "Homebrew 7.0.4"), "7.0.4")
        XCTAssertEqual(
            LocalPackageManagerService.version(from: "Homebrew 7.0.6-6-g1d86792"),
            "7.0.6-6-g1d86792"
        )
        XCTAssertEqual(LocalPackageManagerService.version(from: "uv 0.12.17"), "0.12.17")
        XCTAssertNil(LocalPackageManagerService.version(from: "version unavailable"))
    }

    func testHomebrewGitDescribeVersionDoesNotReportUpdateFromSameRelease() {
        let status = PackageManagerStatus(
            kind: .homebrew,
            executablePath: "/opt/homebrew/bin/brew",
            currentVersion: "7.0.6-6-g1d86792",
            latestVersion: "7.0.6",
            installMethod: .homebrew
        )

        XCTAssertFalse(status.updateAvailable)
    }

    func testAppSettingsDecodesLegacyPayloadWithoutPackageManagerMirrors() throws {
        let data = Data(#"{"selectedVersion":"22.17.0"}"#.utf8)
        let settings = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertEqual(settings.selectedVersion, "22.17.0")
        XCTAssertNil(settings.packageManagerMirrors.npm)
        XCTAssertNil(settings.packageManagerMirrors.pnpm)
        XCTAssertNil(settings.packageManagerMirrors.homebrew)
        XCTAssertNil(settings.packageManagerMirrors.uv)
    }

    func testPackageManagerMirrorsUseManagerSpecificEnvironment() {
        let npm = LocalPackageManagerService.environment(
            ["PATH": "/usr/bin"],
            applyingMirror: "https://registry.example.com",
            for: .npm
        )
        XCTAssertEqual(npm["NPM_CONFIG_REGISTRY"], "https://registry.example.com")
        XCTAssertEqual(npm["npm_config_registry"], "https://registry.example.com")

        let pnpm = LocalPackageManagerService.environment(
            ["PATH": "/usr/bin"],
            applyingMirror: "https://registry.example.com",
            for: .pnpm
        )
        XCTAssertEqual(pnpm["PNPM_CONFIG_REGISTRY"], "https://registry.example.com")
        XCTAssertEqual(pnpm["pnpm_config_registry"], "https://registry.example.com")
        XCTAssertEqual(pnpm["NPM_CONFIG_REGISTRY"], "https://registry.example.com")

        let homebrew = LocalPackageManagerService.environment(
            ["PATH": "/usr/bin"],
            applyingMirror: "https://mirrors.example.com/homebrew-bottles",
            for: .homebrew
        )
        XCTAssertEqual(
            homebrew["HOMEBREW_API_DOMAIN"],
            "https://mirrors.example.com/homebrew-bottles/api"
        )
        XCTAssertEqual(
            homebrew["HOMEBREW_BOTTLE_DOMAIN"],
            "https://mirrors.example.com/homebrew-bottles"
        )

        let uv = LocalPackageManagerService.environment(
            ["PATH": "/usr/bin"],
            applyingMirror: "https://pypi.example.com/simple",
            for: .uv
        )
        XCTAssertEqual(uv["UV_DEFAULT_INDEX"], "https://pypi.example.com/simple")
        XCTAssertEqual(uv["UV_INDEX_URL"], "https://pypi.example.com/simple")
        XCTAssertEqual(uv["PATH"], "/usr/bin")
    }

    func testInstallMethodDetection() {
        XCTAssertEqual(
            LocalPackageManagerService.installMethod(
                for: .npm,
                resolvedPath: "/Users/me/.envpilot/runtimes/node/24.18.0/bin/npm"
            ),
            .envPilotNode
        )
        XCTAssertEqual(
            LocalPackageManagerService.installMethod(
                for: .pnpm,
                resolvedPath: "/Users/me/Library/pnpm/global/5/node_modules/.pnpm/pnpm/bin/pnpm"
            ),
            .pnpm
        )
        XCTAssertEqual(
            LocalPackageManagerService.installMethod(
                for: .homebrew,
                resolvedPath: "/opt/homebrew/bin/brew"
            ),
            .homebrew
        )
        XCTAssertEqual(
            LocalPackageManagerService.installMethod(
                for: .uv,
                resolvedPath: "/Users/me/.local/bin/uv"
            ),
            .standalone
        )
        XCTAssertEqual(
            LocalPackageManagerService.installMethod(
                for: .uv,
                resolvedPath: "/Users/me/.envpilot/tools/uv"
            ),
            .envPilot
        )
    }

    func testInstallPlansDownloadAndValidateScriptsBeforeExecuting() {
        let npm = LocalPackageManagerService.installPlan(for: .npm)
        XCTAssertTrue(npm.displayCommand.contains("https://www.npmjs.com/install.sh"))
        XCTAssertTrue(npm.command.contains("curl -fsSL 'https://www.npmjs.com/install.sh'"))

        let pnpm = LocalPackageManagerService.installPlan(for: .pnpm)
        XCTAssertTrue(pnpm.displayCommand.contains("https://get.pnpm.io/install.sh"))

        let homebrew = LocalPackageManagerService.installPlan(for: .homebrew)
        XCTAssertTrue(
            homebrew.displayCommand.contains(
                "https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh"
            )
        )
        XCTAssertTrue(homebrew.command.contains("/bin/bash \"$installer\""))
        XCTAssertTrue(homebrew.command.contains("NONINTERACTIVE=1"))

        let uv = LocalPackageManagerService.installPlan(for: .uv)
        XCTAssertTrue(uv.displayCommand.contains("https://astral.sh/uv/install.sh"))

        // 核心回归：不再把远程内容直接管道给 shell，而是下载到临时文件、确认非空且像脚本。
        for plan in [npm, pnpm, homebrew, uv] {
            XCTAssertFalse(plan.command.contains("| sh"))
            XCTAssertFalse(plan.command.contains("| /bin/bash"))
            XCTAssertTrue(plan.command.contains("mktemp -t envpilot-installer"))
            XCTAssertTrue(plan.command.contains("trap 'rm -f \"$installer\"' EXIT"))
            XCTAssertTrue(plan.command.contains("[ -s \"$installer\" ]"))
            XCTAssertTrue(plan.command.contains("head -c 2 \"$installer\" | grep -q '#!'"))
        }
    }

    func testUpdatePlansUseBestAvailableCommand() throws {
        let npm = PackageManagerStatus(
            kind: .npm,
            executablePath: "/Users/me/.envpilot/runtimes/node/24.18.0/bin/npm",
            installMethod: .envPilotNode
        )
        XCTAssertEqual(
            try LocalPackageManagerService.updatePlan(for: npm, brewExecutable: nil).displayCommand,
            "npm install -g npm@latest"
        )

        let pnpm = PackageManagerStatus(
            kind: .pnpm,
            executablePath: "/Users/me/.local/bin/pnpm",
            installMethod: .standalone
        )
        XCTAssertEqual(
            try LocalPackageManagerService.updatePlan(for: pnpm, brewExecutable: nil).displayCommand,
            "pnpm self-update"
        )

        let homebrew = PackageManagerStatus(
            kind: .homebrew,
            executablePath: "/opt/homebrew/bin/brew",
            installMethod: .homebrew
        )
        XCTAssertEqual(
            try LocalPackageManagerService.updatePlan(
                for: homebrew,
                brewExecutable: "/opt/homebrew/bin/brew"
            ).displayCommand,
            "brew update"
        )

        let uv = PackageManagerStatus(
            kind: .uv,
            executablePath: "/Users/me/.local/bin/uv",
            installMethod: .standalone
        )
        XCTAssertEqual(
            try LocalPackageManagerService.updatePlan(for: uv, brewExecutable: nil).displayCommand,
            "uv self update"
        )
    }

    func testHomebrewManagedToolUpdatesThroughBrew() throws {
        let status = PackageManagerStatus(
            kind: .uv,
            executablePath: "/opt/homebrew/bin/uv",
            installMethod: .homebrew
        )

        let plan = try LocalPackageManagerService.updatePlan(
            for: status,
            brewExecutable: "/opt/homebrew/bin/brew"
        )

        XCTAssertEqual(plan.displayCommand, "brew upgrade uv")
        XCTAssertTrue(plan.command.contains("upgrade 'uv'"))
    }

    func testSwitchToEnvPilotAvailability() {
        let standalonePNPM = PackageManagerStatus(
            kind: .pnpm,
            executablePath: "/Users/me/.local/bin/pnpm",
            installMethod: .standalone
        )
        XCTAssertTrue(standalonePNPM.canSwitchToEnvPilot)

        let managedPNPM = PackageManagerStatus(
            kind: .pnpm,
            executablePath: "/Users/me/.envpilot/runtimes/node/24.18.0/bin/pnpm",
            installMethod: .envPilotNode
        )
        XCTAssertFalse(managedPNPM.canSwitchToEnvPilot)

        let standaloneUV = PackageManagerStatus(
            kind: .uv,
            executablePath: "/Users/me/.local/bin/uv",
            installMethod: .standalone
        )
        XCTAssertTrue(standaloneUV.canSwitchToEnvPilot)

        let managedUV = PackageManagerStatus(
            kind: .uv,
            executablePath: "/Users/me/.envpilot/tools/uv",
            installMethod: .envPilot
        )
        XCTAssertFalse(managedUV.canSwitchToEnvPilot)
    }

    func testSwitchToEnvPilotPlansInstallLatestManagedVersion() throws {
        let pnpmPlan = try LocalPackageManagerService.switchToEnvPilotPlan(
            for: .pnpm,
            managedNPMPath: "/Users/me/.envpilot/runtimes/node/24.18.0/bin/npm"
        )
        XCTAssertEqual(pnpmPlan.displayCommand, "npm install -g pnpm@latest")
        XCTAssertTrue(pnpmPlan.command.contains("install --global pnpm@latest"))

        let uvPlan = try LocalPackageManagerService.switchToEnvPilotPlan(
            for: .uv,
            managedNPMPath: nil
        )
        XCTAssertTrue(uvPlan.displayCommand.contains("https://astral.sh/uv/install.sh"))
        XCTAssertTrue(uvPlan.command.contains("UV_INSTALL_DIR=\"$HOME/.envpilot/tools\""))
        XCTAssertTrue(uvPlan.command.contains("UV_NO_MODIFY_PATH=1"))
        XCTAssertTrue(uvPlan.command.contains("sh \"$installer\""))
    }

    func testFallbackExecutableDiscoveryFindsStandaloneUV() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let home = root.appendingPathComponent("home", isDirectory: true)
        let executable = home
            .appendingPathComponent(".local/bin", isDirectory: true)
            .appendingPathComponent("uv")
        try FileManager.default.createDirectory(
            at: executable.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        XCTAssertTrue(FileManager.default.createFile(atPath: executable.path, contents: Data()))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)

        let resolved = LocalPackageManagerService.fallbackExecutablePath(
            for: .uv,
            environment: ["HOME": home.path, "PATH": "/usr/bin:/bin"],
            home: home.path
        )

        XCTAssertEqual(resolved, executable.path)
    }

    func testFallbackExecutableDiscoveryFindsEnvPilotManagedUV() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let home = root.appendingPathComponent("home", isDirectory: true)
        let executable = home
            .appendingPathComponent(".envpilot/tools", isDirectory: true)
            .appendingPathComponent("uv")
        try FileManager.default.createDirectory(
            at: executable.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        XCTAssertTrue(FileManager.default.createFile(atPath: executable.path, contents: Data()))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)

        let resolved = LocalPackageManagerService.fallbackExecutablePath(
            for: .uv,
            environment: ["HOME": home.path, "PATH": "/usr/bin:/bin"],
            home: home.path
        )

        XCTAssertEqual(resolved, executable.path)
    }

    func testSwitchCleanupTrashesStandaloneUVAndPNPMBins() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let home = root.appendingPathComponent("home", isDirectory: true)
        let bin = home.appendingPathComponent(".local/bin", isDirectory: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)

        let uv = bin.appendingPathComponent("uv")
        let uvx = bin.appendingPathComponent("uvx")
        let pnpm = bin.appendingPathComponent("pnpm")
        let pnpx = bin.appendingPathComponent("pnpx")
        for url in [uv, uvx, pnpm, pnpx] {
            XCTAssertTrue(FileManager.default.createFile(atPath: url.path, contents: Data()))
        }

        let fileManager = RecordingTrashFileManager()
        let trashedUV = LocalPackageManagerService.removeStandaloneInstallation(
            for: .uv,
            currentPath: uv.path,
            managedPath: home.appendingPathComponent(".envpilot/tools/uv").path,
            home: home.path,
            fileManager: fileManager
        )
        let trashedPNPM = LocalPackageManagerService.removeStandaloneInstallation(
            for: .pnpm,
            currentPath: pnpm.path,
            managedPath: home.appendingPathComponent(".envpilot/runtimes/node/24.18.0/bin/pnpm").path,
            home: home.path,
            fileManager: fileManager
        )

        // 被处理的是「移到废纸篓」，不是一个被吞掉错误的删除。
        XCTAssertEqual(Set(trashedUV), Set([uv.path, uvx.path]))
        XCTAssertEqual(Set(trashedPNPM), Set([pnpm.path, pnpx.path]))
        XCTAssertEqual(Set(fileManager.trashedPaths), Set([uv.path, uvx.path, pnpm.path, pnpx.path]))
        XCTAssertFalse(FileManager.default.fileExists(atPath: uv.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: uvx.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: pnpm.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: pnpx.path))
    }

    func testCleanupKeepsFilesOutsideStandaloneDirectories() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let home = root.appendingPathComponent("home", isDirectory: true)
        let bin = home.appendingPathComponent("custom/bin", isDirectory: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let uv = bin.appendingPathComponent("uv")
        XCTAssertTrue(FileManager.default.createFile(atPath: uv.path, contents: Data()))

        let fileManager = RecordingTrashFileManager()
        let trashed = LocalPackageManagerService.removeStandaloneInstallation(
            for: .uv,
            currentPath: uv.path,
            managedPath: home.appendingPathComponent(".envpilot/tools/uv").path,
            home: home.path,
            fileManager: fileManager
        )

        XCTAssertTrue(trashed.isEmpty)
        XCTAssertTrue(fileManager.trashedPaths.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: uv.path))
    }

    func testCleanupNoticeListsTrashedCommandNames() {
        XCTAssertNil(LocalPackageManagerService.cleanupNotice(forTrashedPaths: []))
        XCTAssertEqual(
            LocalPackageManagerService.cleanupNotice(
                forTrashedPaths: ["/Users/me/.local/bin/pnpm", "/Users/me/.local/bin/pnpx"]
            ),
            "原独立安装已移到废纸篓：pnpm、pnpx。"
        )
    }

    func testUpdateResolvesExecutablePathsAndLatestVersionOncePerOperation() async throws {
        let runner = PackageManagerTestShellRunner()
        runner.resolveOutputs = ["npm\t/opt/fake/bin/npm\n"]
        let provider = CountingLatestVersionProvider()
        let service = LocalPackageManagerService(
            shellRunner: runner,
            latestVersionProvider: provider,
            environment: ["HOME": NSHomeDirectory(), "PATH": "/usr/bin:/bin"]
        )

        let status = try await service.update(.npm)

        XCTAssertEqual(status.currentVersion, "11.16.0")
        XCTAssertEqual(status.latestVersion, "11.17.0")
        // 更新前后共用同一份路径表与同一次「最新版本」请求。
        XCTAssertEqual(runner.commands.filter { $0.contains("command -v") }.count, 1)
        XCTAssertEqual(provider.requestedKinds, [.npm])
    }

    func testUpdateDeduplicatesRepeatedOutputStages() async throws {
        let runner = PackageManagerTestShellRunner()
        // 保证任何机器上都能解析出 npm，测试不依赖本机装了什么。
        runner.resolveOutputs = ["npm\t/opt/fake/bin/npm\n"]
        // 更新命令一定带 PATH 前缀；`--version` 探测不算，避免把探测输出也当成安装进度。
        runner.streamingFragments = [
            "export PATH=": Array(repeating: "Downloading package\n", count: 40),
        ]
        runner.streamingExclusions = ["--version"]
        let service = LocalPackageManagerService(
            shellRunner: runner,
            latestVersionProvider: CountingLatestVersionProvider(),
            environment: ["HOME": NSHomeDirectory(), "PATH": "/usr/bin:/bin"]
        )
        let recorder = StageRecorder()

        _ = try await service.update(.npm, cancellation: nil) { stage in
            recorder.append(stage)
        }

        // 40 行相同的 "Downloading" 只上报一次：
        // connecting / fetchingPackage / installing / 输出去重后的一次 fetchingPackage / verifying
        XCTAssertEqual(
            recorder.stages,
            [.connecting, .fetchingPackage, .installing, .fetchingPackage, .verifying]
        )
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

/// 把 `trashItem` 记下来再真正删除，测试就不会往用户真实的废纸篓里丢文件。
private final class RecordingTrashFileManager: FileManager {
    private let lock = NSLock()
    private(set) var trashedPaths: [String] = []

    override func trashItem(
        at url: URL,
        resultingItemURL outResultingURL: AutoreleasingUnsafeMutablePointer<NSURL?>?
    ) throws {
        lock.lock()
        trashedPaths.append(url.path)
        lock.unlock()
        try removeItem(at: url)
    }
}

/// 可编排的 shell 替身：`command -v` 扫描按队列返回路径，其余命令成功。
private final class PackageManagerTestShellRunner: ShellCommandRunning, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var commands: [String] = []
    /// 依次返回的 `command -v` 扫描结果；用完之后一直沿用最后一个。
    var resolveOutputs: [String] = []
    /// 命令包含 key 时把 value 逐行喂给 onOutput（用来验证阶段去重）。
    var streamingFragments: [String: [String]] = [:]
    /// 命中其中任一子串时不流式输出（例如版本探测）。
    var streamingExclusions: [String] = []

    func run(
        _ launchPath: String,
        arguments: [String],
        environment: [String: String]
    ) throws -> ShellCommandResult {
        ShellCommandResult(standardOutput: "", standardError: "", exitCode: 0)
    }

    func runShell(_ command: String, environment: [String: String]) throws -> ShellCommandResult {
        record(command, onOutput: nil)
    }

    func runShell(
        _ command: String,
        environment: [String: String],
        onOutput: (@Sendable (String) -> Void)?
    ) throws -> ShellCommandResult {
        record(command, onOutput: onOutput)
    }

    private func record(
        _ command: String,
        onOutput: (@Sendable (String) -> Void)?
    ) -> ShellCommandResult {
        lock.lock()
        commands.append(command)
        let resolveOutput: String?
        if command.contains("command -v") {
            resolveOutput = resolveOutputs.isEmpty ? nil : resolveOutputs.removeFirst()
        } else {
            resolveOutput = nil
        }
        let isExcluded = streamingExclusions.contains { command.contains($0) }
        let streaming = isExcluded ? nil : streamingFragments.first { command.contains($0.key) }?.value
        lock.unlock()

        if let streaming {
            for line in streaming {
                onOutput?(line)
            }
        }
        if let resolveOutput {
            return ShellCommandResult(standardOutput: resolveOutput, standardError: "", exitCode: 0)
        }
        if command.contains("--version") {
            return ShellCommandResult(standardOutput: "11.16.0\n", standardError: "", exitCode: 0)
        }
        return ShellCommandResult(standardOutput: "", standardError: "", exitCode: 0)
    }
}

private final class CountingLatestVersionProvider: PackageManagerLatestVersionProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var kinds: [PackageManagerKind] = []

    var requestedKinds: [PackageManagerKind] {
        lock.lock()
        defer { lock.unlock() }
        return kinds
    }

    func latestVersion(
        for kind: PackageManagerKind,
        registryURL: URL?
    ) async throws -> String? {
        lock.withLock {
            kinds.append(kind)
        }
        return "11.17.0"
    }
}

private final class StageRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [AIEnvironmentUpdateStage] = []

    var stages: [AIEnvironmentUpdateStage] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    func append(_ stage: AIEnvironmentUpdateStage) {
        lock.lock()
        recorded.append(stage)
        lock.unlock()
    }
}
