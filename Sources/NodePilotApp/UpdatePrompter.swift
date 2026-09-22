import AppKit
import ENVPilotCore

/// 从菜单入口（应用菜单「检查更新…」、菜单栏面板「检查更新…」）触发的检查。
///
/// 命令式入口没有现成的结果展示位，所以失败与「发现新版本」用系统弹窗给出；成功
/// （已是最新）不弹窗，而是把设置窗口带到「软件更新」卡片——那里本来就有版本号和
/// 检查时间。用模态弹窗播报成功信息属于「用弹窗报告一件没发生的事」。
@MainActor
enum UpdatePrompter {
    static func checkAndPresent(model: AppUpdateModel) async {
        switch await model.check() {
        case .upToDate:
            WindowActions.openSettings()

        case .updateAvailable(let release):
            let notes = ReleaseNotesFormatter.plainText(release.notes)
            let response = await present(
                title: "发现新版本 v\(release.version)",
                message: alertBody(notes: notes, canSelfUpdate: model.canSelfUpdate),
                primaryButton: model.canSelfUpdate ? "更新" : "下载 dmg",
                secondaryButton: "稍后",
                style: .informational
            )
            // 用户选了「稍后」就别把他拽到设置窗口：进度和说明都在那边的
            // 「软件更新」卡片里，选「更新」时才需要把那扇窗带出来。
            guard response == .alertFirstButtonReturn else {
                return
            }
            WindowActions.openSettings()
            await model.install()

        case .none:
            let message: String
            if case .failed(let failure) = model.phase {
                message = failure
            } else {
                // 以前这条分支什么都不做：命令点了没反应，用户以为按钮坏了。
                message = "无法完成检查，请稍后重试。"
            }
            await present(
                title: "检查更新失败",
                message: message,
                primaryButton: "好",
                style: .warning
            )
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
        secondaryButton: String? = nil,
        style: NSAlert.Style = .warning
    ) async -> NSApplication.ModalResponse {
        // `activate(ignoringOtherApps:)` 在 macOS 14 起废弃。
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = style
        alert.addButton(withTitle: primaryButton)
        if let secondaryButton {
            alert.addButton(withTitle: secondaryButton)
        }
        // `runModal()` 是 app-modal：会把刚打开的设置窗口一起冻住，还强行抢焦点。
        // 有窗口可挂时就挂 sheet，只有连一个窗口都没有时才退回 app-modal。
        if let window = NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first(where: { $0.isVisible }) {
            return await withCheckedContinuation { continuation in
                alert.beginSheetModal(for: window) { response in
                    continuation.resume(returning: response)
                }
            }
        }
        return alert.runModal()
    }
}
