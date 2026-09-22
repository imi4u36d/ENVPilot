import XCTest
@testable import ENVPilotCore

private let testManagedRuntimeRoot = "\(NSHomeDirectory())/.envpilot/runtimes"

final class JavaAndShellIntegrationTests: XCTestCase {
    func testParseJavaInstallationsFromJavaHomeOutput() {
        let output = """
        Matching Java Virtual Machines (2):
            21.0.4 (arm64) "Eclipse Adoptium" - "OpenJDK 21.0.4" /Library/Java/JavaVirtualMachines/temurin-21.jdk/Contents/Home
            17.0.12 (arm64) "Eclipse Adoptium" - "OpenJDK 17.0.12" /Library/Java/JavaVirtualMachines/temurin-17.jdk/Contents/Home
        """

        let installations = JavaRuntimeDetector.parseInstallations(from: output)

        XCTAssertEqual(installations.count, 2)
        XCTAssertEqual(installations.first?.version, "21.0.4")
        XCTAssertEqual(installations.first?.homePath, "/Library/Java/JavaVirtualMachines/temurin-21.jdk/Contents/Home")
    }

    func testActivationScriptExportsJavaHomeWhenSelected() {
        let integration = ShellIntegrationService()
        let javaHome = "\(testManagedRuntimeRoot)/java/temurin-21.jdk/Contents/Home"
        let settings = AppSettings(
            selectedJavaVersion: "21.0.4",
            selectedJavaHome: javaHome
        )

        let script = integration.renderActivationScript(settings: settings)

        XCTAssertTrue(script.contains("export ENVPILOT_EFFECTIVE_JAVA_VERSION='21.0.4'"))
        XCTAssertTrue(script.contains("export JAVA_HOME='\(javaHome)'"))
        XCTAssertTrue(script.contains("export PATH=\"$JAVA_HOME/bin:$PATH\""))
    }

    func testActivationScriptExportsNodeHomeForSelectedVersion() {
        let integration = ShellIntegrationService()
        let nodeHome = "\(testManagedRuntimeRoot)/node/14.21.3"
        let settings = AppSettings(
            selectedVersion: "14.21.3",
            selectedNodePath: nodeHome
        )
        let installations = [
            NodeInstallation(
                version: "14.21.3",
                installPath: nodeHome,
                executablePath: "\(nodeHome)/bin/node"
            )
        ]

        let script = integration.renderActivationScript(
            settings: settings,
            nodeInstallations: installations
        )

        XCTAssertTrue(script.contains("export ENVPILOT_EFFECTIVE_NODE_VERSION='14.21.3'"))
        XCTAssertTrue(script.contains("export ENVPILOT_NODE_HOME='\(nodeHome)'"))
        XCTAssertTrue(script.contains("export PATH=\"$ENVPILOT_NODE_HOME/bin:$PATH\""))
        XCTAssertTrue(script.contains("export PATH=\"$HOME/.envpilot/tools:$PATH\""))
        XCTAssertFalse(script.contains("nvm use"))
    }

    /// 目录里的 `.envpilot` 不再参与选版本：终端环境只由全局选择决定。
    ///
    /// 这两条用例守着「项目作用域已删除」这个事实。改动前它们断言的是相反的行为
    /// （项目声明压过全局选择），留着比删掉有用——将来谁想把目录作用域加回来，
    /// 会先在这里撞一下。
    func testActivationScriptIgnoresEnvPilotFileInDirectory() throws {
        let integration = ShellIntegrationService()
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try "JAVA_VERSION=11\n".write(
            to: root.appendingPathComponent(".envpilot"),
            atomically: true,
            encoding: .utf8
        )

        let java11Home = "\(testManagedRuntimeRoot)/java/temurin-11.jdk/Contents/Home"
        let java25Home = "\(testManagedRuntimeRoot)/java/temurin-25.jdk/Contents/Home"
        let settings = AppSettings(
            selectedJavaVersion: "25.0.2",
            selectedJavaHome: java25Home,
            cachedJavaInstallations: [
                JavaInstallation(version: "25.0.2", homePath: java25Home),
                JavaInstallation(version: "11.0.31", homePath: java11Home),
            ]
        )

        let script = integration.renderActivationScript(settings: settings)

        XCTAssertTrue(script.contains("export ENVPILOT_EFFECTIVE_JAVA_VERSION='25.0.2'"))
        XCTAssertTrue(script.contains("export JAVA_HOME='\(java25Home)'"))
        XCTAssertFalse(script.contains("export JAVA_HOME='\(java11Home)'"))
    }

    func testActivationScriptIgnoresProjectNodeDeclaration() throws {
        let integration = ShellIntegrationService()
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try "NODE_VERSION=18.19.0\n".write(
            to: root.appendingPathComponent(".envpilot"),
            atomically: true,
            encoding: .utf8
        )

        let nodeHome = "\(testManagedRuntimeRoot)/node/24.15.0"
        let settings = AppSettings(
            selectedVersion: "24.15.0",
            selectedNodePath: nodeHome,
            cachedNodeInstallations: [
                NodeInstallation(
                    version: "24.15.0",
                    installPath: nodeHome,
                    executablePath: "\(nodeHome)/bin/node"
                )
            ]
        )

        let script = integration.renderActivationScript(settings: settings)

        XCTAssertTrue(script.contains("export ENVPILOT_EFFECTIVE_NODE_VERSION='24.15.0'"))
        XCTAssertTrue(script.contains("export ENVPILOT_NODE_HOME='\(nodeHome)'"))
    }

    func testDetectInstallationsIncludesEnvPilotManagedJDKAndMarksCurrentAsDefault() throws {
        let tempRoot = try makeTemporaryEnvPilotJavaHome(version: "21.0.4")
        defer { try? FileManager.default.removeItem(at: tempRoot.rootURL) }

        let javaHome = tempRoot.javaHomeURL.path
        let shell = JavaDetectorMockShellRunner(outputsByCommandFragment: [
            "/usr/libexec/java_home 2>/dev/null": .init(
                standardOutput: "\(javaHome)\n",
                standardError: "",
                exitCode: 0
            ),
            "'\(javaHome)/bin/java' -version 2>&1": .init(
                standardOutput: "",
                standardError: "openjdk version \"21.0.4\" 2024-07-16\n",
                exitCode: 0
            )
        ])

        let detector = JavaRuntimeDetector(
            shellRunner: shell,
            environment: ["JAVA_HOME": javaHome, "HOME": tempRoot.homeURL.path]
        )
        let installations = detector.detectInstallations()

        XCTAssertEqual(installations.count, 1)
        XCTAssertEqual(installations.first?.version, "21.0.4")
        XCTAssertEqual(installations.first?.homePath, javaHome)
        XCTAssertEqual(installations.first?.isDefault, true)
        XCTAssertEqual(detector.detectActiveJavaHome(), javaHome)
        XCTAssertEqual(detector.detectActiveVersion(), "21.0.4")
    }

    private func makeTemporaryEnvPilotJavaHome(version: String) throws -> (rootURL: URL, homeURL: URL, javaHomeURL: URL) {
        let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let homeURL = rootURL.appendingPathComponent("home", isDirectory: true)
        let javaHomeURL = homeURL
            .appendingPathComponent(".envpilot/runtimes/java/temurin-\(version).jdk/Contents/Home", isDirectory: true)
        try createFakeJavaHome(at: javaHomeURL)

        return (rootURL, homeURL, javaHomeURL)
    }

    private func createFakeJavaHome(at javaHomeURL: URL) throws {
        let javaBinURL = javaHomeURL.appendingPathComponent("bin/java")
        try FileManager.default.createDirectory(at: javaBinURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: javaBinURL.path, contents: Data("#!/bin/zsh\n".utf8))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: javaBinURL.path)
    }

    /// 安装写入的符号链接入口必须能被 `java_home` 这类工具顺链接解析到真身，卸载时要一起清掉。
    func testJavaDiscoveryEntryLifecycle() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let home = root.appendingPathComponent("home", isDirectory: true)
        let bundle = root.appendingPathComponent("store/custom.jdk", isDirectory: true)
        try createFakeJavaHome(at: bundle.appendingPathComponent("Contents/Home", isDirectory: true))

        let installer = RuntimeComponentInstaller(environment: ["HOME": home.path])
        installer.publishJavaDiscoveryEntry(named: "custom.jdk", pointingTo: bundle)

        let entryPath = home
            .appendingPathComponent("Library/Java/JavaVirtualMachines", isDirectory: true)
            .appendingPathComponent("custom.jdk").path
        XCTAssertTrue(RuntimeComponentInstaller.isSymlinkEntry(atPath: entryPath, fileManager: FileManager.default))
        XCTAssertTrue(FileManager.default.fileExists(atPath: entryPath + "/Contents/Home"), "入口应能穿透链接指到真身")

        // 重复安装：先清旧入口再建，不应报错也不应叠出悬空链接。
        installer.publishJavaDiscoveryEntry(named: "custom.jdk", pointingTo: bundle)
        XCTAssertTrue(RuntimeComponentInstaller.isSymlinkEntry(atPath: entryPath, fileManager: FileManager.default))

        installer.removeJavaDiscoveryEntry(named: "custom.jdk")
        XCTAssertFalse(FileManager.default.fileExists(atPath: entryPath))
    }

    private func versionMock(temporaryRootPath: String, version: String) -> JavaDetectorMockShellRunner {
        // 只给本次夹具里的 java 返回版本号：真机上 /opt/homebrew 等绝对路径扫描到的 JDK
        // 拿不到版本会被过滤掉，测试因此与开发机的实际安装互不影响。
        JavaDetectorMockShellRunner(outputsByCommandFragment: [
            temporaryRootPath: .init(
                standardOutput: "",
                standardError: "openjdk version \"\(version)\" 2026-04-21\n",
                exitCode: 0
            )
        ])
    }

    /// 标准 JVM 目录里只放一个符号链接入口时，探测器要能顺链接找到真身。
    func testDetectInstallationsFollowsSymlinkedEntryInUserJVMRoot() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let realBundle = root.appendingPathComponent("store/custom.jdk", isDirectory: true)
        try createFakeJavaHome(at: realBundle.appendingPathComponent("Contents/Home", isDirectory: true))

        let entry = root
            .appendingPathComponent("home/Library/Java/JavaVirtualMachines", isDirectory: true)
            .appendingPathComponent("link.jdk")
        try FileManager.default.createDirectory(at: entry.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: entry.path, withDestinationPath: realBundle.path)

        let detector = JavaRuntimeDetector(
            shellRunner: versionMock(temporaryRootPath: root.path, version: "21.0.11"),
            environment: ["HOME": root.appendingPathComponent("home", isDirectory: true).path]
        )

        let installations = detector.detectInstallations()

        XCTAssertEqual(installations.count, 1)
        XCTAssertTrue(installations.first?.homePath.hasSuffix("custom.jdk/Contents/Home") == true)
    }

    /// 真身在私有运行时目录、标准目录里另有链接入口时，只应算一个 JDK。
    func testDetectInstallationsCountsPrivateRuntimeOnceWithStandardDirectoryEntry() throws {
        let tempRoot = try makeTemporaryEnvPilotJavaHome(version: "21.0.4")
        defer { try? FileManager.default.removeItem(at: tempRoot.rootURL) }

        let privateBundle = tempRoot.javaHomeURL
            .deletingLastPathComponent()   // Contents
            .deletingLastPathComponent()   // temurin-21.0.4.jdk
        let entry = tempRoot.homeURL
            .appendingPathComponent("Library/Java/JavaVirtualMachines", isDirectory: true)
            .appendingPathComponent("private-copy.jdk")
        try FileManager.default.createDirectory(at: entry.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: entry.path, withDestinationPath: privateBundle.path)

        let detector = JavaRuntimeDetector(
            shellRunner: versionMock(temporaryRootPath: tempRoot.rootURL.path, version: "21.0.4"),
            environment: ["HOME": tempRoot.homeURL.path]
        )

        let installations = detector.detectInstallations()

        XCTAssertEqual(installations.count, 1)
        XCTAssertTrue(installations.first?.homePath.hasSuffix("temurin-21.0.4.jdk/Contents/Home") == true)
    }

    /// Gradle 自动置办的 JDK 不在任何标准目录里，目录同层还有 tar.gz / lock 文件。
    func testDetectInstallationsIncludesGradleProvisionedJDK() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let gradleRoot = root.appendingPathComponent("home/.gradle/jdks", isDirectory: true)
        try createFakeJavaHome(at: gradleRoot
            .appendingPathComponent("eclipse_adoptium-21-aarch64-os_x.2/jdk-21.0.12_8/Contents/Home", isDirectory: true))
        FileManager.default.createFile(
            atPath: gradleRoot.appendingPathComponent("OpenJDK21U-jdk_aarch64_mac_hotspot_21.tar.gz").path,
            contents: Data()
        )
        FileManager.default.createFile(atPath: gradleRoot.appendingPathComponent("CACHEDIR.TAG").path, contents: Data())

        let detector = JavaRuntimeDetector(
            shellRunner: versionMock(temporaryRootPath: root.path, version: "21.0.12"),
            environment: ["HOME": root.appendingPathComponent("home", isDirectory: true).path]
        )

        let installations = detector.detectInstallations()

        XCTAssertEqual(installations.count, 1)
        XCTAssertEqual(installations.first?.version, "21.0.12")
    }

    func testJavaBundleRootRecognisesOnlyBundleLayout() {
        let bundleHome = URL(fileURLWithPath: "/tmp/work/jdk-21.0.12+8/Contents/Home", isDirectory: true)
        XCTAssertEqual(
            RuntimeComponentInstaller.javaBundleRoot(ifBundleLayoutOf: bundleHome)?.path,
            "/tmp/work/jdk-21.0.12+8"
        )
        XCTAssertNil(RuntimeComponentInstaller.javaBundleRoot(
            ifBundleLayoutOf: URL(fileURLWithPath: "/tmp/work/zulu-8/Home", isDirectory: true)
        ))
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

private struct JavaDetectorMockShellRunner: ShellCommandRunning {
    let outputsByCommandFragment: [String: ShellCommandResult]
    var onRunShell: (@Sendable (String, [String: String]) throws -> Void)? = nil

    func run(_ launchPath: String, arguments: [String], environment: [String : String]) throws -> ShellCommandResult {
        .init(standardOutput: "", standardError: "", exitCode: 0)
    }

    func runShell(_ command: String, environment: [String : String]) throws -> ShellCommandResult {
        try onRunShell?(command, environment)
        if let match = outputsByCommandFragment.first(where: { command.contains($0.key) }) {
            return match.value
        }
        return .init(standardOutput: "", standardError: "", exitCode: 0)
    }
}
