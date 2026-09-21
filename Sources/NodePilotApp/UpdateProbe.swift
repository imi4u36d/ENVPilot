import AppKit
import ENVPilotCore

/// 「检查更新」的验证探针。和 `WindowSnapshot`、`PerfProbe` 一样，只有设置了环境
/// 变量才介入启动流程，平时完全不参与运行。
///
/// ```bash
/// # 1. 只查 GitHub 上的最新发布（联网，不改动任何东西）
/// ENVPILOT_UPDATE_PROBE=check dist/ENVPilot.app/Contents/MacOS/ENVPilotApp
///
/// # 2. 下载 + 解压 + 校验，打印暂存路径（不动当前安装）
/// ENVPILOT_UPDATE_PROBE=stage ...
///
/// # 3. 完整走一遍替换（`ENVPILOT_UPDATE_RELAUNCH=0` 时不重启，便于自动验证）
/// ENVPILOT_UPDATE_PROBE=apply ENVPILOT_UPDATE_RELAUNCH=0 ...
/// ```
///
/// 界面验收走 `WindowSnapshot`（`ENVPILOT_WINDOW_SNAPSHOT_SETTINGS=1`）与
/// `MenuBarSnapshot`（`ENVPILOT_MENUBAR_SNAPSHOT_UPDATE=…`），都在那边注入状态。
///
/// 暂存目录可用 `ENVPILOT_UPDATE_STAGING_ROOT` 改写（沙箱里跑验证时指到 `/tmp`）。
@MainActor
enum UpdateProbe {
    static let environmentKey = "ENVPILOT_UPDATE_PROBE"

    private static var environment: [String: String] {
        ProcessInfo.processInfo.environment
    }

    static func runIfRequested() {
        guard let mode = environment[environmentKey]?.lowercased(), !mode.isEmpty else {
            return
        }
        // 放到首轮 runloop 里跑：URLSession 的回调需要应用生命周期已就绪。
        DispatchQueue.main.async {
            run(mode: mode)
        }
    }

    private static func run(mode: String) {
        switch mode {
        case "check":
            check()
        case "stage":
            _ = stage()
        case "apply":
            apply()
        default:
            fail("未知模式：\(mode)（可用：check / stage / apply）")
        }
    }

    private static var service: AppUpdateService {
        AppUpdateService(configuration: .live())
    }

    // MARK: 检查

    private static func check() {
        let service = service
        print("update-probe: current=\(service.currentVersion) install=\(describe(service.installMode()))")
        do {
            let release = try service.latestRelease()
            print("update-probe: latest tag=\(release.tag) version=\(release.version) prerelease=\(release.isPrerelease)")
            print("update-probe: archive=\(release.archiveURL?.absoluteString ?? "-")")
            print("update-probe: dmg=\(release.diskImageURL?.absoluteString ?? "-")")
            let result = AppUpdateCheck.evaluate(current: service.currentVersion, release: release)
            print("update-probe: result=\(result.isUpdateAvailable ? "update-available" : "up-to-date")")
            finish(0)
        } catch {
            fail(error.localizedDescription)
        }
    }

    // MARK: 下载并暂存

    private static func stage() -> StagedAppUpdate? {
        let service = service
        do {
            let release = try service.latestRelease()
            print("update-probe: staging \(release.version)")
            let staged = try service.downloadAndStage(release) { progress in
                print("update-probe: \(progress.message)")
            }
            print("update-probe: staged=\(staged.appURL.path)")
            return staged
        } catch {
            fail(error.localizedDescription)
            return nil
        }
    }

    // MARK: 替换

    private static func apply() {
        let service = service
        let mode = service.installMode()
        print("update-probe: current=\(service.currentVersion) install=\(describe(mode))")
        guard mode.canSelfUpdate else {
            fail("当前运行位置不支持自更新：\(mode.manualReason ?? "-")")
            return
        }
        guard let staged = stage() else {
            return
        }
        let relaunch = environment["ENVPILOT_UPDATE_RELAUNCH"] != "0"
        do {
            let destination = try service.apply(staged, relaunch: relaunch)
            print("update-probe: destination=\(destination.path) relaunch=\(relaunch)")
            print("update-probe: exiting so the swap script can run")
            finish(0)
        } catch {
            fail(error.localizedDescription)
        }
    }

    // MARK: 夹具

    /// 快照用的假 release。正文用真实发布说明的形状，方便看排版。
    static func previewRelease(version: String) -> AppRelease {
        AppRelease(
            tag: "v\(version)",
            version: version,
            name: "ENVPilot v\(version)",
            notes: """
            ENVPilot v\(version)

            ## 主窗口

            - 侧边栏折叠动画不再跳变
            - 概览页版本号对齐到等宽数字

            ## 工具

            - `scripts/probe.sh` 增加折叠探针
            """,
            pageURL: URL(string: "https://github.com/imi4u36d/ENVPilot/releases/tag/v\(version)"),
            archiveURL: URL(string: "https://github.com/imi4u36d/ENVPilot/releases/download/v\(version)/ENVPilot.zip"),
            diskImageURL: URL(string: "https://github.com/imi4u36d/ENVPilot/releases/download/v\(version)/ENVPilot.dmg"),
            publishedAt: Date(),
            isPrerelease: false
        )
    }

    private static func describe(_ mode: AppUpdateInstallMode) -> String {
        switch mode {
        case .replaceInPlace(let url):
            return "replace-in-place(\(url.path))"
        case .installIntoApplications(let url):
            return "install-into-applications(\(url.path))"
        case .manualDownloadOnly(let reason):
            return "manual-only(\(reason))"
        }
    }

    private static func fail(_ message: String) {
        print("update-probe: error \(message)")
        finish(1)
    }

    /// 探针必须立刻退出：`apply` 之后自更新脚本正等着本进程消失。
    private static func finish(_ code: Int32) {
        fflush(stdout)
        exit(code)
    }
}
