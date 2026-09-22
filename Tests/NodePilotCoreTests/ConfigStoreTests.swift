import XCTest
@testable import ENVPilotCore

/// `ConfigStore` 的读写行为。
///
/// 全部走 `init(baseDirectory:)` 注入的临时目录：这些用例绝不能碰用户真实的
/// `~/Library/Application Support/ENVPilot/settings.json`。
final class ConfigStoreTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("envpilot-config-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        try super.tearDownWithError()
    }

    func testLoadOnMissingFileReturnsDefaultsAndDoesNotWrite() throws {
        let store = ConfigStore(baseDirectory: root)
        let settingsURL = try store.settingsURL()

        let settings = try store.load()

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: settingsURL.path),
            "读操作不应该创建 settings.json（写盘只由 save/update 触发）"
        )
        XCTAssertNil(settings.selectedNodePath)
    }

    func testSaveThenLoadRoundTrips() throws {
        let store = ConfigStore(baseDirectory: root)
        var settings = AppSettings()
        settings.selectedNodePath = "/tmp/node-22"
        try store.save(settings)

        let reloaded = try ConfigStore(baseDirectory: root).load()
        XCTAssertEqual(reloaded.selectedNodePath, "/tmp/node-22")
    }

    func testCorruptFileIsQuarantinedAndReported() throws {
        let store = ConfigStore(baseDirectory: root)
        let settingsURL = try store.settingsURL()
        try Data("{ this is not json".utf8).write(to: settingsURL)

        let result = try store.loadWithDiagnostics()

        XCTAssertNil(result.settings.selectedNodePath, "损坏时应回落到默认值")
        guard case .corruptFileQuarantined(let backupPath)? = result.warning else {
            return XCTFail("应报告 corruptFileQuarantined，实际 \(String(describing: result.warning))")
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: backupPath), "坏文件应被改名留档")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: settingsURL.path),
            "坏文件应已从原位置移走，避免下一次 save 覆盖它"
        )
        XCTAssertTrue(result.warning?.message.isEmpty == false)
    }

    func testUpdateIsAtomicReadModifyWrite() throws {
        let store = ConfigStore(baseDirectory: root)
        var settings = AppSettings()
        settings.packageManagerMirrors.setAddress("https://registry.npmmirror.com", for: .npm)
        try store.save(settings)

        let outcome = try store.updateWithDiagnostics { current in
            current.selectedNodePath = "/tmp/node-20"
        }

        XCTAssertNil(outcome.warning)
        XCTAssertEqual(outcome.settings.selectedNodePath, "/tmp/node-20")
        // 前一次写入的镜像不能被丢掉。
        XCTAssertEqual(
            outcome.settings.packageManagerMirrors.address(for: .npm),
            "https://registry.npmmirror.com"
        )
        let reloaded = try ConfigStore(baseDirectory: root).load()
        XCTAssertEqual(reloaded.selectedNodePath, "/tmp/node-20")
        XCTAssertEqual(reloaded.packageManagerMirrors.address(for: .npm), "https://registry.npmmirror.com")
    }

    func testUpdateOnMissingFileStartsFromDefaults() throws {
        let store = ConfigStore(baseDirectory: root)
        let outcome = try store.updateWithDiagnostics { current in
            current.selectedNodePath = "/tmp/node-18"
        }
        XCTAssertNil(outcome.warning)
        XCTAssertEqual(outcome.settings.selectedNodePath, "/tmp/node-18")
    }
}
