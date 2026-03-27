import XCTest
@testable import ENVPilotCore

final class NodeEnvironmentServiceTests: XCTestCase {
    func testSelectDefaultNodePersistsVersionAndAppliesNVMCommand() throws {
        let store = InMemoryStore(settings: AppSettings())
        let shell = MockShellRunner()
        let detector = MockDetector(
            nvmInstalled: true,
            installations: [
                NodeInstallation(
                    version: "20.11.1",
                    installPath: "/Users/me/.nvm/versions/node/v20.11.1",
                    executablePath: "/Users/me/.nvm/versions/node/v20.11.1/bin/node"
                )
            ],
            activeVersion: "18.19.0",
            activeNodePath: "/Users/me/.nvm/versions/node/v18.19.0/bin/node"
        )
        let service = NodeEnvironmentService(
            configStore: store,
            detector: detector,
            javaDetector: MockJavaDetector(),
            componentInstaller: MockInstaller(),
            shellRunner: shell
        )

        let snapshot = try service.selectDefaultNode(version: "v20.11.1")

        XCTAssertEqual(snapshot.settings.selectedVersion, "20.11.1")
        XCTAssertTrue(shell.commands.contains { $0.contains("nvm alias default '20.11.1'") })
    }

    func testInstallNodeRunsNVMInstallAndPersistsSelection() throws {
        let store = InMemoryStore(settings: AppSettings())
        let shell = MockShellRunner()
        let detector = MockDetector(
            nvmInstalled: true,
            installations: [
                NodeInstallation(
                    version: "20.11.1",
                    installPath: "/Users/me/.nvm/versions/node/v20.11.1",
                    executablePath: "/Users/me/.nvm/versions/node/v20.11.1/bin/node"
                )
            ],
            activeVersion: nil,
            activeNodePath: nil
        )
        let service = NodeEnvironmentService(
            configStore: store,
            detector: detector,
            javaDetector: MockJavaDetector(),
            componentInstaller: MockInstaller(),
            shellRunner: shell
        )

        let snapshot = try service.installNode(version: "20.11.1")

        XCTAssertEqual(snapshot.settings.selectedVersion, "20.11.1")
        XCTAssertTrue(shell.commands.contains { $0.contains("nvm install '20.11.1'") })
    }

    func testInstallNodeAcceptsMajorVersionAndPersistsResolvedVersion() throws {
        let store = InMemoryStore(settings: AppSettings())
        let shell = MockShellRunner(outputsByCommandFragment: [
            "nvm install '24'": .init(
                standardOutput: "Now using node v24.11.1 (npm v11.6.2)\nv24.11.1\n",
                standardError: "",
                exitCode: 0
            )
        ])
        let detector = MockDetector(
            nvmInstalled: true,
            installations: [
                NodeInstallation(
                    version: "24.11.1",
                    installPath: "/Users/me/.nvm/versions/node/v24.11.1",
                    executablePath: "/Users/me/.nvm/versions/node/v24.11.1/bin/node"
                )
            ],
            activeVersion: "24.11.1",
            activeNodePath: "/Users/me/.nvm/versions/node/v24.11.1/bin/node"
        )
        let service = NodeEnvironmentService(
            configStore: store,
            detector: detector,
            javaDetector: MockJavaDetector(),
            componentInstaller: MockInstaller(),
            shellRunner: shell
        )

        let snapshot = try service.installNode(version: "24")

        XCTAssertEqual(snapshot.settings.selectedVersion, "24.11.1")
        XCTAssertTrue(shell.commands.contains { $0.contains("nvm install '24'") })
    }

    func testInstallNodeRetriesWithRosettaWhenArm64BinaryIsUnavailable() throws {
        let store = InMemoryStore(settings: AppSettings())
        let shell = MockShellRunner(
            outputsByCommandFragment: [
                "nvm install '14.21.3'": .init(
                    standardOutput: "",
                    standardError: """
                    Downloading https://nodejs.org/dist/v14.21.3/node-v14.21.3-darwin-arm64.tar.xz...
                    curl: (56) The requested URL returned error: 404
                    Binary download failed, trying source.
                    """,
                    exitCode: 3
                )
            ],
            outputsByRunCommandFragment: [
                "/usr/bin/arch -x86_64 /bin/zsh -lc": .init(
                    standardOutput: "Now using node v14.21.3 (npm v6.14.18)\nv14.21.3\n",
                    standardError: "",
                    exitCode: 0
                )
            ]
        )
        let detector = MockDetector(
            nvmInstalled: true,
            installations: [
                NodeInstallation(
                    version: "14.21.3",
                    installPath: "/Users/me/.nvm/versions/node/v14.21.3",
                    executablePath: "/Users/me/.nvm/versions/node/v14.21.3/bin/node"
                )
            ],
            activeVersion: "14.21.3",
            activeNodePath: "/Users/me/.nvm/versions/node/v14.21.3/bin/node"
        )
        let service = NodeEnvironmentService(
            configStore: store,
            detector: detector,
            javaDetector: MockJavaDetector(),
            componentInstaller: MockInstaller(),
            shellRunner: shell
        )

        let snapshot = try service.installNode(version: "14.21.3")

        XCTAssertEqual(snapshot.settings.selectedVersion, "14.21.3")
        XCTAssertTrue(shell.commands.contains { $0.contains("nvm install '14.21.3'") })
        XCTAssertTrue(shell.executedLaunchCommands.contains { $0.contains("/usr/bin/arch -x86_64 /bin/zsh -lc") })
    }

    func testUninstallNodeClearsSelectionWhenRemovingSelectedVersion() throws {
        let store = InMemoryStore(settings: AppSettings(selectedVersion: "20.11.1"))
        let shell = MockShellRunner()
        let detector = MockDetector(
            nvmInstalled: true,
            installations: [
                NodeInstallation(
                    version: "20.11.1",
                    installPath: "/Users/me/.nvm/versions/node/v20.11.1",
                    executablePath: "/Users/me/.nvm/versions/node/v20.11.1/bin/node"
                )
            ],
            activeVersion: "20.11.1",
            activeNodePath: "/Users/me/.nvm/versions/node/v20.11.1/bin/node"
        )
        let service = NodeEnvironmentService(
            configStore: store,
            detector: detector,
            javaDetector: MockJavaDetector(),
            componentInstaller: MockInstaller(),
            shellRunner: shell
        )

        let snapshot = try service.uninstallNode(version: "20.11.1")

        XCTAssertNil(snapshot.settings.selectedVersion)
        XCTAssertTrue(shell.commands.contains { $0.contains("nvm uninstall '20.11.1'") })
    }

    func testLoadSnapshotAutoInstallsNVMWhenMissing() throws {
        let store = InMemoryStore(settings: AppSettings())
        let installer = MockInstaller()
        let service = NodeEnvironmentService(
            configStore: store,
            detector: MockDetector(nvmInstalled: false, installations: [], activeVersion: nil, activeNodePath: nil),
            javaDetector: MockJavaDetector(),
            componentInstaller: installer,
            shellRunner: MockShellRunner()
        )

        _ = try service.loadSnapshot()

        XCTAssertEqual(installer.operations, ["install-nvm"])
    }

    func testLoadSnapshotAutoInstallsHomebrewThenNVMWhenBothMissing() throws {
        let store = InMemoryStore(settings: AppSettings())
        let installer = MockInstaller(homebrewInstalled: false)
        let service = NodeEnvironmentService(
            configStore: store,
            detector: MockDetector(nvmInstalled: false, installations: [], activeVersion: nil, activeNodePath: nil),
            javaDetector: MockJavaDetector(),
            componentInstaller: installer,
            shellRunner: MockShellRunner()
        )

        _ = try service.loadSnapshot()

        XCTAssertEqual(installer.operations, ["install-homebrew", "install-nvm"])
    }

    func testLoadSnapshotDoesNotFailWhenAutomaticNVMInstallFails() throws {
        let store = InMemoryStore(settings: AppSettings())
        let service = NodeEnvironmentService(
            configStore: store,
            detector: MockDetector(nvmInstalled: false, installations: [], activeVersion: "24.1.0", activeNodePath: "/usr/local/bin/node"),
            javaDetector: MockJavaDetector(),
            componentInstaller: FailingInstaller(),
            shellRunner: MockShellRunner()
        )

        let snapshot = try service.loadSnapshot()

        XCTAssertEqual(snapshot.activeVersion, "24.1.0")
        XCTAssertEqual(snapshot.activeNodePath, "/usr/local/bin/node")
    }

    func testSelectDefaultNodeFailsWhenVersionNotInstalled() {
        let store = InMemoryStore(settings: AppSettings())
        let service = NodeEnvironmentService(
            configStore: store,
            detector: MockDetector(nvmInstalled: true, installations: [], activeVersion: nil, activeNodePath: nil),
            javaDetector: MockJavaDetector(),
            componentInstaller: MockInstaller(),
            shellRunner: MockShellRunner()
        )

        XCTAssertThrowsError(try service.selectDefaultNode(version: "20.11.1")) { error in
            guard case NodeEnvironmentServiceError.nodeVersionNotInstalled(let version) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(version, "20.11.1")
        }
    }
}

private struct MockJavaDetector: JavaRuntimeDetecting {
    func detectInstallations() -> [JavaInstallation] { [] }
    func detectActiveVersion() -> String? { nil }
    func detectActiveJavaHome() -> String? { nil }
}

private final class MockInstaller: RuntimeComponentInstalling, @unchecked Sendable {
    private(set) var operations: [String] = []
    private var homebrewInstalled: Bool

    init(homebrewInstalled: Bool = true) {
        self.homebrewInstalled = homebrewInstalled
    }

    func isHomebrewInstalled() -> Bool {
        homebrewInstalled
    }

    func installHomebrew() throws {
        operations.append("install-homebrew")
        homebrewInstalled = true
    }

    func canInstallNVM() -> Bool {
        homebrewInstalled
    }

    func installNVM() throws {
        operations.append("install-nvm")
    }
}

private struct FailingInstaller: RuntimeComponentInstalling {
    func isHomebrewInstalled() -> Bool {
        false
    }

    func installHomebrew() throws {
        throw RuntimeComponentInstallerError.homebrewInstallFailed(message: "brew failed")
    }

    func canInstallNVM() -> Bool {
        false
    }

    func installNVM() throws {
        throw RuntimeComponentInstallerError.nvmInstallFailed(message: "nvm failed")
    }
}

private final class InMemoryStore: AppSettingsStoring, @unchecked Sendable {
    private(set) var settings: AppSettings

    init(settings: AppSettings) {
        self.settings = settings
    }

    func load() throws -> AppSettings {
        settings
    }

    func save(_ settings: AppSettings) throws {
        self.settings = settings
    }
}

private final class MockShellRunner: ShellCommandRunning, @unchecked Sendable {
    private(set) var commands: [String] = []
    private(set) var executedLaunchCommands: [String] = []
    private let outputsByCommandFragment: [String: ShellCommandResult]
    private let outputsByRunCommandFragment: [String: ShellCommandResult]

    init(
        outputsByCommandFragment: [String: ShellCommandResult] = [:],
        outputsByRunCommandFragment: [String: ShellCommandResult] = [:]
    ) {
        self.outputsByCommandFragment = outputsByCommandFragment
        self.outputsByRunCommandFragment = outputsByRunCommandFragment
    }

    func run(
        _ launchPath: String,
        arguments: [String],
        environment: [String: String]
    ) throws -> ShellCommandResult {
        let fullCommand = ([launchPath] + arguments).joined(separator: " ")
        commands.append(fullCommand)
        executedLaunchCommands.append(fullCommand)
        if let match = outputsByRunCommandFragment.first(where: { fullCommand.contains($0.key) }) {
            return match.value
        }
        return .init(standardOutput: "", standardError: "", exitCode: 0)
    }

    func runShell(_ command: String, environment: [String: String]) throws -> ShellCommandResult {
        commands.append(command)
        if let match = outputsByCommandFragment.first(where: { command.contains($0.key) }) {
            return match.value
        }
        return .init(standardOutput: "", standardError: "", exitCode: 0)
    }
}

private struct MockDetector: NodeInstallationDetecting {
    let nvmInstalled: Bool
    let installations: [NodeInstallation]
    let activeVersion: String?
    let activeNodePath: String?

    func isNVMInstalled() -> Bool {
        nvmInstalled
    }

    func detectInstallations() -> [NodeInstallation] {
        installations
    }

    func detectActiveVersion() -> String? {
        activeVersion
    }

    func detectActiveNodePath() -> String? {
        activeNodePath
    }
}
