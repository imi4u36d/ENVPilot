import XCTest
@testable import ENVPilotCore

final class ProjectNodeVersionResolverTests: XCTestCase {
    func testResolveVersionReturnsNilWhenProjectFilesAreMissing() throws {
        let resolver = ProjectNodeVersionResolver()
        let url = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)

        XCTAssertNil(resolver.resolveVersion(startingAt: url))
    }

    func testResolveVersionTrimsWhitespaceInNVMRC() throws {
        let resolver = ProjectNodeVersionResolver()
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        try "  v20.11.1  \n".write(
            to: root.appendingPathComponent(".nvmrc"),
            atomically: true,
            encoding: .utf8
        )

        XCTAssertEqual(resolver.resolveVersion(startingAt: root), "v20.11.1")
    }

    func testResolveVersionFallsBackToNodeVersion() throws {
        let resolver = ProjectNodeVersionResolver()
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        try "18.19.0\n".write(
            to: root.appendingPathComponent(".node-version"),
            atomically: true,
            encoding: .utf8
        )

        XCTAssertEqual(resolver.resolveVersion(startingAt: root), "18.19.0")
    }

    func testResolveVersionWalksParentDirectories() throws {
        let resolver = ProjectNodeVersionResolver()
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let nested = root
            .appendingPathComponent("a", isDirectory: true)
            .appendingPathComponent("b", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try "24.1.0\n".write(
            to: root.appendingPathComponent(".nvmrc"),
            atomically: true,
            encoding: .utf8
        )

        XCTAssertEqual(resolver.resolveVersion(startingAt: nested), "24.1.0")
    }

    func testResolveVersionIgnoresBlankLinesAndComments() throws {
        let resolver = ProjectNodeVersionResolver()
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        try "\n# comment\n   \n22.4.1\n".write(
            to: root.appendingPathComponent(".nvmrc"),
            atomically: true,
            encoding: .utf8
        )

        XCTAssertEqual(resolver.resolveVersion(startingAt: root), "22.4.1")
    }

    func testResolveVersionPrefersNearestDirectoryFile() throws {
        let resolver = ProjectNodeVersionResolver()
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let child = root.appendingPathComponent("child", isDirectory: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        try "20.10.0\n".write(
            to: root.appendingPathComponent(".nvmrc"),
            atomically: true,
            encoding: .utf8
        )
        try "18.17.1\n".write(
            to: child.appendingPathComponent(".node-version"),
            atomically: true,
            encoding: .utf8
        )

        XCTAssertEqual(resolver.resolveVersion(startingAt: child), "18.17.1")
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
