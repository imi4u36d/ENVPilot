import AppKit
import SwiftUI

/// 主窗口页面的离屏快照。
///
/// `screencapture` 需要屏幕录制权限，自动化脚本也不可靠。这里直接把真实的
/// `RootView` 放进应用自己的窗口里完成布局，再用 `cacheDisplay` 把视图树画到
/// 位图，因此不需要任何系统权限，也能反映真实的深浅色与字号。
///
/// 用法：
/// ```bash
/// ENVPILOT_WINDOW_SNAPSHOT=artifacts/ui/overview.png \
/// ENVPILOT_WINDOW_SNAPSHOT_SECTION=overview \
///   .build/debug/ENVPilotApp
/// ```
///
/// 未设置该环境变量时它完全不参与启动流程。
@MainActor
enum WindowSnapshot {
    static let environmentKey = "ENVPILOT_WINDOW_SNAPSHOT"

    private static let sectionKey = "ENVPILOT_WINDOW_SNAPSHOT_SECTION"
    private static let sizeKey = "ENVPILOT_WINDOW_SNAPSHOT_SIZE"
    private static let schemeKey = "ENVPILOT_WINDOW_SNAPSHOT_SCHEME"
    private static let projectKey = "ENVPILOT_WINDOW_SNAPSHOT_PROJECT"
    /// `=1` 时改为渲染设置窗口（含「软件更新」卡片）。
    private static let settingsKey = "ENVPILOT_WINDOW_SNAPSHOT_SETTINGS"
    /// 快照里注入的更新状态：`available|downloading|latest|failed`（空/缺省为不注入）。
    private static let updateStateKey = "ENVPILOT_WINDOW_SNAPSHOT_UPDATE"

    /// 快照请求的初始页面，供 `RootView` 在 `init` 中读取。
    static var initialSection: AppSection? {
        guard ProcessInfo.processInfo.environment[environmentKey] != nil else { return nil }
        guard let raw = ProcessInfo.processInfo.environment[sectionKey] else { return .overview }
        return AppSection(rawValue: raw)
    }

    static func runIfRequested(store: NodeRuntimeStore, updates: AppUpdateModel) {
        guard let path = ProcessInfo.processInfo.environment[environmentKey], !path.isEmpty else {
            return
        }
        let url = URL(fileURLWithPath: path)
        // 主窗口与设置窗口都可以注入更新状态（侧边栏角标 / 软件更新卡片）。
        applyRequestedUpdateState(to: updates)
        if ProcessInfo.processInfo.environment[settingsKey] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                Task {
                    await captureSettings(store: store, updates: updates, to: url)
                    NSApp.terminate(nil)
                }
            }
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            Task {
                await capture(store: store, to: url)
                NSApp.terminate(nil)
            }
        }
    }

    // MARK: Settings window

    /// 设置窗口没有主窗口那套 `Window` 场景宿主，这里自己起一个窗口渲染真实的
    /// `SettingsRootView`。用 `cacheDisplay` 而不是 `ImageRenderer`：卡片里的
    /// 滚动区与按钮在 `ImageRenderer` 下画不出来（按钮会变成禁止符占位）。
    private static func captureSettings(store: NodeRuntimeStore, updates: AppUpdateModel, to url: URL) async {
        await waitForRuntimeData(store)
        let root = SettingsRootView(store: store, updates: updates)
        let hosting = NSHostingView(rootView: root)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 500),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        if let scheme = requestedScheme() {
            window.appearance = NSAppearance(named: scheme)
        }
        window.orderFrontRegardless()

        for _ in 0..<10 {
            try? await Task.sleep(nanoseconds: 120_000_000)
            window.contentView?.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
        }
        guard let view = window.contentView else {
            log("settings snapshot: no content view")
            return
        }
        emit(view, to: url)
        window.orderOut(nil)
    }

    /// 快照用的状态注入，完全不联网。
    private static func applyRequestedUpdateState(to updates: AppUpdateModel) {
        switch ProcessInfo.processInfo.environment[updateStateKey]?.lowercased() {
        case "available":
            updates.applyPreviewPhase(.available(UpdateProbe.previewRelease(version: "0.6.5")))
        case "downloading":
            updates.applyPreviewPhase(.downloading(message: "正在下载 ENVPilot 0.6.5 42% · 1.6 MB/s", fraction: 0.42))
        case "failed":
            updates.applyPreviewPhase(.failed("无法访问 https://api.github.com/repos/imi4u36d/ENVPilot/releases/latest：The Internet connection appears to be offline."))
        case .some(let other) where !other.isEmpty:
            updates.applyPreviewPhase(.upToDate(current: updates.currentVersion, latest: updates.currentVersion))
        default:
            break
        }
    }

    // MARK: Capture

    private static func capture(store: NodeRuntimeStore, to url: URL) async {
        await waitForRuntimeData(store)
        if let project = ProcessInfo.processInfo.environment[projectKey], !project.isEmpty {
            store.setProjectDirectory((project as NSString).expandingTildeInPath)
            await waitUntil(store, timeoutMilliseconds: 4_000) { !$0.isLoading }
        }
        // 让 SwiftUI 完成一次布局与 `.task` 触发（运行时页会在这里拉候选版本）。
        for _ in 0..<12 {
            try? await Task.sleep(nanoseconds: 150_000_000)
            layoutWindows()
        }

        guard let window = targetWindow() else {
            log("snapshot: no main window found")
            return
        }

        let size = requestedSize()
        window.setContentSize(size)
        if let scheme = requestedScheme() {
            window.appearance = NSAppearance(named: scheme)
        }
        for _ in 0..<6 {
            try? await Task.sleep(nanoseconds: 120_000_000)
            layoutWindows()
        }

        guard let view = window.contentView else {
            log("snapshot: window has no content view")
            return
        }
        // 连标题栏与工具栏一起画：`contentView` 的父视图就是整个窗口边框视图，
        // 只抓 contentView 会丢掉页面标题、副标题和刷新按钮。
        emit(view.superview ?? view, to: url)
    }

    private static let renderScale: CGFloat = 2

    private static func emit(_ view: NSView, to url: URL) {
        let bounds = view.bounds
        guard bounds.width > 1, bounds.height > 1 else {
            log("snapshot: empty bounds \(bounds)")
            return
        }
        let pixelsWide = Int(bounds.width * renderScale)
        let pixelsHigh = Int(bounds.height * renderScale)
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelsWide,
            pixelsHigh: pixelsHigh,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            log("snapshot: cannot allocate bitmap")
            return
        }
        rep.size = bounds.size
        view.cacheDisplay(in: bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            log("snapshot: png encode failed")
            return
        }
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: url)
            print("window snapshot → \(url.path) \(pixelsWide)x\(pixelsHigh)")
        } catch {
            log("snapshot: \(error.localizedDescription)")
        }
    }

    // MARK: Window helpers

    private static func targetWindow() -> NSWindow? {
        let candidates = NSApp.windows.filter { window in
            window.contentView != nil
                && !window.className.contains("StatusBarWindow")
                && window.className != "NSMenuWindow"
                && window.frame.width > 400
        }
        return candidates.max { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
    }

    private static func layoutWindows() {
        for window in NSApp.windows {
            window.contentView?.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
        }
    }

    private static func requestedSize() -> NSSize {
        guard let raw = ProcessInfo.processInfo.environment[sizeKey] else {
            return NSSize(width: 1180, height: 790)
        }
        let parts = raw.lowercased().split(separator: "x").compactMap { Double($0) }
        guard parts.count == 2, parts[0] > 400, parts[1] > 400 else {
            return NSSize(width: 1180, height: 790)
        }
        return NSSize(width: parts[0], height: parts[1])
    }

    private static func requestedScheme() -> NSAppearance.Name? {
        switch ProcessInfo.processInfo.environment[schemeKey]?.lowercased() {
        case "dark":
            return .darkAqua
        case "light":
            return .aqua
        default:
            return nil
        }
    }

    // MARK: Data readiness

    private static func waitForRuntimeData(_ store: NodeRuntimeStore) async {
        await waitUntil(store, timeoutMilliseconds: 20_000) { $0.snapshot != nil && !$0.isLoading }
        await store.refresh()
        await waitUntil(store, timeoutMilliseconds: 4_000) { !$0.isLoading }
    }

    private static func waitUntil(
        _ store: NodeRuntimeStore,
        timeoutMilliseconds: Int,
        condition: (NodeRuntimeStore) -> Bool
    ) async {
        var remaining = timeoutMilliseconds
        while !condition(store), remaining > 0 {
            try? await Task.sleep(nanoseconds: 80_000_000)
            remaining -= 80
        }
    }

    private static func log(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }
}
