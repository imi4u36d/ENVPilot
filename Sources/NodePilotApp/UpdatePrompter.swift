import AppKit
import ENVPilotCore

/// 从菜单入口（应用菜单「检查更新…」、菜单栏面板「检查更新…」）触发的检查。
///
/// 命令式入口没有现成的结果展示位，所以结果用系统弹窗给出；发现新版本时顺手把
/// 设置窗口带到「软件更新」卡片上，下载进度才有地方看。
@MainActor
enum UpdatePrompter {
    static func checkAndPresent(model: AppUpdateModel) async {
        switch await model.check() {
        case .upToDate(let current, let latest):
            present(
                title: "已是最新版本",
                message: "当前版本 v\(current)，GitHub 上的最新版本是 v\(latest)。",
                primaryButton: "好"
            )
        case .updateAvailable(let release):
            let notes = ReleaseNotesFormatter.plainText(release.notes)
            let response = present(
                title: "发现新版本 v\(release.version)",
                message: alertBody(notes: notes, canSelfUpdate: model.canSelfUpdate),
                primaryButton: model.canSelfUpdate ? "更新" : "下载 dmg",
                secondaryButton: "稍后"
            )
            // 进度、说明都在「软件更新」卡片里，先把它带出来再看用户的选择。
            WindowActions.openSettings()
            if response == .alertFirstButtonReturn {
                await model.install()
            }
        case .none:
            if case .failed(let message) = model.phase {
                present(title: "检查更新失败", message: message, primaryButton: "好")
            }
        }
    }

    private static func alertBody(notes: String, canSelfUpdate: Bool) -> String {
        let limit = 600
        let trimmed = notes.count > limit ? String(notes.prefix(limit)) + "…" : notes
        let action = canSelfUpdate
            ? "现在更新会下载新版本、替换应用并自动重新启动。"
            : "当前运行位置无法自动替换，将下载 dmg 后手动安装。"
        guard !trimmed.isEmpty else {
            return action
        }
        return "\(action)\n\n\(trimmed)"
    }

    @discardableResult
    static func present(
        title: String,
        message: String,
        primaryButton: String,
        secondaryButton: String? = nil
    ) -> NSApplication.ModalResponse {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: primaryButton)
        if let secondaryButton {
            alert.addButton(withTitle: secondaryButton)
        }
        return alert.runModal()
    }
}
