import Foundation
import ServiceManagement

/// 开机自启动：走 macOS 的登录项（`SMAppService`），不写 LaunchAgent、不改用户的 plist。
///
/// 只有从 `.app` 包里跑起来才可用。裸二进制（`swift run`、`.build/debug/ENVPilotApp`）
/// 没有稳定的代码身份，注册会失败——那种情况下界面要把开关置灰并说明原因，
/// 而不是让开关看着能点、实际什么都没发生。
public struct LoginItemService: Sendable {
    public enum Status: Equatable, Sendable {
        /// 系统里已登记为登录项。
        case enabled
        /// 可以设置，当前是关的。
        case disabled
        /// 当前运行方式注册不了登录项（不是 `.app` 包）。
        case unavailable(reason: String)
    }

    public init() {}

    public func status() -> Status {
        guard Bundle.main.bundlePath.hasSuffix(".app") else {
            return .unavailable(reason: "需要在 .app 里运行")
        }
        return SMAppService.mainApp.status == .enabled ? .enabled : .disabled
    }

    public var isAvailable: Bool {
        if case .unavailable = status() {
            return false
        }
        return true
    }

    /// 注册或注销登录项。失败时把系统给的原因带出去，由界面显示。
    public func setEnabled(_ enabled: Bool) -> Result<Void, LoginItemError> {
        guard isAvailable else {
            return .failure(LoginItemError(reason: "需要在 .app 里运行才能设置开机自启动"))
        }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return .success(())
        } catch {
            return .failure(LoginItemError(reason: error.localizedDescription))
        }
    }
}

public struct LoginItemError: Error, Equatable, Sendable {
    public let reason: String

    public init(reason: String) {
        self.reason = reason
    }
}
