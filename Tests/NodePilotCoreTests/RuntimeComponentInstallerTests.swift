import Foundation
import XCTest
@testable import ENVPilotCore

final class RuntimeComponentInstallerTests: XCTestCase {
    func testDownloadURLRequiresHTTPS() {
        XCTAssertNoThrow(try RuntimeComponentInstaller.url("https://example.com/runtime.tar.xz"))
        XCTAssertThrowsError(try RuntimeComponentInstaller.url("http://example.com/runtime.tar.xz"))
        XCTAssertThrowsError(try RuntimeComponentInstaller.url("file:///tmp/runtime.tar.xz"))
    }

    func testArchiveEntriesRejectAbsoluteAndParentPaths() throws {
        let installer = RuntimeComponentInstaller()

        XCTAssertNoThrow(try installer.validateArchiveEntries("runtime/bin/node\nruntime/lib/module\n"))
        XCTAssertThrowsError(try installer.validateArchiveEntries("../../outside\n"))
        XCTAssertThrowsError(try installer.validateArchiveEntries("runtime/../outside\n"))
        XCTAssertThrowsError(try installer.validateArchiveEntries("/absolute/path\n"))
    }

    func testVerifySHA256AcceptsExpectedDigest() throws {
        let fileURL = try temporaryFile(contents: Data("abc".utf8))
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        try RuntimeComponentInstaller().verifySHA256(
            fileURL: fileURL,
            expectedHex: "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
    }

    func testVerifySHA256RejectsMismatchedDigest() throws {
        let fileURL = try temporaryFile(contents: Data("abc".utf8))
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        XCTAssertThrowsError(
            try RuntimeComponentInstaller().verifySHA256(fileURL: fileURL, expectedHex: String(repeating: "0", count: 64))
        ) { error in
            guard case RuntimeComponentInstallerError.runtimeChecksumMismatch(let file) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(file, fileURL.lastPathComponent)
        }
    }

    func testVerifyMD5AcceptsPythonOrgDigest() throws {
        let fileURL = try temporaryFile(contents: Data("abc".utf8))
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        // `md5("abc")`，与 python.org 的 `<archive>.md5` 同格式。
        try RuntimeComponentInstaller().verifyMD5(
            fileURL: fileURL,
            expectedHex: "900150983cd24fb0d6963f7d28e17f72"
        )
    }

    func testVerifyMD5RejectsMismatchedDigest() throws {
        let fileURL = try temporaryFile(contents: Data("abc".utf8))
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        XCTAssertThrowsError(
            try RuntimeComponentInstaller().verifyMD5(
                fileURL: fileURL,
                expectedHex: String(repeating: "0", count: 32)
            )
        ) { error in
            guard case RuntimeComponentInstallerError.runtimeChecksumMismatch(let file) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(file, fileURL.lastPathComponent)
        }
    }

    func testMD5DigestParsingHandlesBothPythonOrgFormats() {
        XCTAssertEqual(
            RuntimeComponentInstaller.md5HexDigest(in: "900150983cd24fb0d6963f7d28e17f72\n"),
            "900150983cd24fb0d6963f7d28e17f72"
        )
        XCTAssertEqual(
            RuntimeComponentInstaller.md5HexDigest(
                in: "900150983cd24fb0d6963f7d28e17f72  Python-3.13.5.tar.xz\n"
            ),
            "900150983cd24fb0d6963f7d28e17f72"
        )
        XCTAssertNil(RuntimeComponentInstaller.md5HexDigest(in: "no digest here"))
    }

    func testReleaseFileDigestMatchingPicksTheExactArchive() {
        let files = [
            PythonReleaseFile(
                url: "https://www.python.org/ftp/python/3.13.5/Python-3.13.5.tgz",
                md5Sum: "88dc0b8317cab6e46e8336995bcc577f"
            ),
            PythonReleaseFile(
                url: "https://www.python.org/ftp/python/3.13.5/Python-3.13.5.tar.xz",
                md5Sum: "dbaa8833aa736eddbb18a6a6ae0c10fa"
            ),
            PythonReleaseFile(
                url: "https://www.python.org/ftp/python/3.13.5/Python-3.13.5.tar.xz.asc",
                md5Sum: ""
            ),
        ]

        XCTAssertEqual(
            RuntimeComponentInstaller.md5Digest(in: files, archiveName: "Python-3.13.5.tar.xz"),
            "dbaa8833aa736eddbb18a6a6ae0c10fa"
        )
        XCTAssertNil(RuntimeComponentInstaller.md5Digest(in: files, archiveName: "Python-3.13.4.tar.xz"))
    }

    func testPythonSourceCandidateUsesPredictableArchiveURLWithoutProbing() throws {
        let candidate = try RuntimeComponentInstaller()
            .pythonSourceCandidate(version: "3.13.5", confirmExistence: false)

        XCTAssertEqual(candidate?.packageName, "Python-3.13.5.tar.xz")
        XCTAssertEqual(
            candidate?.downloadURL,
            "https://www.python.org/ftp/python/3.13.5/Python-3.13.5.tar.xz"
        )
    }

    func testSweepStaleInstallArtifactsRemovesOnlyOldArtifacts() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let managedRoot = root.appendingPathComponent("managed", isDirectory: true)
        let tempRoot = root.appendingPathComponent("temp", isDirectory: true)
        let now = Date()
        let old = now.addingTimeInterval(-48 * 60 * 60)
        let fresh = now.addingTimeInterval(-60)

        func makeDirectory(_ url: URL, modified: Date) throws {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
        }

        let staleBackup = managedRoot.appendingPathComponent(".24.18.0.backup-OLD", isDirectory: true)
        let freshBackup = managedRoot.appendingPathComponent(".24.18.0.backup-NEW", isDirectory: true)
        let installedRuntime = managedRoot.appendingPathComponent("24.18.0", isDirectory: true)
        let staleTemp = tempRoot.appendingPathComponent("envpilot-runtime-node-old", isDirectory: true)
        let freshTemp = tempRoot.appendingPathComponent("envpilot-runtime-node-new", isDirectory: true)
        try makeDirectory(staleBackup, modified: old)
        try makeDirectory(freshBackup, modified: fresh)
        try makeDirectory(installedRuntime, modified: old)
        try makeDirectory(staleTemp, modified: old)
        try makeDirectory(freshTemp, modified: fresh)

        RuntimeComponentInstaller().sweepStaleInstallArtifacts(
            in: [managedRoot],
            tempDirectory: tempRoot,
            now: now
        )

        XCTAssertFalse(FileManager.default.fileExists(atPath: staleBackup.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: staleTemp.path))
        // 24 小时内的残留可能属于另一个正在进行的安装，不能碰；普通安装目录更不能碰。
        XCTAssertTrue(FileManager.default.fileExists(atPath: freshBackup.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: freshTemp.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: installedRuntime.path))
    }

    func testInstallEntryPointsHonorPreCancelledToken() {
        let cancellation = ShellCommandCancellation()
        cancellation.cancel()
        let installer = RuntimeComponentInstaller()

        XCTAssertThrowsError(
            try installer.installNode(version: "24.0.0", cancellation: cancellation, progress: nil)
        ) { error in
            XCTAssertTrue(error is CancellationError, "node threw \(error)")
        }
        XCTAssertThrowsError(
            try installer.installJava(featureVersion: 21, cancellation: cancellation, progress: nil)
        ) { error in
            XCTAssertTrue(error is CancellationError, "java threw \(error)")
        }
        XCTAssertThrowsError(
            try installer.installPython(version: "3.13.5", cancellation: cancellation, progress: nil)
        ) { error in
            XCTAssertTrue(error is CancellationError, "python threw \(error)")
        }
    }

    func testReplaceManagedDirectoryRestoresExistingTargetWhenMoveFails() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let missingSource = root.appendingPathComponent("missing", isDirectory: true)
        let target = root.appendingPathComponent("target", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try Data("existing".utf8).write(to: target.appendingPathComponent("marker"))

        XCTAssertThrowsError(
            try RuntimeComponentInstaller().replaceManagedDirectory(source: missingSource, target: target)
        )
        XCTAssertEqual(
            try String(contentsOf: target.appendingPathComponent("marker"), encoding: .utf8),
            "existing"
        )
    }

    func testReplaceManagedDirectorySwapsInStagedRuntime() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source", isDirectory: true)
        let target = root.appendingPathComponent("target", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try Data("new".utf8).write(to: source.appendingPathComponent("marker"))
        try Data("old".utf8).write(to: target.appendingPathComponent("marker"))

        try RuntimeComponentInstaller().replaceManagedDirectory(source: source, target: target)

        XCTAssertEqual(
            try String(contentsOf: target.appendingPathComponent("marker"), encoding: .utf8),
            "new"
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
    }

    private func temporaryFile(contents: Data) throws -> URL {
        let directory = try temporaryDirectory()
        let fileURL = directory.appendingPathComponent("payload")
        try contents.write(to: fileURL)
        return fileURL
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("envpilot-installer-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
