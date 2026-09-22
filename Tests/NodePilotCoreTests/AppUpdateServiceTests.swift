import XCTest
@testable import ENVPilotCore

final class AppUpdateServiceTests: XCTestCase {
    // MARK: 版本号

    func testVersionParsing() {
        XCTAssertEqual(AppVersion("v0.6.4")?.numbers, [0, 6, 4])
        XCTAssertEqual(AppVersion("0.6.4")?.numbers, [0, 6, 4])
        XCTAssertEqual(AppVersion("0.7")?.numbers, [0, 7])
        XCTAssertEqual(AppVersion("0.6.5-beta.1")?.prerelease, ["beta", "1"])
        XCTAssertEqual(AppVersion("0.0.0-dev+abc1234")?.numbers, [0, 0, 0])
        XCTAssertEqual(AppVersion("0.0.0-dev+abc1234")?.prerelease, ["dev"])
        XCTAssertEqual(AppVersion("7.0.6-6-g1d86792")?.numbers, [7, 0, 6])
        XCTAssertEqual(AppVersion("7.0.6-6-g1d86792")?.prerelease, [])
        XCTAssertEqual(AppVersion("7.0.6-6-g1d86792-dirty")?.prerelease, [])
        XCTAssertNil(AppVersion("dev"))
        XCTAssertNil(AppVersion(""))
    }

    func testVersionComparison() {
        // 数值比较，而不是字符串比较：0.6.10 > 0.6.9。
        XCTAssertTrue(AppVersion("0.6.10")! > AppVersion("0.6.9")!)
        XCTAssertTrue(AppVersion("0.7")! > AppVersion("0.6.4")!)
        XCTAssertTrue(AppVersion("1.0")! > AppVersion("0.9.9")!)
        XCTAssertEqual(AppVersion("v0.6.4"), AppVersion("0.6.4"))
        // 正式版 > 预发布版。
        XCTAssertTrue(AppVersion("0.6.5")! > AppVersion("0.6.5-beta.1")!)
        XCTAssertTrue(AppVersion("0.6.5-beta.2")! > AppVersion("0.6.5-beta.1")!)
        // git describe 后缀表示 tag 之后的提交，不是预发布版本。
        XCTAssertEqual(AppVersion("7.0.6-6-g1d86792"), AppVersion("7.0.6"))
        XCTAssertEqual(AppVersion("7.0.6-6-g1d86792-dirty"), AppVersion("7.0.6"))
        XCTAssertTrue(AppVersion("7.0.7-1-gabc1234")! > AppVersion("7.0.6")!)
        // 开发构建的 0.0.0-dev 小于任何正式发布。
        XCTAssertTrue(AppVersion("0.0.0-dev+abc1234")! < AppVersion("0.1.0")!)
    }

    func testEvaluateAvailability() {
        let release = makeRelease(version: "0.6.5")

        XCTAssertTrue(AppUpdateCheck.evaluate(current: "0.6.4", release: release).isUpdateAvailable)
        XCTAssertFalse(AppUpdateCheck.evaluate(current: "0.6.5", release: release).isUpdateAvailable)
        XCTAssertFalse(AppUpdateCheck.evaluate(current: "0.7.0", release: release).isUpdateAvailable)
        // 开发构建（版本号读不到）也要能走检查流程。
        XCTAssertTrue(AppUpdateCheck.evaluate(current: "dev", release: release).isUpdateAvailable)

        guard case .upToDate(let current, let latest) = AppUpdateCheck.evaluate(current: "0.6.5", release: release) else {
            return XCTFail("应当判定为已是最新")
        }
        XCTAssertEqual(current, "0.6.5")
        XCTAssertEqual(latest, "0.6.5")
    }

    // MARK: GitHub 返回体

    func testDecodeGitHubReleasePayload() throws {
        let json = """
        {
          "tag_name": "v0.6.5",
          "name": "ENVPilot v0.6.5",
          "body": "## 修复\\n- 一个 bug",
          "html_url": "https://github.com/imi4u36d/ENVPilot/releases/tag/v0.6.5",
          "draft": false,
          "prerelease": false,
          "published_at": "2026-09-21T11:39:00Z",
          "assets": [
            {
              "name": "ENVPilot.dmg",
              "browser_download_url": "https://github.com/imi4u36d/ENVPilot/releases/download/v0.6.5/ENVPilot.dmg"
            },
            {
              "name": "ENVPilot.zip",
              "browser_download_url": "https://github.com/imi4u36d/ENVPilot/releases/download/v0.6.5/ENVPilot.zip"
            }
          ]
        }
        """.data(using: .utf8)!

        let payload = try AppUpdateService.decodeReleasePayload(json)
        XCTAssertEqual(payload.tagName, "v0.6.5")
        XCTAssertEqual(payload.assets?.count, 2)

        let archiveURL = payload.assets?.first { $0.name == "ENVPilot.zip" }?.browserDownloadUrl
        XCTAssertEqual(archiveURL?.lastPathComponent, "ENVPilot.zip")
        XCTAssertEqual(AppUpdateService.normalizedVersion(payload.tagName), "0.6.5")
        XCTAssertNotNil(AppUpdateService.parseTimestamp(payload.publishedAt ?? ""))
    }

    // MARK: 安装方式

    func testInstallModeFallsBackForNonBundledExecutable() {
        let service = makeService(bundleURL: URL(fileURLWithPath: "/tmp/somewhere/ENVPilotApp"))

        guard case .manualDownloadOnly = service.installMode() else {
            return XCTFail("非打包应用应当只支持手动下载")
        }
    }

    func testReleaseFromRedirectURL() throws {
        let configuration = AppUpdateService.Configuration(
            stagingRoot: URL(fileURLWithPath: NSTemporaryDirectory()),
            currentVersion: "0.6.4",
            currentBundleURL: nil,
            applicationsDirectory: URL(fileURLWithPath: NSTemporaryDirectory())
        )
        // `/releases/latest` 会 302 到这个地址，资产名由发布流水线固定。
        let finalURL = URL(string: "https://github.com/imi4u36d/ENVPilot/releases/tag/v0.6.5")!
        let release = try XCTUnwrap(AppUpdateService.release(fromRedirectURL: finalURL, configuration: configuration))

        XCTAssertEqual(release.tag, "v0.6.5")
        XCTAssertEqual(release.version, "0.6.5")
        XCTAssertEqual(release.pageURL, finalURL)
        XCTAssertEqual(
            release.archiveURL?.absoluteString,
            "https://github.com/imi4u36d/ENVPilot/releases/download/v0.6.5/ENVPilot.zip"
        )
        XCTAssertEqual(
            release.diskImageURL?.absoluteString,
            "https://github.com/imi4u36d/ENVPilot/releases/download/v0.6.5/ENVPilot.dmg"
        )

        XCTAssertNil(AppUpdateService.release(
            fromRedirectURL: URL(string: "https://github.com/imi4u36d/ENVPilot/releases")!,
            configuration: configuration
        ))
    }

    func testInstallModeReplacesWritableBundleInPlace() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let app = root.appendingPathComponent("ENVPilot.app", isDirectory: true)
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)

        let service = makeService(bundleURL: app)
        XCTAssertEqual(service.installMode(), .replaceInPlace(app))
    }

    func testInstallModeInstallsIntoApplicationsForReadOnlyLocation() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let mounted = URL(fileURLWithPath: "/Volumes/ENVPilot/ENVPilot.app", isDirectory: true)

        let service = makeService(bundleURL: mounted, applicationsDirectory: root)
        guard case .installIntoApplications(let destination) = service.installMode() else {
            return XCTFail("只读位置应当装到应用程序目录")
        }
        XCTAssertEqual(destination, root.appendingPathComponent("ENVPilot.app"))
    }

    // MARK: 解压与校验

    func testExtractAndValidateStagedApp() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let archive = try makeSignedFakeAppArchive(in: root, version: "9.9.9")
        let staging = root.appendingPathComponent("staged", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)

        let service = makeService(bundleURL: root.appendingPathComponent("ENVPilot.app"))
        try service.extractArchive(archive, to: staging)

        let stagedApp = try service.stagedApplication(in: staging)
        XCTAssertEqual(stagedApp.lastPathComponent, "ENVPilot.app")
        XCTAssertNoThrow(try service.validate(stagedApp, expecting: "9.9.9"))
    }

    func testValidateRejectsWrongVersion() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let archive = try makeSignedFakeAppArchive(in: root, version: "9.9.8")
        let staging = root.appendingPathComponent("staged", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)

        let service = makeService(bundleURL: root.appendingPathComponent("ENVPilot.app"))
        try service.extractArchive(archive, to: staging)
        let stagedApp = try service.stagedApplication(in: staging)

        XCTAssertThrowsError(try service.validate(stagedApp, expecting: "9.9.9")) { error in
            guard case AppUpdateError.stagedAppInvalid(let message) = error else {
                return XCTFail("应当是 stagedAppInvalid，实际是 \(error)")
            }
            XCTAssertTrue(message.contains("9.9.8"), message)
        }
    }

    func testStagedApplicationRejectsArchiveWithoutApp() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("staged"), withIntermediateDirectories: true)

        let service = makeService(bundleURL: root.appendingPathComponent("ENVPilot.app"))
        XCTAssertThrowsError(try service.stagedApplication(in: root.appendingPathComponent("staged")))
    }

    // MARK: 更新脚本

    func testApplyScriptWaitsForParentAndCanSkipRelaunch() {
        let script = AppUpdateService.applyScript(
            stagedApp: "/tmp/staged/ENVPilot.app",
            destination: "/Users/me/Applications/ENVPilot.app",
            helper: "/Users/me/.local/bin/envpilot-helper",
            workDirectory: "/tmp/staged",
            relaunch: false
        )
        XCTAssertTrue(script.contains("kill -0 \"$PARENT_PID\""))
        XCTAssertTrue(script.contains("/usr/bin/ditto"))
        XCTAssertTrue(script.contains("'/Users/me/Applications/ENVPilot.app'"))
        XCTAssertTrue(script.contains("'/Users/me/.local/bin/envpilot-helper'"))
        XCTAssertTrue(script.contains("xattr -dr com.apple.quarantine"))
        XCTAssertTrue(script.contains("relaunch skipped"))
        XCTAssertFalse(script.contains("/usr/bin/open"))

        let relaunching = AppUpdateService.applyScript(
            stagedApp: "/tmp/staged/ENVPilot.app",
            destination: "/Applications/ENVPilot.app",
            helper: nil,
            workDirectory: "/tmp/staged",
            relaunch: true
        )
        XCTAssertTrue(relaunching.contains(#"/usr/bin/open "$DEST""#))
    }

    // MARK: 夹具

    private func makeService(
        bundleURL: URL,
        applicationsDirectory: URL? = nil
    ) -> AppUpdateService {
        let configuration = AppUpdateService.Configuration(
            stagingRoot: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("envpilot-update-tests", isDirectory: true),
            currentVersion: "0.6.4",
            currentBundleURL: bundleURL,
            applicationsDirectory: applicationsDirectory ?? URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("envpilot-applications", isDirectory: true)
        )
        return AppUpdateService(configuration: configuration)
    }

    private func makeRelease(version: String) -> AppRelease {
        AppRelease(
            tag: "v\(version)",
            version: version,
            name: "ENVPilot v\(version)",
            notes: "",
            pageURL: URL(string: "https://github.com/imi4u36d/ENVPilot/releases/tag/v\(version)"),
            archiveURL: URL(string: "https://github.com/imi4u36d/ENVPilot/releases/download/v\(version)/ENVPilot.zip"),
            diskImageURL: nil,
            publishedAt: nil,
            isPrerelease: false
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("envpilot-update-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// 造一个 ad-hoc 签名的假 `ENVPilot.app`，打包成 `ENVPilot.zip`，走真实的
    /// `ditto` 解压与 `codesign --verify` 校验路径。
    private func makeSignedFakeAppArchive(in root: URL, version: String) throws -> URL {
        let app = root.appendingPathComponent("payload/ENVPilot.app", isDirectory: true)
        let macOS = app.appendingPathComponent("Contents/MacOS", isDirectory: true)
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)

        let plist: [String: Any] = [
            "CFBundleIdentifier": "com.envpilot.app",
            "CFBundleShortVersionString": version,
            "CFBundleExecutable": "ENVPilotApp",
            "CFBundlePackageType": "APPL",
            "CFBundleName": "ENVPilot",
        ]
        let plistData = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try plistData.write(to: app.appendingPathComponent("Contents/Info.plist"))

        let executable = macOS.appendingPathComponent("ENVPilotApp")
        try "#!/bin/zsh\nexit 0\n".write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)

        let shell = ShellCommandRunner()
        let sign = try shell.run("/usr/bin/codesign", arguments: ["--force", "--sign", "-", app.path], environment: ProcessInfo.processInfo.environment)
        guard sign.succeeded else {
            throw XCTSkip("codesign 不可用：\(sign.standardError)")
        }

        let archive = root.appendingPathComponent("ENVPilot.zip")
        let zip = try shell.run(
            "/usr/bin/ditto",
            arguments: ["-c", "-k", "--keepParent", app.path, archive.path],
            environment: ProcessInfo.processInfo.environment
        )
        guard zip.succeeded else {
            throw XCTSkip("ditto 打包失败：\(zip.standardError)")
        }
        return archive
    }
}
