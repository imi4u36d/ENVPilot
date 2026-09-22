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

    func testRepairBacksUpExistingZshrcAndPreservesItsPermissions() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let home = root.appendingPathComponent("home", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("envpilot-helper")
        XCTAssertTrue(FileManager.default.createFile(atPath: source.path, contents: Data("helper".utf8)))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: source.path)

        let zshrc = home.appendingPathComponent(".zshrc")
        let original = "alias ll='ls -la'\n"
        try Data(original.utf8).write(to: zshrc)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: zshrc.path)

        let service = EnvironmentSetupService(
            environment: ["HOME": home.path],
            runtimeProvider: StubRuntimeProvider(snapshot: selectedNodeSnapshot(version: "24.18.0")),
            helperSourceURL: source
        )

        let report = service.repair(aiStatuses: [])

        XCTAssertFalse(report.needsRepair)
        // 动用户的 ~/.zshrc 之前先留一份带时间戳的备份。
        let backups = try FileManager.default.contentsOfDirectory(atPath: home.path)
            .filter { $0.hasPrefix(".zshrc.envpilot-backup-") }
        XCTAssertEqual(backups.count, 1)
        XCTAssertEqual(
            try String(contentsOf: home.appendingPathComponent(backups[0]), encoding: .utf8),
            original
        )

        let updated = try String(contentsOf: zshrc, encoding: .utf8)
        XCTAssertTrue(updated.contains("alias ll='ls -la'"))
        XCTAssertTrue(updated.contains("# >>> ENVPilot >>>"))
        // 原子替换不能把原来的 0600 变成默认权限。
        let permissions = try FileManager.default
            .attributesOfItem(atPath: zshrc.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o600)
    }

    func testRepairSkipsZshrcRewriteWhenMarkerBlockIsAlreadyCurrent() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let home = root.appendingPathComponent("home", isDirectory: true)
        let source = root.appendingPathComponent("envpilot-helper")
        XCTAssertTrue(FileManager.default.createFile(atPath: source.path, contents: Data("helper".utf8)))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: source.path)

        let runtimeSnapshot = selectedNodeSnapshot(version: "24.18.0")
        let first = EnvironmentSetupService(
            environment: ["HOME": home.path],
            runtimeProvider: StubRuntimeProvider(snapshot: runtimeSnapshot),
            helperSourceURL: source
        )
        XCTAssertFalse(first.repair(aiStatuses: []).needsRepair)

        let zshrc = home.appendingPathComponent(".zshrc")
        let contents = try String(contentsOf: zshrc, encoding: .utf8)
        let modified = try FileManager.default
            .attributesOfItem(atPath: zshrc.path)[.modificationDate] as? Date

        let second = EnvironmentSetupService(
            environment: ["HOME": home.path],
            runtimeProvider: StubRuntimeProvider(snapshot: runtimeSnapshot),
            helperSourceURL: source
        )
        XCTAssertFalse(second.repair(aiStatuses: []).needsRepair)

        XCTAssertEqual(try String(contentsOf: zshrc, encoding: .utf8), contents)
        XCTAssertEqual(
            try FileManager.default.attributesOfItem(atPath: zshrc.path)[.modificationDate] as? Date,
            modified
        )
        // 没写盘就不会留下第二份备份。
        XCTAssertTrue(
            try FileManager.default.contentsOfDirectory(atPath: home.path)
                .filter { $0.hasPrefix(".zshrc.envpilot-backup-") }
                .isEmpty
        )
    }

    func testRepairReplacesExistingHelperWithoutLeavingTemporaryFiles() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let home = root.appendingPathComponent("home", isDirectory: true)
        let bin = home.appendingPathComponent(".local/bin", isDirectory: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try Data("stale".utf8).write(to: bin.appendingPathComponent("envpilot-helper"))

        let source = root.appendingPathComponent("envpilot-helper")
        XCTAssertTrue(FileManager.default.createFile(atPath: source.path, contents: Data("helper".utf8)))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: source.path)

        let service = EnvironmentSetupService(
            environment: ["HOME": home.path],
            runtimeProvider: StubRuntimeProvider(snapshot: selectedNodeSnapshot(version: "24.18.0")),
            helperSourceURL: source
        )
        XCTAssertFalse(service.repair(aiStatuses: []).needsRepair)

        let helper = bin.appendingPathComponent("envpilot-helper")
        XCTAssertEqual(try String(contentsOf: helper, encoding: .utf8), "helper")
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: helper.path))
        XCTAssertTrue(
            try FileManager.default.contentsOfDirectory(atPath: bin.path)
                .allSatisfy { $0 == "envpilot-helper" || $0 == "ep" }
        )
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
