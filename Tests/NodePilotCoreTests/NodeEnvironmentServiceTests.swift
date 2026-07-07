import XCTest
@testable import ENVPilotCore

final class NodeEnvironmentServiceTests: XCTestCase {
    func testSelectDefaultNodePersistsVersionAndPathWithoutExternalCommand() throws {
        let store = InMemoryStore(settings: AppSettings())
        let shell = MockShellRunner()
        let nodePath = "/Users/me/.envpilot/runtimes/node/20.11.1"
        let detector = MockDetector(
            installations: [
                NodeInstallation(
                    version: "20.11.1",
                    installPath: nodePath,
                    executablePath: "\(nodePath)/bin/node"
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
        XCTAssertEqual(snapshot.settings.selectedNodePath, nodePath)
        XCTAssertFalse(shell.commands.contains { $0.contains("nvm alias default") })
    }

    func testInstallNodeUsesManagedInstallerAndPersistsSelection() throws {
        let store = InMemoryStore(settings: AppSettings())
        let shell = MockShellRunner()
        let installer = MockInstaller()
        let detector = MockDetector(
            installations: [],
            activeVersion: nil,
            activeNodePath: nil
        )
        let service = NodeEnvironmentService(
            configStore: store,
            detector: detector,
            javaDetector: MockJavaDetector(),
            componentInstaller: installer,
            shellRunner: shell
        )

        let snapshot = try service.installNode(version: "20.11.1")

        XCTAssertEqual(snapshot.settings.selectedVersion, "20.11.1")
        XCTAssertEqual(snapshot.settings.selectedNodePath, "/Users/me/.envpilot/runtimes/node/20.11.1")
        XCTAssertEqual(installer.operations, ["install-node:20.11.1"])
        XCTAssertFalse(shell.commands.contains { $0.contains("nvm install") })
    }

    func testInstallNodeAcceptsMajorVersionSpec() throws {
        let store = InMemoryStore(settings: AppSettings())
        let shell = MockShellRunner()
        let installer = MockInstaller()
        let detector = MockDetector(
            installations: [],
            activeVersion: nil,
            activeNodePath: nil
        )
        let service = NodeEnvironmentService(
            configStore: store,
            detector: detector,
            javaDetector: MockJavaDetector(),
            componentInstaller: installer,
            shellRunner: shell
        )

        let snapshot = try service.installNode(version: "24")

        XCTAssertEqual(snapshot.settings.selectedVersion, "24")
        XCTAssertEqual(installer.operations, ["install-node:24"])
    }

    func testInstallNodeDoesNotUseExternalInstallerOrRosetta() throws {
        let store = InMemoryStore(settings: AppSettings())
        let shell = MockShellRunner()
        let detector = MockDetector(
            installations: [],
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

        let snapshot = try service.installNode(version: "14.21.3")

        XCTAssertEqual(snapshot.settings.selectedVersion, "14.21.3")
        XCTAssertFalse(shell.commands.contains { $0.contains("nvm install") })
        XCTAssertFalse(shell.executedLaunchCommands.contains { $0.contains("/usr/bin/arch -x86_64 /bin/zsh -lc") })
    }

    func testUninstallNodeClearsSelectionWhenRemovingSelectedVersion() throws {
        let nodePath = "/Users/me/.envpilot/runtimes/node/20.11.1"
        let store = InMemoryStore(settings: AppSettings(selectedVersion: "20.11.1", selectedNodePath: nodePath))
        let shell = MockShellRunner()
        let installer = MockInstaller()
        let detector = MockDetector(
            installations: [
                NodeInstallation(
                    version: "20.11.1",
                    installPath: nodePath,
                    executablePath: "\(nodePath)/bin/node"
                )
            ],
            activeVersion: "20.11.1",
            activeNodePath: "/Users/me/.nvm/versions/node/v20.11.1/bin/node"
        )
        let service = NodeEnvironmentService(
            configStore: store,
            detector: detector,
            javaDetector: MockJavaDetector(),
            componentInstaller: installer,
            shellRunner: shell
        )

        let snapshot = try service.uninstallNode(version: "20.11.1")

        XCTAssertNil(snapshot.settings.selectedVersion)
        XCTAssertNil(snapshot.settings.selectedNodePath)
        XCTAssertEqual(installer.operations, ["uninstall-node:20.11.1"])
        XCTAssertFalse(shell.commands.contains { $0.contains("nvm uninstall") })
    }

    func testLoadSnapshotDoesNotAutoInstallRuntimeManagerWhenMissing() throws {
        let store = InMemoryStore(settings: AppSettings())
        let installer = MockInstaller()
        let service = NodeEnvironmentService(
            configStore: store,
            detector: MockDetector(installations: [], activeVersion: nil, activeNodePath: nil),
            javaDetector: MockJavaDetector(),
            componentInstaller: installer,
            shellRunner: MockShellRunner()
        )

        _ = try service.loadSnapshot()

        XCTAssertEqual(installer.operations, [])
    }

    func testLoadSnapshotDoesNotAutoInstallRuntimeManagersWhenMissing() throws {
        let store = InMemoryStore(settings: AppSettings())
        let installer = MockInstaller()
        let service = NodeEnvironmentService(
            configStore: store,
            detector: MockDetector(installations: [], activeVersion: nil, activeNodePath: nil),
            javaDetector: MockJavaDetector(),
            componentInstaller: installer,
            shellRunner: MockShellRunner()
        )

        _ = try service.loadSnapshot()

        XCTAssertEqual(installer.operations, [])
    }

    func testLoadSnapshotDoesNotFailWhenRuntimeManagerInstallIsUnavailable() throws {
        let store = InMemoryStore(settings: AppSettings())
        let service = NodeEnvironmentService(
            configStore: store,
            detector: MockDetector(installations: [], activeVersion: "24.1.0", activeNodePath: "/usr/local/bin/node"),
            javaDetector: MockJavaDetector(),
            componentInstaller: FailingInstaller(),
            shellRunner: MockShellRunner()
        )

        let snapshot = try service.loadSnapshot()

        XCTAssertNil(snapshot.activeVersion)
        XCTAssertNil(snapshot.activeNodePath)
    }

    func testLoadSnapshotDeduplicatesNodeVersionsAndKeepsSelectedPath() throws {
        let selectedPath = "/Users/me/.envpilot/runtimes/node/24.15.0"
        let otherPath = "/Users/me/.envpilot/runtimes/node/24.15.0-copy"
        let store = InMemoryStore(settings: AppSettings(selectedVersion: "24.15.0", selectedNodePath: selectedPath))
        let service = NodeEnvironmentService(
            configStore: store,
            detector: MockDetector(
                installations: [
                    NodeInstallation(
                        version: "24.15.0",
                        installPath: otherPath,
                        executablePath: "\(otherPath)/bin/node"
                    ),
                    NodeInstallation(
                        version: "24.15.0",
                        installPath: selectedPath,
                        executablePath: "\(selectedPath)/bin/node"
                    ),
                ],
                activeVersion: "24.15.0",
                activeNodePath: "\(otherPath)/bin/node"
            ),
            javaDetector: MockJavaDetector(),
            componentInstaller: MockInstaller(),
            shellRunner: MockShellRunner()
        )

        let snapshot = try service.loadSnapshot()

        XCTAssertEqual(snapshot.installations.map(\.version), ["24.15.0"])
        XCTAssertEqual(snapshot.installations.first?.installPath, selectedPath)
        XCTAssertEqual(store.settings.cachedNodeInstallations?.first?.installPath, selectedPath)
    }

    func testLoadSnapshotDeduplicatesNodeVersionsAndKeepsActivePathWhenUnselected() throws {
        let inactivePath = "/Users/me/.envpilot/runtimes/node/24.15.0"
        let activePath = "/Users/me/.envpilot/runtimes/node/24.15.0-active"
        let store = InMemoryStore(settings: AppSettings())
        let service = NodeEnvironmentService(
            configStore: store,
            detector: MockDetector(
                installations: [
                    NodeInstallation(
                        version: "24.15.0",
                        installPath: inactivePath,
                        executablePath: "\(inactivePath)/bin/node"
                    ),
                    NodeInstallation(
                        version: "24.15.0",
                        installPath: activePath,
                        executablePath: "\(activePath)/bin/node"
                    ),
                ],
                activeVersion: "24.15.0",
                activeNodePath: "\(activePath)/bin/node"
            ),
            javaDetector: MockJavaDetector(),
            componentInstaller: MockInstaller(),
            shellRunner: MockShellRunner()
        )

        let snapshot = try service.loadSnapshot()

        XCTAssertEqual(snapshot.installations.map(\.version), ["24.15.0"])
        XCTAssertEqual(snapshot.installations.first?.installPath, activePath)
    }

    func testInstallJavaUsesManagedInstallerAndPersistsSelection() throws {
        let store = InMemoryStore(settings: AppSettings())
        let installer = MockInstaller()
        let javaHome = "/Users/me/.envpilot/runtimes/java/temurin-21.jdk/Contents/Home"
        let service = NodeEnvironmentService(
            configStore: store,
            detector: MockDetector(installations: [], activeVersion: nil, activeNodePath: nil),
            javaDetector: MockJavaDetector(
                installations: [JavaInstallation(version: "21.0.4", homePath: javaHome, isDefault: true)],
                activeVersion: "21.0.4",
                activeJavaHome: javaHome
            ),
            componentInstaller: installer,
            shellRunner: MockShellRunner()
        )

        let snapshot = try service.installJava(featureVersion: 21, progress: nil)

        XCTAssertEqual(installer.operations, ["install-java:21"])
        XCTAssertEqual(snapshot.settings.selectedJavaVersion, "21.0.0")
        XCTAssertEqual(snapshot.settings.selectedJavaHome, javaHome)
        XCTAssertEqual(snapshot.activeJavaVersion, "21.0.4")
        XCTAssertEqual(snapshot.activeJavaHome, javaHome)
    }

    func testSelectDefaultJavaPersistsHomeWithoutExternalCommand() throws {
        let store = InMemoryStore(settings: AppSettings())
        let javaHome = "/Users/me/.envpilot/runtimes/java/temurin-17.jdk/Contents/Home"
        let installer = MockInstaller()
        let service = NodeEnvironmentService(
            configStore: store,
            detector: MockDetector(installations: [], activeVersion: nil, activeNodePath: nil),
            javaDetector: MockJavaDetector(
                installations: [JavaInstallation(version: "17.0.16", homePath: javaHome)],
                activeVersion: "17.0.16",
                activeJavaHome: javaHome
            ),
            componentInstaller: installer,
            shellRunner: MockShellRunner()
        )

        let snapshot = try service.selectDefaultJava(version: "17.0.16", homePath: javaHome)

        XCTAssertEqual(installer.operations, [])
        XCTAssertEqual(snapshot.settings.selectedJavaVersion, "17.0.16")
        XCTAssertEqual(snapshot.settings.selectedJavaHome, javaHome)
    }

    func testListAvailableJavaVersionsUsesManagedInstaller() throws {
        let store = InMemoryStore(settings: AppSettings())
        let installer = MockInstaller()
        let service = NodeEnvironmentService(
            configStore: store,
            detector: MockDetector(installations: [], activeVersion: nil, activeNodePath: nil),
            javaDetector: MockJavaDetector(),
            componentInstaller: installer,
            shellRunner: MockShellRunner()
        )

        let candidates = try service.listAvailableJavaVersions()

        XCTAssertEqual(candidates.map(\.featureVersion), [21])
    }

    func testUninstallJavaUsesManagedInstallerAndClearsSelection() throws {
        let javaHome = "/Users/me/.envpilot/runtimes/java/temurin-17.jdk/Contents/Home"
        let store = InMemoryStore(settings: AppSettings(selectedJavaVersion: "17.0.16", selectedJavaHome: javaHome))
        let installer = MockInstaller()
        let service = NodeEnvironmentService(
            configStore: store,
            detector: MockDetector(installations: [], activeVersion: nil, activeNodePath: nil),
            javaDetector: MockJavaDetector(
                installations: [JavaInstallation(version: "17.0.16", homePath: javaHome)],
                activeVersion: nil,
                activeJavaHome: nil
            ),
            componentInstaller: installer,
            shellRunner: MockShellRunner()
        )

        let snapshot = try service.uninstallJava(homePath: javaHome, progress: nil)

        XCTAssertEqual(installer.operations, ["uninstall-java:\(javaHome)"])
        XCTAssertNil(snapshot.settings.selectedJavaVersion)
        XCTAssertNil(snapshot.settings.selectedJavaHome)
    }

    func testSelectDefaultNodeFailsWhenVersionNotInstalled() {
        let store = InMemoryStore(settings: AppSettings())
        let service = NodeEnvironmentService(
            configStore: store,
            detector: MockDetector(installations: [], activeVersion: nil, activeNodePath: nil),
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
    let installations: [JavaInstallation]
    let activeVersion: String?
    let activeJavaHome: String?

    init(
        installations: [JavaInstallation] = [],
        activeVersion: String? = nil,
        activeJavaHome: String? = nil
    ) {
        self.installations = installations
        self.activeVersion = activeVersion
        self.activeJavaHome = activeJavaHome
    }

    func detectInstallations() -> [JavaInstallation] { installations }
    func detectActiveVersion() -> String? { activeVersion }
    func detectActiveJavaHome() -> String? { activeJavaHome }
}

private final class MockInstaller: RuntimeComponentInstalling, @unchecked Sendable {
    private(set) var operations: [String] = []

    func listAvailableNodeVersions(ltsOnly: Bool) throws -> [NodeDownloadCandidate] {
        [NodeDownloadCandidate(version: "24.15.0", lts: nil)]
    }

    func installNode(version: String, progress: (@Sendable (String) -> Void)?) throws -> NodeInstallation {
        operations.append("install-node:\(version)")
        let normalized = NodeInstallationDetector.normalizeVersion(version) ?? version
        let installPath = "/Users/me/.envpilot/runtimes/node/\(normalized)"
        return NodeInstallation(version: normalized, installPath: installPath, executablePath: "\(installPath)/bin/node")
    }

    func uninstallManagedNode(installation: NodeInstallation) throws {
        operations.append("uninstall-node:\(installation.version)")
    }

    func listAvailableJavaVersions(ltsOnly: Bool) throws -> [JavaDownloadCandidate] {
        [
            JavaDownloadCandidate(
                featureVersion: 21,
                version: "21.0.4+7",
                vendor: "Temurin",
                packageName: "temurin-21.tar.gz",
                downloadURL: "https://example.invalid/temurin-21.tar.gz"
            )
        ]
    }

    func installJava(featureVersion: Int, progress: (@Sendable (String) -> Void)?) throws -> JavaInstallation {
        operations.append("install-java:\(featureVersion)")
        let homePath = "/Users/me/.envpilot/runtimes/java/temurin-\(featureVersion).jdk/Contents/Home"
        return JavaInstallation(version: "\(featureVersion).0.0", homePath: homePath)
    }

    func uninstallManagedJava(homePath: String) throws {
        operations.append("uninstall-java:\(homePath)")
    }
}

private struct FailingInstaller: RuntimeComponentInstalling {
    func listAvailableNodeVersions(ltsOnly: Bool) throws -> [NodeDownloadCandidate] {
        throw RuntimeComponentInstallerError.runtimeDownloadFailed(url: "node", message: "download failed")
    }

    func installNode(version: String, progress: (@Sendable (String) -> Void)?) throws -> NodeInstallation {
        throw RuntimeComponentInstallerError.runtimeDownloadFailed(url: "node", message: "download failed")
    }

    func uninstallManagedNode(installation: NodeInstallation) throws {
        throw RuntimeComponentInstallerError.runtimeNotInstalled(path: installation.installPath)
    }

    func listAvailableJavaVersions(ltsOnly: Bool) throws -> [JavaDownloadCandidate] {
        throw RuntimeComponentInstallerError.runtimeDownloadFailed(url: "java", message: "download failed")
    }

    func installJava(featureVersion: Int, progress: (@Sendable (String) -> Void)?) throws -> JavaInstallation {
        throw RuntimeComponentInstallerError.runtimeDownloadFailed(url: "java", message: "download failed")
    }

    func uninstallManagedJava(homePath: String) throws {
        throw RuntimeComponentInstallerError.runtimeNotInstalled(path: homePath)
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
    let installations: [NodeInstallation]
    let activeVersion: String?
    let activeNodePath: String?

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
