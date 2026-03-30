import XCTest
@testable import ENVPilotCore

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
        let settings = AppSettings(
            selectedJavaVersion: "21.0.4",
            selectedJavaHome: "/Library/Java/JavaVirtualMachines/temurin-21.jdk/Contents/Home",
            profiles: [EnvironmentProfile(name: "Default")]
        )

        let script = integration.renderActivationScript(settings: settings, cwd: nil, shell: .zsh)

        XCTAssertTrue(script.contains("export ENVPILOT_EFFECTIVE_JAVA_VERSION='21.0.4'"))
        XCTAssertTrue(script.contains("export JAVA_HOME='/Library/Java/JavaVirtualMachines/temurin-21.jdk/Contents/Home'"))
        XCTAssertTrue(script.contains("export PATH=\"$JAVA_HOME/bin:$PATH\""))
    }

    func testActivationScriptUsesNVMForSelectedVersion() {
        let integration = ShellIntegrationService()
        let settings = AppSettings(
            selectedVersion: "14.21.3",
            profiles: [EnvironmentProfile(name: "Default")]
        )

        let script = integration.renderActivationScript(settings: settings, cwd: nil, shell: .zsh)

        XCTAssertTrue(script.contains("export NVM_DIR=\"${NVM_DIR:-$HOME/.nvm}\""))
        XCTAssertTrue(script.contains("if [ -s \"$NVM_DIR/nvm.sh\" ]; then"))
        XCTAssertTrue(script.contains("nvm use --silent '14.21.3'"))
    }

    func testDetectInstallationsIncludesSDKMANCandidatesAndMarksCurrentAsDefault() throws {
        let tempRoot = try makeTemporarySDKMANJavaHome(version: "21.0.4-tem")
        defer { try? FileManager.default.removeItem(at: tempRoot.rootURL) }

        let javaHome = tempRoot.javaHomeURL.path
        let shell = JavaDetectorMockShellRunner(outputsByCommandFragment: [
            "'\(javaHome)/bin/java' -version 2>&1": .init(
                standardOutput: "",
                standardError: "openjdk version \"21.0.4\" 2024-07-16\n",
                exitCode: 0
            )
        ])

        let detector = JavaRuntimeDetector(
            shellRunner: shell,
            environment: ["SDKMAN_CANDIDATES_DIR": tempRoot.candidatesURL.path]
        )
        let installations = detector.detectInstallations()

        XCTAssertEqual(installations.count, 1)
        XCTAssertEqual(installations.first?.version, "21.0.4")
        XCTAssertEqual(installations.first?.homePath, javaHome)
        XCTAssertEqual(installations.first?.isDefault, true)
        XCTAssertEqual(detector.detectActiveJavaHome(), javaHome)
        XCTAssertEqual(detector.detectActiveVersion(), "21.0.4")
    }

    func testSDKMANJavaIdentifierFromHomePath() {
        let home = "/Users/me/.sdkman/candidates/java/21.0.4-tem/Contents/Home"
        XCTAssertEqual(JavaRuntimeDetector.sdkmanJavaIdentifier(fromHomePath: home), "21.0.4-tem")
        XCTAssertNil(JavaRuntimeDetector.sdkmanJavaIdentifier(fromHomePath: "/Library/Java/JavaVirtualMachines/temurin-21.jdk/Contents/Home"))
    }

    func testParseSDKMANJavaCandidates() {
        let output = """
        ================================================================================
        Available Java Versions for macOS ARM 64bit
        ================================================================================
         Vendor        | Use | Version      | Dist    | Status     | Identifier
        --------------------------------------------------------------------------------
         Temurin       |     | 21.0.10      | tem     |            | 21.0.10-tem
                       |     | 17.0.18      | tem     |            | 17.0.18-tem
         Zulu          |     | 17.0.18.fx   | zulu    |            | 17.0.18.fx-zulu
        """

        let candidates = RuntimeComponentInstaller.parseSDKMANJavaCandidates(from: output)

        XCTAssertEqual(candidates.count, 3)
        XCTAssertEqual(candidates[0].vendor, "Temurin")
        XCTAssertEqual(candidates[1].vendor, "Temurin")
        XCTAssertEqual(candidates[2].identifier, "17.0.18.fx-zulu")
    }

    func testRuntimeComponentInstallerRepairsBrokenSDKMANDirectoryBeforeInstall() throws {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let sdkmanDir = tempRoot.appendingPathComponent(".sdkman", isDirectory: true)
        let bashPath = tempRoot.appendingPathComponent("bin/bash")
        try FileManager.default.createDirectory(
            at: sdkmanDir.appendingPathComponent("candidates"),
            withIntermediateDirectories: true,
            attributes: nil
        )
        try FileManager.default.createDirectory(
            at: bashPath.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )
        FileManager.default.createFile(atPath: bashPath.path, contents: Data("#!/bin/zsh\n".utf8))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: bashPath.path)

        let initScriptPath = sdkmanDir.appendingPathComponent("bin/sdkman-init.sh")
        let shell = JavaDetectorMockShellRunner(
            outputsByCommandFragment: [
                "command -v curl": .init(
                    standardOutput: "/usr/bin/curl\n",
                    standardError: "",
                    exitCode: 0
                ),
                "command -v bash": .init(
                    standardOutput: "\(bashPath.path)\n",
                    standardError: "",
                    exitCode: 0
                ),
                "'\(bashPath.path)' --version": .init(
                    standardOutput: "GNU bash, version 5.2.37(1)-release (aarch64-apple-darwin)\n",
                    standardError: "",
                    exitCode: 0
                ),
                "curl -fsSL https://get.sdkman.io | '\(bashPath.path)'": .init(
                    standardOutput: "",
                    standardError: "",
                    exitCode: 0
                )
            ],
            onRunShell: { command, environment in
                if command.contains("curl -fsSL https://get.sdkman.io |") {
                    try FileManager.default.createDirectory(
                        at: initScriptPath.deletingLastPathComponent(),
                        withIntermediateDirectories: true,
                        attributes: nil
                    )
                    FileManager.default.createFile(atPath: initScriptPath.path, contents: Data("#!/bin/zsh\n".utf8))
                }
            }
        )
        let installer = RuntimeComponentInstaller(
            shellRunner: shell,
            environment: [
                "HOME": tempRoot.path,
                "SDKMAN_DIR": sdkmanDir.path,
            ]
        )

        try installer.installSDKMAN()

        XCTAssertTrue(FileManager.default.fileExists(atPath: initScriptPath.path))
        let backups = try FileManager.default.contentsOfDirectory(atPath: tempRoot.path).filter { $0.hasPrefix(".sdkman.broken-") }
        XCTAssertEqual(backups.count, 1)
    }

    func testRuntimeComponentInstallerThrowsWhenSDKMANInstallRemainsIncomplete() throws {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let sdkmanDir = tempRoot.appendingPathComponent(".sdkman", isDirectory: true)
        let bashPath = tempRoot.appendingPathComponent("bin/bash")
        try FileManager.default.createDirectory(
            at: sdkmanDir.appendingPathComponent("tmp"),
            withIntermediateDirectories: true,
            attributes: nil
        )
        try FileManager.default.createDirectory(
            at: bashPath.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )
        FileManager.default.createFile(atPath: bashPath.path, contents: Data("#!/bin/zsh\n".utf8))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: bashPath.path)

        let shell = JavaDetectorMockShellRunner(outputsByCommandFragment: [
            "command -v curl": .init(
                standardOutput: "/usr/bin/curl\n",
                standardError: "",
                exitCode: 0
            ),
            "command -v bash": .init(
                standardOutput: "\(bashPath.path)\n",
                standardError: "",
                exitCode: 0
            ),
            "'\(bashPath.path)' --version": .init(
                standardOutput: "GNU bash, version 5.2.37(1)-release (aarch64-apple-darwin)\n",
                standardError: "",
                exitCode: 0
            ),
            "curl -fsSL https://get.sdkman.io | '\(bashPath.path)'": .init(
                standardOutput: "",
                standardError: "",
                exitCode: 0
            )
        ])
        let installer = RuntimeComponentInstaller(
            shellRunner: shell,
            environment: [
                "HOME": tempRoot.path,
                "SDKMAN_DIR": sdkmanDir.path,
            ]
        )

        XCTAssertThrowsError(try installer.installSDKMAN()) { error in
            guard case RuntimeComponentInstallerError.sdkmanInstallIncomplete(let initScriptPath, let repairedBackupPath) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertTrue(initScriptPath.hasSuffix(".sdkman/bin/sdkman-init.sh"))
            XCTAssertNotNil(repairedBackupPath)
        }
    }

    private func makeTemporarySDKMANJavaHome(version: String) throws -> (rootURL: URL, candidatesURL: URL, javaHomeURL: URL) {
        let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let candidatesURL = rootURL.appendingPathComponent("java", isDirectory: true)
        let javaHomeURL = candidatesURL.appendingPathComponent(version, isDirectory: true)
        let javaBinURL = javaHomeURL.appendingPathComponent("bin/java")

        try FileManager.default.createDirectory(at: javaBinURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: javaBinURL.path, contents: Data("#!/bin/zsh\n".utf8))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: javaBinURL.path)
        try FileManager.default.createSymbolicLink(
            at: candidatesURL.appendingPathComponent("current"),
            withDestinationURL: javaHomeURL
        )

        return (rootURL, candidatesURL, javaHomeURL)
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
