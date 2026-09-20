import AppKit
import SwiftUI

/// 菜单栏面板的离屏快照。
///
/// 菜单栏弹层不在窗口系统里：`screencapture` 抓不到它，自动化脚本也无法点开。
/// 这里用 `ImageRenderer` 直接渲染真实的 `MenuBarView`（读取真实运行时状态），
/// 便于设计评审与回归比对。
///
/// 用法：
/// ```bash
/// ENVPILOT_MENUBAR_SNAPSHOT=artifacts/menubar.png dist/ENVPilot.app/Contents/MacOS/ENVPilotApp
/// ```
/// 同时输出浅色 `menubar.png` 与深色 `menubar-dark.png`。
/// 未设置该环境变量时它完全不参与启动流程。
@MainActor
enum MenuBarSnapshot {
    static let environmentKey = "ENVPILOT_MENUBAR_SNAPSHOT"

    /// 入口：只有设置了环境变量才介入，且延迟到应用启动完成后再渲染。
    static func runIfRequested(store: NodeRuntimeStore) {
        guard let path = ProcessInfo.processInfo.environment[environmentKey], !path.isEmpty else {
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            Task {
                await render(store: store, to: URL(fileURLWithPath: path))
                NSApp.terminate(nil)
            }
        }
    }

    // MARK: Rendering

    private static func render(store: NodeRuntimeStore, to url: URL) async {
        await waitForRuntimeData(store)

        emit(renderLayer(store: store, scheme: .light), to: urlVariant(url, suffix: ""))
        emit(renderLayer(store: store, scheme: .dark), to: urlVariant(url, suffix: "-dark"))
    }

    /// 直接渲染真实的 `MenuBarView`（含面板外观）。刻意不绕过 `body`：
    /// 面板塌成细缝这类问题只出现在根部容器上，快照必须覆盖同一棵树。
    private static func renderLayer(store: NodeRuntimeStore, scheme: ColorScheme) -> CGImage? {
        let renderer = ImageRenderer(content: snapshotLayer(store: store, scheme: scheme))
        renderer.scale = 2
        renderer.isOpaque = false
        return renderer.cgImage
    }

    private static func snapshotLayer(store: NodeRuntimeStore, scheme: ColorScheme) -> some View {
        // 额外画布留白，让圆角与描边不被裁掉。
        ZStack(alignment: .topLeading) {
            Color.clear
                .frame(width: MenuBarView.panelWidth + 40, height: 560)
            MenuBarView(store: store, initialPicking: pickingFromEnvironment)
                .environment(\.colorScheme, scheme)
                .fixedSize(horizontal: false, vertical: true)
                .offset(x: 20, y: 20)
        }
    }

    /// 便于验收展开态：`ENVPILOT_MENUBAR_SNAPSHOT_PICK=node`。
    private static var pickingFromEnvironment: RuntimeKind? {
        guard let raw = ProcessInfo.processInfo.environment["ENVPILOT_MENUBAR_SNAPSHOT_PICK"] else {
            return nil
        }
        return RuntimeKind(rawValue: raw)
    }

    private static func emit(_ image: CGImage?, to url: URL) {
        guard let image else {
            FileHandle.standardError.write(Data("menubar snapshot: render failed\n".utf8))
            return
        }
        let rep = NSBitmapImageRep(cgImage: image)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            FileHandle.standardError.write(Data("menubar snapshot: png encode failed\n".utf8))
            return
        }
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: url)
            print("menubar snapshot → \(url.path)")
        } catch {
            FileHandle.standardError.write(Data("menubar snapshot: \(error.localizedDescription)\n".utf8))
        }
    }

    // MARK: Data readiness

    /// 等到一次真实的运行时读取完成，再做一次主动刷新以保证摘要派生也已结束。
    private static func waitForRuntimeData(_ store: NodeRuntimeStore) async {
        await waitUntil(store, timeoutMilliseconds: 20_000) { $0.snapshot != nil && !$0.isLoading }
        await store.refresh()
        await waitUntil(store, timeoutMilliseconds: 3_000) { !$0.isLoading }
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

    // MARK: Paths

    private static func urlVariant(_ url: URL, suffix: String) -> URL {
        let directory = url.deletingLastPathComponent()
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension.isEmpty ? "png" : url.pathExtension
        return directory.appendingPathComponent("\(base)\(suffix).\(ext)")
    }
}
