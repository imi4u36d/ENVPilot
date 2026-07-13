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
