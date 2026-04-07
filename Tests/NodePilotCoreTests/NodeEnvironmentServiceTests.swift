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

    func testLoadSnapshotIncludesSDKMANStatus() throws {
        let store = InMemoryStore(settings: AppSettings())
        let javaHome = "/Users/me/.sdkman/candidates/java/21.0.4-tem"
        let installer = MockInstaller(sdkmanInstalled: false, canInstallSDKMAN: true)
        let service = NodeEnvironmentService(
            configStore: store,
            detector: MockDetector(nvmInstalled: true, installations: [], activeVersion: nil, activeNodePath: nil),
            javaDetector: MockJavaDetector(
                installations: [JavaInstallation(version: "21.0.4", homePath: javaHome)],
                activeVersion: "21.0.4",
                activeJavaHome: javaHome
            ),
            componentInstaller: installer,
            shellRunner: MockShellRunner()
        )

        let snapshot = try service.loadSnapshot()

        XCTAssertEqual(snapshot.sdkmanStatus.isInstalled, false)
        XCTAssertEqual(snapshot.sdkmanStatus.canInstall, true)
        XCTAssertEqual(snapshot.sdkmanStatus.hasManagedJavaInstallations, true)
    }

    func testInstallJavaWithSDKMANAutoInstallsSDKMANAndDoesNotSetDefault() throws {
        let store = InMemoryStore(settings: AppSettings())
        let javaHome = "/Users/me/.sdkman/candidates/java/21.0.4-tem"
        let installer = MockInstaller(sdkmanInstalled: false, canInstallSDKMAN: true)
        let service = NodeEnvironmentService(
            configStore: store,
            detector: MockDetector(nvmInstalled: true, installations: [], activeVersion: nil, activeNodePath: nil),
            javaDetector: MockJavaDetector(
                installations: [JavaInstallation(version: "21.0.4", homePath: javaHome, isDefault: true)],
                activeVersion: "21.0.4",
                activeJavaHome: javaHome
            ),
            componentInstaller: installer,
            shellRunner: MockShellRunner()
        )

        let snapshot = try service.installJavaWithSDKMAN(identifier: "21.0.4-tem")

        XCTAssertEqual(installer.operations, [
            "install-sdkman",
            "install-sdkman-java:21.0.4-tem",
        ])
        XCTAssertNil(snapshot.settings.selectedJavaVersion)
        XCTAssertNil(snapshot.settings.selectedJavaHome)
        XCTAssertEqual(snapshot.activeJavaVersion, "21.0.4")
        XCTAssertEqual(snapshot.activeJavaHome, javaHome)
    }

    func testSelectDefaultJavaSyncsSDKMANDefaultWhenSDKMANHomeSelected() throws {
        let store = InMemoryStore(settings: AppSettings())
        let javaHome = "/Users/me/.sdkman/candidates/java/17.0.16-tem"
        let installer = MockInstaller(sdkmanInstalled: true)
        let service = NodeEnvironmentService(
            configStore: store,
            detector: MockDetector(nvmInstalled: true, installations: [], activeVersion: nil, activeNodePath: nil),
            javaDetector: MockJavaDetector(
                installations: [JavaInstallation(version: "17.0.16", homePath: javaHome)],
                activeVersion: "17.0.16",
                activeJavaHome: javaHome
            ),
            componentInstaller: installer,
            shellRunner: MockShellRunner()
        )

        let snapshot = try service.selectDefaultJava(version: "17.0.16", homePath: javaHome)

        XCTAssertTrue(installer.operations.contains("sdkman-default-java:17.0.16-tem"))
        XCTAssertEqual(snapshot.settings.selectedJavaVersion, "17.0.16")
        XCTAssertEqual(snapshot.settings.selectedJavaHome, javaHome)
    }

    func testListAvailableJavaCandidatesWithSDKMANMarksInstalledCandidates() throws {
        let store = InMemoryStore(settings: AppSettings())
        let javaHome = "/Users/me/.sdkman/candidates/java/17.0.16-tem"
        let installer = MockInstaller(
            sdkmanInstalled: true,
            availableJavaCandidates: [
                SDKMANJavaCandidate(vendor: "Temurin", version: "17.0.16", distribution: "tem", identifier: "17.0.16-tem"),
                SDKMANJavaCandidate(vendor: "Zulu", version: "21.0.10", distribution: "zulu", identifier: "21.0.10-zulu"),
            ]
        )
        let service = NodeEnvironmentService(
            configStore: store,
            detector: MockDetector(nvmInstalled: true, installations: [], activeVersion: nil, activeNodePath: nil),
            javaDetector: MockJavaDetector(
                installations: [JavaInstallation(version: "17.0.16", homePath: javaHome)],
                activeVersion: "17.0.16",
                activeJavaHome: javaHome
            ),
            componentInstaller: installer,
            shellRunner: MockShellRunner()
        )

        let candidates = try service.listAvailableJavaCandidatesWithSDKMAN()

        XCTAssertEqual(candidates.count, 2)
        XCTAssertEqual(candidates[0].isInstalled, true)
        XCTAssertEqual(candidates[1].isInstalled, false)
    }

    func testUninstallJavaWithSDKMANClearsSelectedJavaWhenRemovingSelectedIdentifier() throws {
        let javaHome = "/Users/me/.sdkman/candidates/java/17.0.16-tem"
        let store = InMemoryStore(settings: AppSettings(selectedJavaVersion: "17.0.16", selectedJavaHome: javaHome))
        let installer = MockInstaller(sdkmanInstalled: true)
        let service = NodeEnvironmentService(
            configStore: store,
            detector: MockDetector(nvmInstalled: true, installations: [], activeVersion: nil, activeNodePath: nil),
            javaDetector: MockJavaDetector(),
            componentInstaller: installer,
            shellRunner: MockShellRunner()
        )

        let snapshot = try service.uninstallJavaWithSDKMAN(identifier: "17.0.16-tem", progress: nil)

        XCTAssertTrue(installer.operations.contains("sdkman-uninstall-java:17.0.16-tem"))
        XCTAssertNil(snapshot.settings.selectedJavaVersion)
        XCTAssertNil(snapshot.settings.selectedJavaHome)
    }

    func testUninstallJavaWithSDKMANRetriesAfterSwitchingDefaultWhenTargetIsInUse() throws {
        let targetHome = "/Users/me/.sdkman/candidates/java/11.0.25-tem"
        let fallbackHome = "/Users/me/.sdkman/candidates/java/17.0.16-tem"
        let store = InMemoryStore(settings: AppSettings(selectedJavaVersion: "11.0.25", selectedJavaHome: targetHome))
        let installer = RetryingSDKMANInstaller(identifierToFailFirst: "11.0.25-tem")
        let service = NodeEnvironmentService(
            configStore: store,
            detector: MockDetector(nvmInstalled: true, installations: [], activeVersion: nil, activeNodePath: nil),
            javaDetector: MockJavaDetector(
                installations: [
                    JavaInstallation(version: "17.0.16", homePath: fallbackHome),
                    JavaInstallation(version: "11.0.25", homePath: targetHome),
                ],
                activeVersion: "17.0.16",
                activeJavaHome: fallbackHome
            ),
            componentInstaller: installer,
            shellRunner: MockShellRunner()
        )

        let snapshot = try service.uninstallJavaWithSDKMAN(identifier: "11.0.25-tem", progress: nil)

        XCTAssertEqual(
            installer.operations,
            [
                "sdkman-uninstall-java:11.0.25-tem",
                "sdkman-default-java:17.0.16-tem",
                "sdkman-uninstall-java:11.0.25-tem",
            ]
        )
        XCTAssertNil(snapshot.settings.selectedJavaVersion)
        XCTAssertNil(snapshot.settings.selectedJavaHome)
    }

    func testUninstallJavaWithSDKMANForcesRemovalWhenCurrentVersionAndNoFallbackExists() throws {
        let targetIdentifier = "11.0.30-tem"
        let targetHome = "/Users/me/.sdkman/candidates/java/\(targetIdentifier)"
        let store = InMemoryStore(settings: AppSettings(selectedJavaVersion: "11.0.30", selectedJavaHome: targetHome))
        let installer = ForceHintSDKMANInstaller(
            message: """
            Override with --force, but leaves the candidate unusable!
            java \(targetIdentifier) is the current version and should not be removed.
            """
        )
        let shell = MockShellRunner(
            outputsByCommandFragment: [
                "sdk uninstall java '\(targetIdentifier)' --force": .init(
                    standardOutput: "removed java \(targetIdentifier).",
                    standardError: "",
                    exitCode: 0
                )
            ]
        )
        let service = NodeEnvironmentService(
            configStore: store,
            detector: MockDetector(nvmInstalled: true, installations: [], activeVersion: nil, activeNodePath: nil),
            javaDetector: MockJavaDetector(
                installations: [JavaInstallation(version: "11.0.30", homePath: targetHome)],
                activeVersion: "11.0.30",
                activeJavaHome: targetHome
            ),
            componentInstaller: installer,
            shellRunner: shell
        )

        let snapshot = try service.uninstallJavaWithSDKMAN(identifier: targetIdentifier, progress: nil)

        XCTAssertEqual(installer.operations, ["sdkman-uninstall-java:\(targetIdentifier)"])
        XCTAssertTrue(shell.commands.contains { $0.contains("sdk uninstall java '\(targetIdentifier)' --force") })
        XCTAssertNil(snapshot.settings.selectedJavaVersion)
        XCTAssertNil(snapshot.settings.selectedJavaHome)
    }

    func testUninstallJavaUsesSDKMANPathWhenJavaIsSDKMANManaged() throws {
        let javaHome = "/Users/me/.sdkman/candidates/java/21.0.4-tem"
        let store = InMemoryStore(settings: AppSettings(selectedJavaVersion: "21.0.4", selectedJavaHome: javaHome))
        let installer = MockInstaller(sdkmanInstalled: true)
        let service = NodeEnvironmentService(
            configStore: store,
            detector: MockDetector(nvmInstalled: true, installations: [], activeVersion: nil, activeNodePath: nil),
            javaDetector: MockJavaDetector(
                installations: [JavaInstallation(version: "21.0.4", homePath: javaHome)],
                activeVersion: nil,
                activeJavaHome: nil
            ),
            componentInstaller: installer,
            shellRunner: MockShellRunner()
        )

        let snapshot = try service.uninstallJava(homePath: javaHome, progress: nil)

        XCTAssertTrue(installer.operations.contains("sdkman-uninstall-java:21.0.4-tem"))
        XCTAssertNil(snapshot.settings.selectedJavaVersion)
        XCTAssertNil(snapshot.settings.selectedJavaHome)
    }

    func testUninstallJavaRemovesNonSDKMANJDKBundleAndClearsSelection() throws {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let jdkBundle = tempRoot.appendingPathComponent("temurin-21.jdk", isDirectory: true)
        let javaHome = jdkBundle.appendingPathComponent("Contents/Home", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        try FileManager.default.createDirectory(at: javaHome, withIntermediateDirectories: true)

        let javaHomePath = javaHome.path
        let store = InMemoryStore(settings: AppSettings(selectedJavaVersion: "21.0.4", selectedJavaHome: javaHomePath))
        let service = NodeEnvironmentService(
            configStore: store,
            detector: MockDetector(nvmInstalled: true, installations: [], activeVersion: nil, activeNodePath: nil),
            javaDetector: MockJavaDetector(
                installations: [JavaInstallation(version: "21.0.4", homePath: javaHomePath)],
                activeVersion: nil,
                activeJavaHome: nil
            ),
            componentInstaller: MockInstaller(),
            shellRunner: MockShellRunner()
        )

        let snapshot = try service.uninstallJava(homePath: javaHomePath, progress: nil)

        XCTAssertFalse(FileManager.default.fileExists(atPath: jdkBundle.path))
        XCTAssertNil(snapshot.settings.selectedJavaVersion)
        XCTAssertNil(snapshot.settings.selectedJavaHome)
    }

    func testUninstallJavaFailsForUnsupportedNonSDKMANLocation() {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let javaHomeURL = tempRoot.appendingPathComponent("custom-jdk/Contents/Home", isDirectory: true)
        try? FileManager.default.createDirectory(at: javaHomeURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let javaHome = javaHomeURL.path
        let store = InMemoryStore(settings: AppSettings(selectedJavaVersion: "1.6.0", selectedJavaHome: javaHome))
        let service = NodeEnvironmentService(
            configStore: store,
            detector: MockDetector(nvmInstalled: true, installations: [], activeVersion: nil, activeNodePath: nil),
            javaDetector: MockJavaDetector(
                installations: [JavaInstallation(version: "1.6.0", homePath: javaHome)],
                activeVersion: nil,
                activeJavaHome: nil
            ),
            componentInstaller: MockInstaller(),
            shellRunner: MockShellRunner()
        )

        XCTAssertThrowsError(try service.uninstallJava(homePath: javaHome, progress: nil)) { error in
            guard case NodeEnvironmentServiceError.javaUninstallUnsupported(let path) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(path, javaHome)
        }
    }

    func testShouldUsePrivilegedJavaRemovalOnlyForSystemJDKPath() {
        let service = NodeEnvironmentService(
            configStore: InMemoryStore(settings: AppSettings()),
            detector: MockDetector(nvmInstalled: true, installations: [], activeVersion: nil, activeNodePath: nil),
            javaDetector: MockJavaDetector(),
            componentInstaller: MockInstaller(),
            shellRunner: MockShellRunner()
        )

        XCTAssertTrue(service.shouldUsePrivilegedJavaRemoval(path: "/Library/Java/JavaVirtualMachines/jdk-17.jdk"))
        XCTAssertFalse(service.shouldUsePrivilegedJavaRemoval(path: "/Users/me/.jdks/jdk-17.jdk"))
    }

    func testRunPrivilegedJavaUninstallUsesOsaScriptWithAdminPrivileges() throws {
        let shell = MockShellRunner(
            outputsByRunCommandFragment: [
                "/usr/bin/osascript -e": .init(standardOutput: "", standardError: "", exitCode: 0)
            ]
        )
        let service = NodeEnvironmentService(
            configStore: InMemoryStore(settings: AppSettings()),
            detector: MockDetector(nvmInstalled: true, installations: [], activeVersion: nil, activeNodePath: nil),
            javaDetector: MockJavaDetector(),
            componentInstaller: MockInstaller(),
            shellRunner: shell
        )

        try service.runPrivilegedJavaUninstall(path: "/Library/Java/JavaVirtualMachines/jdk-17.jdk")

        XCTAssertTrue(shell.executedLaunchCommands.contains { $0.contains("/usr/bin/osascript -e") })
        XCTAssertTrue(shell.executedLaunchCommands.contains { $0.contains("with administrator privileges") })
        XCTAssertTrue(shell.executedLaunchCommands.contains { $0.contains("/bin/rm -rf '/Library/Java/JavaVirtualMachines/jdk-17.jdk'") })
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
    private var homebrewInstalled: Bool
    private var sdkmanInstalled: Bool
    private let canInstallSDKMANFlag: Bool
    private let availableJavaCandidates: [SDKMANJavaCandidate]

    init(
        homebrewInstalled: Bool = true,
        sdkmanInstalled: Bool = true,
        canInstallSDKMAN: Bool = true,
        availableJavaCandidates: [SDKMANJavaCandidate] = []
    ) {
        self.homebrewInstalled = homebrewInstalled
        self.sdkmanInstalled = sdkmanInstalled
        self.canInstallSDKMANFlag = canInstallSDKMAN
        self.availableJavaCandidates = availableJavaCandidates
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

    func isSDKMANInstalled() -> Bool {
        sdkmanInstalled
    }

    func canInstallSDKMAN() -> Bool {
        canInstallSDKMANFlag
    }

    func installSDKMAN() throws {
        operations.append("install-sdkman")
        sdkmanInstalled = true
    }

    func listAvailableJavaCandidatesWithSDKMAN() throws -> [SDKMANJavaCandidate] {
        operations.append("sdkman-list-java")
        return availableJavaCandidates
    }

    func installJavaWithSDKMAN(identifier: String) throws {
        operations.append("install-sdkman-java:\(identifier)")
    }

    func uninstallJavaWithSDKMAN(identifier: String) throws {
        operations.append("sdkman-uninstall-java:\(identifier)")
    }

    func setSDKMANDefaultJava(identifier: String) throws {
        operations.append("sdkman-default-java:\(identifier)")
    }
}

private final class RetryingSDKMANInstaller: RuntimeComponentInstalling, @unchecked Sendable {
    private(set) var operations: [String] = []
    private let identifierToFailFirst: String
    private var failedOnce = false

    init(identifierToFailFirst: String) {
        self.identifierToFailFirst = identifierToFailFirst
    }

    func isHomebrewInstalled() -> Bool { true }
    func installHomebrew() throws {}
    func canInstallNVM() -> Bool { true }
    func installNVM() throws {}
    func isSDKMANInstalled() -> Bool { true }
    func canInstallSDKMAN() -> Bool { true }
    func installSDKMAN() throws {}
    func listAvailableJavaCandidatesWithSDKMAN() throws -> [SDKMANJavaCandidate] { [] }
    func installJavaWithSDKMAN(identifier: String) throws {}

    func uninstallJavaWithSDKMAN(identifier: String) throws {
        operations.append("sdkman-uninstall-java:\(identifier)")
        if identifier == identifierToFailFirst, !failedOnce {
            failedOnce = true
            throw RuntimeComponentInstallerError.sdkmanJavaUninstallFailed(
                identifier: identifier,
                message: "Cannot uninstall: java \(identifier) is currently in use."
            )
        }
    }

    func setSDKMANDefaultJava(identifier: String) throws {
        operations.append("sdkman-default-java:\(identifier)")
    }
}

private final class ForceHintSDKMANInstaller: RuntimeComponentInstalling, @unchecked Sendable {
    private(set) var operations: [String] = []
    private let message: String

    init(message: String) {
        self.message = message
    }

    func isHomebrewInstalled() -> Bool { true }
    func installHomebrew() throws {}
    func canInstallNVM() -> Bool { true }
    func installNVM() throws {}
    func isSDKMANInstalled() -> Bool { true }
    func canInstallSDKMAN() -> Bool { true }
    func installSDKMAN() throws {}
    func listAvailableJavaCandidatesWithSDKMAN() throws -> [SDKMANJavaCandidate] { [] }
    func installJavaWithSDKMAN(identifier: String) throws {}

    func uninstallJavaWithSDKMAN(identifier: String) throws {
        operations.append("sdkman-uninstall-java:\(identifier)")
        throw RuntimeComponentInstallerError.sdkmanJavaUninstallFailed(
            identifier: identifier,
            message: message
        )
    }

    func setSDKMANDefaultJava(identifier: String) throws {
        operations.append("sdkman-default-java:\(identifier)")
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

    func isSDKMANInstalled() -> Bool {
        false
    }

    func canInstallSDKMAN() -> Bool {
        false
    }

    func installSDKMAN() throws {
        throw RuntimeComponentInstallerError.sdkmanInstallFailed(message: "sdkman failed")
    }

    func listAvailableJavaCandidatesWithSDKMAN() throws -> [SDKMANJavaCandidate] {
        throw RuntimeComponentInstallerError.sdkmanListJavaFailed(message: "list failed")
    }

    func installJavaWithSDKMAN(identifier: String) throws {
        throw RuntimeComponentInstallerError.sdkmanJavaInstallFailed(identifier: identifier, message: "java install failed")
    }

    func uninstallJavaWithSDKMAN(identifier: String) throws {
        throw RuntimeComponentInstallerError.sdkmanJavaUninstallFailed(identifier: identifier, message: "java uninstall failed")
    }

    func setSDKMANDefaultJava(identifier: String) throws {
        throw RuntimeComponentInstallerError.sdkmanSetDefaultFailed(identifier: identifier, message: "default failed")
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
