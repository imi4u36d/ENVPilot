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
            selectedJavaHome: javaHome,
            profiles: [EnvironmentProfile(name: "Default")]
        )

        let script = integration.renderActivationScript(settings: settings, cwd: nil, shell: .zsh)

        XCTAssertTrue(script.contains("export ENVPILOT_EFFECTIVE_JAVA_VERSION='21.0.4'"))
        XCTAssertTrue(script.contains("export JAVA_HOME='\(javaHome)'"))
        XCTAssertTrue(script.contains("export PATH=\"$JAVA_HOME/bin:$PATH\""))
    }

    func testActivationScriptExportsNodeHomeForSelectedVersion() {
        let integration = ShellIntegrationService()
        let nodeHome = "\(testManagedRuntimeRoot)/node/14.21.3"
        let settings = AppSettings(
            selectedVersion: "14.21.3",
            selectedNodePath: nodeHome,
            profiles: [EnvironmentProfile(name: "Default")]
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
            nodeInstallations: installations,
            cwd: nil,
            shell: .zsh
        )

        XCTAssertTrue(script.contains("export ENVPILOT_EFFECTIVE_NODE_VERSION='14.21.3'"))
        XCTAssertTrue(script.contains("export ENVPILOT_NODE_HOME='\(nodeHome)'"))
        XCTAssertTrue(script.contains("export PATH=\"$ENVPILOT_NODE_HOME/bin:$PATH\""))
        XCTAssertFalse(script.contains("nvm use"))
    }

    func testActivationScriptUsesEnvPilotJavaVersionFromProjectCache() throws {
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

        let script = integration.renderActivationScript(settings: settings, cwd: root, shell: .zsh)

        XCTAssertTrue(script.contains("export ENVPILOT_EFFECTIVE_JAVA_VERSION='11'"))
        XCTAssertTrue(script.contains("export JAVA_HOME='\(java11Home)'"))
        XCTAssertFalse(script.contains("export JAVA_HOME='\(java25Home)'"))
    }

    func testActivationScriptDoesNotFallBackToSelectedNodeWhenProjectVersionIsMissing() throws {
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

        let script = integration.renderActivationScript(settings: settings, cwd: root, shell: .zsh)

        XCTAssertTrue(script.contains("export ENVPILOT_EFFECTIVE_NODE_VERSION='18.19.0'"))
        XCTAssertFalse(script.contains("export ENVPILOT_NODE_HOME='\(nodeHome)'"))
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
        let javaBinURL = javaHomeURL.appendingPathComponent("bin/java")

        try FileManager.default.createDirectory(at: javaBinURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: javaBinURL.path, contents: Data("#!/bin/zsh\n".utf8))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: javaBinURL.path)

        return (rootURL, homeURL, javaHomeURL)
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
