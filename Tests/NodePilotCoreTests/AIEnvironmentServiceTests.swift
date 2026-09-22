import XCTest
@testable import ENVPilotCore

final class AIEnvironmentServiceTests: XCTestCase {
    func testVersionParsingHandlesSupportedCLIOutputs() {
        XCTAssertEqual(LocalAIEnvironmentService.version(from: "codex-cli 0.154.0"), "0.154.0")
        XCTAssertEqual(LocalAIEnvironmentService.version(from: "2.1.236 (Claude Code)"), "2.1.236")
        XCTAssertEqual(LocalAIEnvironmentService.version(from: "0.86.1\n"), "0.86.1")
        XCTAssertEqual(LocalAIEnvironmentService.version(from: "opencode 1.18.32"), "1.18.32")
        XCTAssertNil(LocalAIEnvironmentService.version(from: "version unavailable"))
    }

    func testInstallMethodDetection() {
        XCTAssertEqual(
            LocalAIEnvironmentService.installMethod(
                for: .codex,
                resolvedPath: "/opt/homebrew/Caskroom/codex/0.154.0/bin/codex"
            ),
            .homebrewCask("codex")
        )
        XCTAssertEqual(
            LocalAIEnvironmentService.installMethod(
                for: .openCode,
                resolvedPath: "/opt/homebrew/Cellar/opencode/1.18.32/bin/opencode"
            ),
            .homebrewFormula("opencode")
        )
        XCTAssertEqual(
            LocalAIEnvironmentService.installMethod(
                for: .pi,
                resolvedPath: "/Users/me/.envpilot/runtimes/node/24.18.0/lib/node_modules/@earendil-works/pi-coding-agent/dist/bundle/cli.js"
            ),
            .envPilotNode
        )
        XCTAssertEqual(
            LocalAIEnvironmentService.installMethod(
                for: .pi,
                resolvedPath: "/Users/me/.npm-global/lib/node_modules/@earendil-works/pi-coding-agent/dist/bundle/cli.js"
            ),
            .npm
        )
        XCTAssertEqual(
            LocalAIEnvironmentService.installMethod(
                for: .pi,
                resolvedPath: "/Users/me/Library/pnpm/global/5/node_modules/.pnpm/@earendil-works+pi-coding-agent@0.87.0/node_modules/@earendil-works/pi-coding-agent/dist/bundle/cli.js"
            ),
            .pnpm
        )
    }

    func testInstallMethodLabelsMatchPackageManagers() {
        XCTAssertEqual(AIEnvironmentInstallMethod.homebrewCask("codex").label, "Homebrew Cask")
        XCTAssertEqual(AIEnvironmentInstallMethod.homebrewFormula("opencode").label, "Homebrew")
        XCTAssertEqual(AIEnvironmentInstallMethod.envPilotNode.label, "ENVPilot Node")
        XCTAssertEqual(AIEnvironmentInstallMethod.npm.label, "npm")
        XCTAssertEqual(AIEnvironmentInstallMethod.pnpm.label, "pnpm")
    }

    func testSwitchToEnvPilotAvailability() {
        let native = AIEnvironmentStatus(
            kind: .codex,
            executablePath: "/usr/local/bin/codex",
            installMethod: .native
        )
        XCTAssertTrue(native.canSwitchToEnvPilot)

        let managed = AIEnvironmentStatus(
            kind: .codex,
            executablePath: "/Users/me/.envpilot/runtimes/node/24.18.0/bin/codex",
            installMethod: .envPilotNode
        )
        XCTAssertFalse(managed.canSwitchToEnvPilot)

        let missing = AIEnvironmentStatus(kind: .codex)
        XCTAssertFalse(missing.canSwitchToEnvPilot)
    }

    func testFallbackExecutableDiscoveryFindsPNPMGlobalBinOutsidePath() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let home = root.appendingPathComponent("home", isDirectory: true)
        let executable = home
            .appendingPathComponent("Library/pnpm", isDirectory: true)
            .appendingPathComponent("pi")
        try FileManager.default.createDirectory(
            at: executable.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        XCTAssertTrue(FileManager.default.createFile(atPath: executable.path, contents: Data()))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)

        let resolved = LocalAIEnvironmentService.fallbackExecutablePath(
            for: .pi,
            environment: ["HOME": home.path, "PATH": "/usr/bin:/bin"]
        )

        XCTAssertEqual(resolved, executable.path)
    }

    func testFallbackExecutableDiscoveryFindsENVPilotManagedNodeBinOutsidePath() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let home = root.appendingPathComponent("home", isDirectory: true)
        let executable = home
            .appendingPathComponent(".envpilot/runtimes/node/24.18.0/bin", isDirectory: true)
            .appendingPathComponent("pi")
        try FileManager.default.createDirectory(
            at: executable.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        XCTAssertTrue(FileManager.default.createFile(atPath: executable.path, contents: Data()))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)

        let resolved = LocalAIEnvironmentService.fallbackExecutablePath(
            for: .pi,
            environment: ["HOME": home.path, "PATH": "/usr/bin:/bin"]
        )

        XCTAssertEqual(resolved, executable.path)
    }

    func testManagedNodeToolRunsWithSiblingNodeOnPath() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let home = root.appendingPathComponent("home", isDirectory: true)
        let bin = home.appendingPathComponent(".envpilot/runtimes/node/24.18.0/bin", isDirectory: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)

        let node = bin.appendingPathComponent("node")
        try Data("#!/bin/sh\necho 0.87.0\n".utf8).write(to: node)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: node.path)

        let pi = bin.appendingPathComponent("pi")
        try Data("#!/usr/bin/env node\n".utf8).write(to: pi)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: pi.path)

        let service = LocalAIEnvironmentService(
            latestVersionProvider: NilLatestVersionProvider(),
            environment: [
                "HOME": home.path,
                "ENVPILOT_NODE_HOME": bin.deletingLastPathComponent().path,
                "PATH": "/usr/bin:/bin",
                "SHELL": "/bin/zsh",
            ]
        )

        let status = await service.loadStatuses().first { $0.kind == .pi }

        XCTAssertEqual(status?.executablePath, pi.path)
        XCTAssertEqual(status?.currentVersion, "0.87.0")
        XCTAssertNil(status?.errorMessage)
    }

    func testSwitchToEnvPilotInstallsIntoManagedNodeAndPrefersManagedExecutable() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let home = root.appendingPathComponent("home", isDirectory: true)
        let nodeHome = home
            .appendingPathComponent(".envpilot/runtimes/node/24.18.0", isDirectory: true)
        let bin = nodeHome.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)

        let npm = bin.appendingPathComponent("npm")
        try Data("#!/bin/sh\n".utf8).write(to: npm)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: npm.path)

        let managedCodex = bin.appendingPathComponent("codex")
        let externalCodex = "/usr/local/bin/codex"
        let runner = AIEnvironmentTestShellRunner { command in
            if command.contains("for tool in codex claude pi opencode") {
                return ShellCommandResult(
                    standardOutput: "codex\t\(externalCodex)\n",
                    standardError: "",
                    exitCode: 0
                )
            }
            if command.contains("--version") {
                let version = FileManager.default.isExecutableFile(atPath: managedCodex.path)
                    ? "codex-cli 0.155.1"
                    : "codex-cli 0.154.0"
                return ShellCommandResult(standardOutput: version, standardError: "", exitCode: 0)
            }
            if command.contains("install") && command.contains("@openai/codex") {
                FileManager.default.createFile(atPath: managedCodex.path, contents: Data("#!/bin/sh\n".utf8))
                try? FileManager.default.setAttributes(
                    [.posixPermissions: 0o755],
                    ofItemAtPath: managedCodex.path
                )
                return ShellCommandResult(standardOutput: "", standardError: "", exitCode: 0)
            }
            return ShellCommandResult(standardOutput: "", standardError: "", exitCode: 0)
        }
        let service = LocalAIEnvironmentService(
            shellRunner: runner,
            latestVersionProvider: NilLatestVersionProvider(),
            settingsStore: StubSettingsStore(
                settings: AppSettings(
                    selectedVersion: "24.18.0",
                    selectedNodePath: nodeHome.path
                )
            ),
            environment: [
                "HOME": home.path,
                "PATH": "/usr/bin:/bin",
                "SHELL": "/bin/zsh",
            ]
        )

        let initialStatuses = await service.loadStatuses()
        let initial = try XCTUnwrap(initialStatuses.first { $0.kind == .codex })
        XCTAssertEqual(initial.executablePath, externalCodex)
        XCTAssertTrue(initial.canSwitchToEnvPilot)

        let switched = try await service.switchToEnvPilot(.codex)

        XCTAssertEqual(switched.executablePath, managedCodex.path)
        XCTAssertEqual(switched.installMethod, .envPilotNode)
        XCTAssertEqual(switched.currentVersion, "0.155.1")
        XCTAssertTrue(runner.commands.contains { command in
            command.contains("'\(npm.path)' install --global '@openai/codex'")
        })
    }

    func testHomebrewUpdatePlanUsesPackageManager() {
        let status = AIEnvironmentStatus(
            kind: .codex,
            executablePath: "/opt/homebrew/bin/codex",
            currentVersion: "0.154.0",
            latestVersion: "0.155.1",
            installMethod: .homebrewCask("codex")
        )

        let plan = LocalAIEnvironmentService.updatePlan(
            for: status,
            brewExecutable: "/opt/homebrew/bin/brew"
        )

        XCTAssertEqual(plan.displayCommand, "brew upgrade --cask codex")
        XCTAssertTrue(plan.command.contains("upgrade --cask 'codex'"))
    }

    func testSelfUpdatePlansMatchEachTool() {
        let cases: [(AIEnvironmentStatus, String)] = [
            (
                AIEnvironmentStatus(
                    kind: .codex,
                    executablePath: "/usr/local/bin/codex",
                    installMethod: .native
                ),
                "codex update"
            ),
            (
                AIEnvironmentStatus(
                    kind: .claudeCode,
                    executablePath: "/usr/local/bin/claude",
                    installMethod: .native
                ),
                "claude update"
            ),
            (
                AIEnvironmentStatus(
                    kind: .pi,
                    executablePath: "/Users/me/.envpilot/runtimes/node/24.18.0/bin/pi",
                    installMethod: .envPilotNode
                ),
                "pi update pi"
            ),
            (
                AIEnvironmentStatus(
                    kind: .pi,
                    executablePath: "/Users/me/Library/pnpm/pi",
                    installMethod: .pnpm
                ),
                "pi update pi"
            ),
            (
                AIEnvironmentStatus(
                    kind: .openCode,
                    executablePath: "/usr/local/bin/opencode",
                    installMethod: .native
                ),
                "opencode upgrade"
            ),
        ]

        for (status, expected) in cases {
            let plan = LocalAIEnvironmentService.updatePlan(for: status, brewExecutable: nil)
            XCTAssertEqual(plan.displayCommand, expected)
        }
    }

    func testInstallPlansUseGlobalNPMOrPNPM() {
        let npmPlan = LocalAIEnvironmentService.installPlan(
            for: .openCode,
            packageManager: .npm("/Users/me/.envpilot/runtimes/node/24.18.0/bin/npm")
        )
        XCTAssertEqual(npmPlan.displayCommand, "npm install -g opencode-ai")
        XCTAssertTrue(npmPlan.command.contains("install --global 'opencode-ai'"))

        let pnpmPlan = LocalAIEnvironmentService.installPlan(
            for: .claudeCode,
            packageManager: .pnpm("/Users/me/Library/pnpm/pnpm")
        )
        XCTAssertEqual(pnpmPlan.displayCommand, "pnpm add -g @anthropic-ai/claude-code")
        XCTAssertTrue(pnpmPlan.command.contains("add --global '@anthropic-ai/claude-code'"))
    }

    func testUpdateAvailabilityUsesSemanticVersionComparison() {
        let status = AIEnvironmentStatus(
            kind: .codex,
            executablePath: "/opt/homebrew/bin/codex",
            currentVersion: "0.154.9",
            latestVersion: "0.154.10"
        )
        XCTAssertTrue(status.updateAvailable)

        let latest = AIEnvironmentStatus(
            kind: .codex,
            executablePath: "/opt/homebrew/bin/codex",
            currentVersion: "0.155.1",
            latestVersion: "0.155.1"
        )
        XCTAssertFalse(latest.updateAvailable)
    }

    func testUpdateStageParsingRecognisesPackageWork() {
        XCTAssertEqual(
            LocalAIEnvironmentService.updateStage(from: "==> Downloading https://example.com/codex.zip"),
            .fetchingPackage
        )
        XCTAssertEqual(
            LocalAIEnvironmentService.updateStage(from: "==> Installing Cask codex"),
            .installing
        )
        XCTAssertNil(LocalAIEnvironmentService.updateStage(from: "Updating Codex"))
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

private struct NilLatestVersionProvider: AIEnvironmentLatestVersionProviding {
    func latestVersion(for packageName: String) async throws -> String? {
        nil
    }
}

private final class StubSettingsStore: AppSettingsStoring, @unchecked Sendable {
    private let settings: AppSettings

    init(settings: AppSettings) {
        self.settings = settings
    }

    func load() throws -> AppSettings {
        settings
    }

    func save(_ settings: AppSettings) throws {}
}

private final class AIEnvironmentTestShellRunner: ShellCommandRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var recordedCommands: [String] = []
    private let handler: @Sendable (String) throws -> ShellCommandResult

    init(handler: @escaping @Sendable (String) throws -> ShellCommandResult) {
        self.handler = handler
    }

    var commands: [String] {
        lock.lock()
        defer { lock.unlock() }
        return recordedCommands
    }

    func run(
        _ launchPath: String,
        arguments: [String],
        environment: [String: String]
    ) throws -> ShellCommandResult {
        try handler(([launchPath] + arguments).joined(separator: " "))
    }

    func runShell(_ command: String, environment: [String: String]) throws -> ShellCommandResult {
        lock.lock()
        recordedCommands.append(command)
        lock.unlock()
        return try handler(command)
    }
}
