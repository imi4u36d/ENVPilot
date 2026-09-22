import AppKit
import Combine
import ENVPilotCore
import Foundation

enum AppPreferenceKey {
    static let showsMenuBarMenu = "showsMenuBarMenu"
    static let keepsMenuBarIconAfterClose = "keepsMenuBarIconAfterClose"
    static let hasCompletedEnvironmentCheck = "hasCompletedEnvironmentCheck"
}

/// 与 `@AppStorage` 共用的非偏好键（侧边栏状态由 AppKit 侧读写）。
enum AppStateKey {
    static let sidebarCollapsed = "ENVPilotSidebarCollapsed"
    static let sidebarWidthInitialized = "ENVPilotSidebarWidthInitialized"
}

/// 主窗口呈现器。
///
/// `openWindow(id:)` 只在 SwiftUI 视图环境里可用，而 `applicationShouldHandleReopen` 是
/// AppKit 侧的回调。这里由 `RootView` 在出现时把那个动作登记进来，Dock 点击时就能把
/// 主窗口找回来——否则「关掉菜单栏入口 + 关掉主窗口」会让应用既没窗口也没状态项。
@MainActor
enum MainWindowPresenter {
    private static var openAction: (() -> Void)?

    static func register(_ action: @escaping () -> Void) {
        openAction = action
    }

    static func show() {
        NSApp.activate()
        if let visible = NSApp.windows.first(where: { $0.isVisible && $0.canBecomeMain }) {
            visible.makeKeyAndOrderFront(nil)
            return
        }
        openAction?()
    }
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

    /// 点 Dock 图标时把主窗口带回来。
    ///
    /// 这条路径以前是空的：关掉菜单栏入口、又关掉主窗口之后，应用还在运行（这是
    /// 「关闭主窗口后保留菜单栏图标」的既定行为），此时既没有窗口也没有状态项，
    /// Dock 成了唯一入口，却没有任何代码保证它能恢复窗口。
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            MainWindowPresenter.show()
        }
        return true
    }
}
