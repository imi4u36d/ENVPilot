import AppKit
import Foundation

enum DesktopPathActions {
    static func copy(_ path: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(path, forType: .string)
    }

    /// 在 Finder 中显示路径。
    ///
    /// 以前路径不存在时直接 `return`：菜单项看起来可用、点了却毫无反应，而调用方还会
    /// 传空串进来（「复制可执行文件路径」因此复制走一个空值）。现在返回是否成功，
    /// 调用方据此禁用菜单项。
    @discardableResult
    static func revealInFinder(_ path: String) -> Bool {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return false
        }
        let url = URL(fileURLWithPath: trimmed)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return false
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
        return true
    }

    /// 「显示 / 复制路径」这类动作是否可用：空串与 `nil` 一律不可用。
    static func isUsablePath(_ path: String?) -> Bool {
        guard let path else {
            return false
        }
        return !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

enum RuntimeDisplayFormatter {
    static func javaVersion(_ version: String?) -> String {
        guard let version, !version.isEmpty else {
            return "--"
        }
        if version.hasPrefix("1.8.") || version.hasPrefix("1.8.0_") {
            return "8 · \(version)"
        }
        return version
    }
}
