import XCTest
@testable import ENVPilotCore

final class EnvironmentSetupServiceTests: XCTestCase {
    func testRepairInstallsCommandLineToolsAndShellIntegration() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let home = root.appendingPathComponent("home", isDirectory: true)
        let source = root.appendingPathComponent("envpilot-helper")
        XCTAssertTrue(FileManager.default.createFile(atPath: source.path, contents: Data("helper".utf8)))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: source.path)

        let runtime = StubRuntimeProvider(snapshot: selectedNodeSnapshot(version: "24.18.0"))
        let service = EnvironmentSetupService(
            environment: ["HOME": home.path],
            runtimeProvider: runtime,
            helperSourceURL: source
        )

        let report = service.repair(aiStatuses: [])

        XCTAssertFalse(report.needsRepair)
        let helper = home.appendingPathComponent(".local/bin/envpilot-helper")
        let ep = home.appendingPathComponent(".local/bin/ep")
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: helper.path))
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: ep.path), "envpilot-helper")

        let zshrc = try String(contentsOf: home.appendingPathComponent(".zshrc"), encoding: .utf8)
        XCTAssertTrue(zshrc.contains("# >>> ENVPilot >>>"))
        XCTAssertTrue(zshrc.contains(helper.path))
    }

    func testRepairInstallsRecommendedNodeWhenNoneIsInstalled() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let home = root.appendingPathComponent("home", isDirectory: true)
        let source = root.appendingPathComponent("envpilot-helper")
        XCTAssertTrue(FileManager.default.createFile(atPath: source.path, contents: Data("helper".utf8)))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: source.path)

        let runtime = StubRuntimeProvider(snapshot: emptyNodeSnapshot())
        let service = EnvironmentSetupService(
            environment: ["HOME": home.path],
            runtimeProvider: runtime,
            helperSourceURL: source
        )

        let report = service.repair(aiStatuses: [])

        XCTAssertFalse(report.needsRepair)
        XCTAssertEqual(runtime.installedVersions, ["24.18.0"])
        XCTAssertEqual(runtime.selectedVersion, "24.18.0")
    }

    func testUpdatedZshrcReplacesExistingBlockAndPreservesOtherLines() {
        let existing = """
        export PATH="$HOME/.local/bin:$PATH"

        # >>> ENVPilot >>>
        old snippet
        # <<< ENVPilot <<<

        alias ll='ls -la'
        """
        let snippet = """
        # >>> ENVPilot >>>
        new snippet
        # <<< ENVPilot <<<
        """

        let updated = EnvironmentSetupService.updatedZshrc(existing, snippet: snippet)

        XCTAssertFalse(updated.contains("old snippet"))
        XCTAssertTrue(updated.contains("new snippet"))
        XCTAssertTrue(updated.contains("alias ll='ls -la'"))
    }

    private func selectedNodeSnapshot(version: String) -> NodeRuntimeSnapshot {
        let installPath = "/Users/me/.envpilot/runtimes/node/\(version)"
        return NodeRuntimeSnapshot(
            installations: [
                NodeInstallation(
                    version: version,
                    installPath: installPath,
                    executablePath: "\(installPath)/bin/node",
                    isDefault: true
                )
            ],
            activeVersion: version,
            activeNodePath: "\(installPath)/bin/node",
            settings: AppSettings(
                selectedVersion: version,
                selectedNodePath: installPath
            )
        )
    }

    private func emptyNodeSnapshot() -> NodeRuntimeSnapshot {
        NodeRuntimeSnapshot(
            installations: [],
            activeVersion: nil,
            settings: AppSettings()
        )
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

private final class StubRuntimeProvider: EnvironmentNodeRuntimeProviding, @unchecked Sendable {
    private var snapshot: NodeRuntimeSnapshot
    private(set) var installedVersions: [String] = []
    private(set) var selectedVersion: String?

    init(snapshot: NodeRuntimeSnapshot) {
        self.snapshot = snapshot
    }

    func loadSnapshot(progress: (@Sendable (String) -> Void)?) throws -> NodeRuntimeSnapshot {
        snapshot
    }

    func listAvailableNodeVersions(ltsOnly: Bool) throws -> [NodeDownloadCandidate] {
        [NodeDownloadCandidate(version: "24.18.0", lts: "Krypton")]
    }

    func selectDefaultNode(version: String, progress: (@Sendable (String) -> Void)?) throws -> NodeRuntimeSnapshot {
        selectedVersion = version
        let installPath = "/Users/me/.envpilot/runtimes/node/\(version)"
        snapshot = NodeRuntimeSnapshot(
            installations: [
                NodeInstallation(
                    version: version,
                    installPath: installPath,
                    executablePath: "\(installPath)/bin/node",
                    isDefault: true
                )
            ],
            activeVersion: version,
            activeNodePath: "\(installPath)/bin/node",
            settings: AppSettings(selectedVersion: version, selectedNodePath: installPath)
        )
        return snapshot
    }

    func installNode(version: String, progress: (@Sendable (String) -> Void)?) throws -> NodeRuntimeSnapshot {
        installedVersions.append(version)
        return try selectDefaultNode(version: version, progress: progress)
    }
}
