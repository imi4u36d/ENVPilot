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

    func testInstallPlansUseOfficialInstallers() {
        XCTAssertEqual(
            LocalPackageManagerService.installPlan(for: .npm).displayCommand,
            "curl -qL https://www.npmjs.com/install.sh | sh"
        )
        XCTAssertEqual(
            LocalPackageManagerService.installPlan(for: .pnpm).displayCommand,
            "curl -fsSL https://get.pnpm.io/install.sh | sh -"
        )
        XCTAssertEqual(
            LocalPackageManagerService.installPlan(for: .homebrew).displayCommand,
            "Homebrew 官方安装脚本"
        )
        XCTAssertEqual(
            LocalPackageManagerService.installPlan(for: .uv).displayCommand,
            "curl -LsSf https://astral.sh/uv/install.sh | sh"
        )
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
        XCTAssertEqual(uvPlan.displayCommand, "将 uv 最新版安装到 ENVPilot 目录")
        XCTAssertTrue(uvPlan.command.contains("UV_INSTALL_DIR=\"$HOME/.envpilot/tools\""))
        XCTAssertTrue(uvPlan.command.contains("UV_NO_MODIFY_PATH=1"))
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

    func testSwitchCleanupRemovesStandaloneUVAndPNPMBins() throws {
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

        LocalPackageManagerService.removeStandaloneInstallation(
            for: .uv,
            currentPath: uv.path,
            managedPath: home.appendingPathComponent(".envpilot/tools/uv").path,
            home: home.path
        )
        LocalPackageManagerService.removeStandaloneInstallation(
            for: .pnpm,
            currentPath: pnpm.path,
            managedPath: home.appendingPathComponent(".envpilot/runtimes/node/24.18.0/bin/pnpm").path,
            home: home.path
        )

        XCTAssertFalse(FileManager.default.fileExists(atPath: uv.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: uvx.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: pnpm.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: pnpx.path))
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
