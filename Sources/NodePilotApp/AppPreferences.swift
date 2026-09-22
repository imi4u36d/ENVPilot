import AppKit
import Combine
import ENVPilotCore
import Foundation

enum AppPreferenceKey {
    static let showsMenuBarMenu = "showsMenuBarMenu"
    static let keepsMenuBarIconAfterClose = "keepsMenuBarIconAfterClose"
    static let hasCompletedEnvironmentCheck = "hasCompletedEnvironmentCheck"
}

/// 「关闭主窗口后是否留在菜单栏」这一个开关的读取处。
///
/// 默认开：跟历史行为一致——关掉主窗口，应用仍然留在菜单栏。关掉之后，
/// 最后一个窗口一关应用就退出（设置窗口还开着时不算「最后一个窗口关掉」）。
enum CloseBehavior {
    static func keepsRunningAfterLastWindowClosed(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: AppPreferenceKey.keepsMenuBarIconAfterClose) as? Bool ?? true
    }
}

/// 开机自启动的状态镜像。值本身在系统那边（登录项），这里只负责读出来、改回去，
/// 以及把失败原因交给界面显示。
@MainActor
final class LoginItemModel: ObservableObject {
    @Published private(set) var isOn = false
    @Published private(set) var canToggle = true
    @Published private(set) var notice: String?

    private let service: LoginItemService

    init(service: LoginItemService = LoginItemService()) {
        self.service = service
        refresh()
    }

    func refresh() {
        switch service.status() {
        case .enabled:
            canToggle = true
            isOn = true
            notice = nil
        case .disabled:
            canToggle = true
            isOn = false
            notice = nil
        case .unavailable(let reason):
            canToggle = false
            isOn = false
            notice = reason
        }
    }

    func toggle(_ enabled: Bool) {
        switch service.setEnabled(enabled) {
        case .success:
            isOn = enabled
            notice = nil
        case .failure(let error):
            // 系统没答应，开关就得弹回去——否则界面显示「已开启」而实际没注册。
            isOn = false
            notice = error.reason
        }
    }
}

/// 应用自身的生命周期代理。目前只回答一个问题：最后一个窗口关掉之后要不要退出。
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// 关掉「留在菜单栏」开关后，关最后一个窗口就退出。
    ///
    /// 用 `UserDefaults` 现读而不是缓存一份：这个开关在设置窗口里改完立刻生效，
    /// 不需要谁去通知这里。
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !CloseBehavior.keepsRunningAfterLastWindowClosed()
    }
}
