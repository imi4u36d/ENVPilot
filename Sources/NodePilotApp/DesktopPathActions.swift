import AppKit
import Foundation

enum DesktopPathActions {
    static func copy(_ path: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(path, forType: .string)
    }

    static func revealInFinder(_ path: String) {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
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
