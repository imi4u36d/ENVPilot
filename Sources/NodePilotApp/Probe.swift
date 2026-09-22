#if DEBUG
import AppKit
import ENVPilotCore
import SwiftUI

/// 折叠卡顿的测量工具。默认完全不参与运行，只有 `ENVPILOT_PERF_PROBE=1` 时生效
/// （和 `WindowSnapshot` 一样的离屏工具路子）。
///
/// 它做四件事：
///
/// 1. **记录主线程被占住的时长**：心跳（间隔可调，默认 5ms）+ 两次心跳之间的间隔。
///    间隔明显变长就是主线程在连续干活，也就是肉眼看到的「卡一下」。标定阶段故意
///    占住主线程 120ms，用来确认这套测量本身有效。
/// 2. **反复触发折叠**。默认沿响应链发 `toggleSidebar:`；`TRIGGER=click` 会找到
///    标题栏那个按钮、往它身上投递一次真实鼠标点击——只有这条路径与用户手点等价。
/// 3. **统计 `body` 求值次数与标题栏压平次数**，用来判断某项开销是否真的落在
///    折叠这条路径上。
/// 4. **记录每一栏的 `minX:width`**，用来确认折叠到底发生没发生、有没有走动画。
///
/// 已经查清、别再用旧结论误导自己的四点：
/// - 点折叠按钮**不会**让任何页面 `body` 重新求值（8 次点击后 `root`/`overview`
///   的计数和 1 次点击时一样），所以页面里的重活不在动画路径上。
/// - 折叠完成后侧边栏那一栏会**保留展开宽度**、停在 `minX = 0`（被隐藏，直接盖在
///   内容列上）；只有分隔条的 `minX` 会从「展开宽度-3」变到 ~-3。按宽度判断开合，
///   结论一定是反的。
/// - 单击一次的动画是干净的（收起 0 次卡顿，展开偶尔 1 次 ~20ms）。**真正的毛病是
///   动画没跑完就再点一次**：AppKit 不会反向动画，而是把侧边栏一步弹到目标宽度
///   （实测 115pt → 展开宽度），内容列还会先铺成全宽（`minX:width = 0:1100`）再跳
///   回来。这就是「跳一下」。生产里由 `SidebarToggleGuard` 在事件层拦掉这种点击。
/// - 标题栏那个折叠按钮会**绕过 SwiftUI 的 `columnVisibility` binding** 直接改
///   AppKit 的 `NSSplitViewItem`（实测在 binding 的 set 里把改动全部排队，界面照样
///   在动画中途被弹走）；`NSApp.postEvent` 投进去的合成事件也**不会**经过
///   `NSEvent.addLocalMonitorForEvents`，所以用 `TRIGGER=click` 验不了那个 guard。
///
/// 环境变量：
/// - `ENVPILOT_PERF_PROBE=1` 打开探针（记录主线程占用）
/// - `ENVPILOT_PERF_MANUAL=1` 不自动折叠，留给人手点；这条路径不改窗口结构，
///   折叠按钮和动画都跟平时一样
/// - `ENVPILOT_PERF_TRIGGER=toolbar|click|cg|human|chain|appkit|menu` 触发方式。
///   `toolbar` 直接调用标准工具栏那个按钮的 target/action，是现在最接近手点的一条
///   （换成原生 `NSSplitViewController` 之后它是唯一能真正驱动折叠的入口）；
///   `click` 是把合成鼠标事件塞进本进程事件队列（绕过 local monitor）；
///   `cg` 走窗口服务器投真实 `CGEvent`（需要辅助功能权限，本机没给，实测点不动）；
///   `human` 在 `click` 基础上先挪光标、按下后隔 90ms 再抬起（复现真人按住的那段
///   嵌套 runloop）；`chain`/`appkit` 是向拆分视图发 `toggleSidebar:`（实验用，实测
///   不等于点按钮，别拿它的数字下结论）；`menu` 找主菜单里 action 为 `toggleSidebar:`
///   的菜单项。SwiftUI 自动塞的那条已经不要了（它本来就是空动作），换成「显示 ▸
///   切换侧边栏」，那条走 `WindowActions.toggleSidebar()` 直接调用控制器，
///   所以这条触发方式现在找不到任何菜单项，跑出来是 0 次折叠
/// - `ENVPILOT_PERF_FLIPS=24` / `ENVPILOT_PERF_GAP=450` 折叠次数与间隔（毫秒）。
///   `GAP` 小于动画时长（~240ms）时才是「动画没跑完又点一次」的场景
/// - `ENVPILOT_PERF_TICK_MS=5` 心跳间隔。测卡顿时别调大：间隔超过 20ms 的判定
///   阈值之后，每次心跳都会被算成一次卡顿
/// - `ENVPILOT_PERF_NO_WAIT=1` 不等首屏数据加载完就开始点
/// - `ENVPILOT_PERF_TRACE=1` 打印 RootView 折叠请求与 guard 判定（临时排查用）
/// - `ENVPILOT_PERF_FLOAT=1` 把窗口浮到最前，录屏取证时用
/// - `ENVPILOT_PERF_DUMP=1` 打印窗口视图树、主菜单与按钮命中链，然后退出
/// - `ENVPILOT_SIMPLE=sidebar|detail|both` 把某一栏换成空壳（跟探针无关，平时也能用）
/// - `ENVPILOT_PERF_SECTION=runtimes` 指定被测页面
/// - `ENVPILOT_PERF_SIZE=900x700` 指定窗口大小
@MainActor
enum PerfProbe {
    struct Settings {
        var continuous = false
        var manual = false
        var appkitTrigger = false
        var chainTrigger = false
        var buttonTrigger = false
        var menuTrigger = false
        var clickTrigger = false
        var cgTrigger = false
        var toolbarTrigger = false
        var humanTrigger = false
        var dump = false
        var section: AppSection?
        var windowSize: NSSize?
    }

    private(set) static var settings = Settings()

    static var isRunning: Bool {
        ProcessInfo.processInfo.environment["ENVPILOT_PERF_PROBE"] == "1"
    }

    /// 只把某一栏换成空壳，窗口结构和折叠按钮都保持原样：
    /// 用眼睛就能看出「卡顿是跟着哪一栏来的」。`ENVPILOT_SIMPLE=sidebar|detail|both`
    static var simpleSidebar: Bool {
        let value = ProcessInfo.processInfo.environment["ENVPILOT_SIMPLE"] ?? ""
        return value == "sidebar" || value == "both"
    }

    static var simpleDetail: Bool {
        let value = ProcessInfo.processInfo.environment["ENVPILOT_SIMPLE"] ?? ""
        return value == "detail" || value == "both"
    }

    /// 清掉拆分视图的 AppKit `autosaveName`，用来验证「动画没跑完再点一次会跳」
    /// 是不是 AppKit 把 autosave 的栏宽又塞回来了。
    static var clearsAutosave: Bool {
        ProcessInfo.processInfo.environment["ENVPILOT_PERF_NO_AUTOSAVE"] == "1"
    }

    static func log(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }

    /// 临时排查用：只有 `ENVPILOT_PERF_TRACE=1` 时打印。
    static func trace(_ message: String) {
        guard ProcessInfo.processInfo.environment["ENVPILOT_PERF_TRACE"] == "1" else {
            return
        }
        log("trace: " + message)
    }

    /// 各页面 `body` 被求值的次数。用来判断「点一次折叠按钮」到底会重算几次页面，
    /// 从而知道页面里的重活是不是真的落在折叠这条路径上。
    private(set) static var bodyEvaluations: [String: Int] = [:]

    static func noteBody(_ name: String) {
        guard isRunning else {
            return
        }
        bodyEvaluations[name, default: 0] += 1
    }

    /// `FlatTitleBarView.flatten()` 被调用的次数。它每次都去写窗口的标题栏属性，
    /// 如果这件事落在折叠动画的每一帧上，就是在反复让 AppKit 重算窗口外框。
    private(set) static var flattenCalls = 0

    static func noteFlatten() {
        guard isRunning else {
            return
        }
        flattenCalls += 1
    }

    /// 启动时读一次环境变量。
    static func load() {
        guard isRunning else {
            return
        }
        let environment = ProcessInfo.processInfo.environment
        settings.continuous = environment["ENVPILOT_PERF_FAST"] == "1"
        settings.manual = environment["ENVPILOT_PERF_MANUAL"] == "1"
        settings.appkitTrigger = environment["ENVPILOT_PERF_TRIGGER"] == "appkit"
        settings.chainTrigger = environment["ENVPILOT_PERF_TRIGGER"] == "chain"
        settings.buttonTrigger = environment["ENVPILOT_PERF_TRIGGER"] == "button"
        settings.menuTrigger = environment["ENVPILOT_PERF_TRIGGER"] == "menu"
        settings.clickTrigger = environment["ENVPILOT_PERF_TRIGGER"] == "click"
        settings.cgTrigger = environment["ENVPILOT_PERF_TRIGGER"] == "cg"
        settings.toolbarTrigger = environment["ENVPILOT_PERF_TRIGGER"] == "toolbar"
        settings.humanTrigger = environment["ENVPILOT_PERF_TRIGGER"] == "human"
        settings.dump = environment["ENVPILOT_PERF_DUMP"] == "1"
        settings.section = environment["ENVPILOT_PERF_SECTION"].flatMap(AppSection.init(rawValue:))
        if let raw = environment["ENVPILOT_PERF_SIZE"] {
            let parts = raw.lowercased().split(separator: "x").compactMap { Double($0) }
            if parts.count == 2, parts[0] > 400, parts[1] > 400 {
                settings.windowSize = NSSize(width: parts[0], height: parts[1])
            }
        }
    }

    static func runIfRequested(store: NodeRuntimeStore) {
        guard isRunning else {
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            Task {
                await run(store: store)
            }
        }
    }

    // MARK: 折叠触发

    /// 沿窗口的响应链找能处理 `toggleSidebar:` 的对象。
    /// 找得到就说明这个 App 的折叠走的是 AppKit 那条路（和系统侧边栏按钮一样），
    /// 用它来触发比改 SwiftUI 状态更接近真实点击。
    ///
    /// 返回对象本身而不是闭包：把 `AnyObject` 捕进 `@MainActor` 闭包里，Swift 6.3
    /// 会报 `SendingRisksDataRace`（本机 6.4 不报，CI 上直接编译失败）。
    private static func sidebarTogglers(in window: NSWindow) -> [(label: String, object: AnyObject)] {
        var found: [(String, AnyObject)] = []
        let selector = #selector(NSSplitViewController.toggleSidebar(_:))

        func check(_ object: AnyObject?, _ label: String) {
            guard let object else {
                return
            }
            let name = String(describing: type(of: object))
            if name.contains("NS") || name.contains("SwiftUI"), object.responds(to: selector) {
                found.append(("\(label): \(name)", object))
            }
        }

        if let controller = window.contentViewController {
            check(controller, "contentViewController")
            for child in controller.children {
                check(child, "child")
            }
        }
        var responder: NSResponder? = window.contentView
        var depth = 0
        while let current = responder, depth < 20 {
            check(current, "responder#\(depth)")
            responder = current.nextResponder
            depth += 1
        }
        if let split = WidthTracker.findSplit(in: window) {
            check(split.delegate, "split.delegate")
            check(split, "splitView")
        }
        return found
    }

    /// 不指定接收者：让 AppKit 自己沿响应链找，和系统给侧边栏按钮派发动作的方式一致。
    /// 返回值表示有没有人接手（false 就是没人管这个动作）。
    private static func chainToggle(in window: NSWindow) -> (() -> Bool) {
        let selector = #selector(NSSplitViewController.toggleSidebar(_:))
        return {
            NSApp.sendAction(selector, to: nil, from: nil)
        }
    }

    /// 标准工具栏里那个「伸缩按钮」的动作。AppKit 给
    /// `NSToolbarItem.Identifier.toggleSidebar` 装好的 target/action 就是点它的真实路径，
    /// 比自己造一个 `toggleSidebar:` 更接近用户。
    private static func toolbarToggleAction(in window: NSWindow) -> (() -> Void)? {
        guard let item = window.toolbar?.items.first(where: { $0.action != nil }) else {
            return nil
        }
        return { [weak item] in
            guard let item, let action = item.action else {
                return
            }
            NSApp.sendAction(action, to: item.target, from: item)
        }
    }

    /// 真正能「点」的那个控件：标题栏里 `action` 为 `toggleSidebar:` 的按钮。
    /// `performClick` 走的就是鼠标点下去那条路，比向拆分视图发消息更接近真实点击。
    private static func toggleControls(in window: NSWindow) -> [NSControl] {
        let selector = #selector(NSSplitViewController.toggleSidebar(_:))
        var found: [NSControl] = []
        func walk(_ view: NSView, depth: Int) {
            guard depth <= 30 else {
                return
            }
            if let control = view as? NSControl, control.action == selector {
                found.append(control)
            }
            for sub in view.subviews {
                walk(sub, depth: depth + 1)
            }
        }
        if let root = window.contentView?.superview ?? window.contentView {
            walk(root, depth: 0)
        }
        return found
    }

    /// 主菜单里那个 `Toggle Sidebar` 菜单项。标题栏按钮和它发的是同一个 `toggleSidebar:`，
    /// 但菜单项能拿到明确的 target，可以原样派发，是最接近点按钮的可编程入口。
    private static func toggleMenuItem() -> NSMenuItem? {
        let selector = #selector(NSSplitViewController.toggleSidebar(_:))
        var result: NSMenuItem?
        func search(_ menu: NSMenu) {
            for item in menu.items {
                if item.action == selector {
                    result = item
                    return
                }
                if let submenu = item.submenu {
                    search(submenu)
                }
                if result != nil {
                    return
                }
            }
        }
        if let menu = NSApp.mainMenu {
            search(menu)
        }
        return result
    }

    /// 标题栏里那个真正的折叠按钮。它不是 `NSControl`（`action` 是 nil，点击由
    /// SwiftUI 的宿主视图自己处理），所以只能找出视图、往它身上丢一次真实鼠标事件。
    private static func toolbarToggleButton(in window: NSWindow) -> NSView? {
        guard let root = window.contentView?.superview else {
            return nil
        }
        var result: NSView?
        func walk(_ view: NSView, insideToolbar: Bool, depth: Int) {
            guard result == nil, depth <= 30 else {
                return
            }
            let nowInsideToolbar = insideToolbar || String(describing: type(of: view)) == "NSToolbarView"
            if nowInsideToolbar, String(describing: type(of: view)).contains("SwiftUIAppKitButton") {
                result = view
                return
            }
            for sub in view.subviews {
                walk(sub, insideToolbar: nowInsideToolbar, depth: depth + 1)
            }
        }
        walk(root, insideToolbar: false, depth: 0)
        return result
    }

    /// 往按钮中心投递一对真实的 mouseDown / mouseUp。事件只进本进程的事件队列，
    /// 不需要任何辅助功能权限，走的也是 AppKit 正常的命中与派发路径。
    private static func click(_ view: NSView, in window: NSWindow) {
        let pointInView = NSPoint(x: view.bounds.midX, y: view.bounds.midY)
        let pointInWindow = view.convert(pointInView, to: nil)
        let timestamp = ProcessInfo.processInfo.systemUptime
        for (type, pressure) in [(NSEvent.EventType.leftMouseDown, Float(1)), (NSEvent.EventType.leftMouseUp, Float(0))] {
            guard let event = NSEvent.mouseEvent(
                with: type,
                location: pointInWindow,
                modifierFlags: [],
                timestamp: timestamp,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: 0,
                clickCount: 1,
                pressure: pressure
            ) else {
                continue
            }
            NSApp.postEvent(event, atStart: false)
        }
    }

    /// 走窗口服务器的真实点击（`CGEvent`）。和人手点击一样会被 local event monitor
    /// 看到，因此能用来验证 `SidebarToggleGuard`；`NSApp.postEvent` 那条路绕过了
    /// local monitor，验不了。
    private static func cgClick(_ view: NSView, in window: NSWindow) -> Bool {
        guard let screen = window.screen ?? NSScreen.main else {
            return false
        }
        let pointInWindow = view.convert(NSPoint(x: view.bounds.midX, y: view.bounds.midY), to: nil)
        let screenPoint = window.convertPoint(toScreen: pointInWindow)
        let cursor = CGPoint(x: screenPoint.x, y: screen.frame.maxY - screenPoint.y)
        CGWarpMouseCursorPosition(cursor)
        guard let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: cursor, mouseButton: .left),
              let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: cursor, mouseButton: .left) else {
            return false
        }
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }

    /// 尽量还原人手的一次点击：先把光标真的挪到按钮上，投一个 mouseMoved，
    /// 按下之后**隔一段时间**再抬起（让按钮的 tracking loop 真的跑起来）。
    ///
    /// `postEvent` 把 down/up 背靠背塞进队列时，AppKit 不会走按住跟踪那一段
    /// 嵌套 runloop，动画是在一个干净的 runloop 里起步的；真人点击不是。
    /// 要复现「只有我点才卡」，这一步不能省。
    private static func humanClick(_ view: NSView, in window: NSWindow, holdMilliseconds: Int) {
        let pointInView = NSPoint(x: view.bounds.midX, y: view.bounds.midY)
        let pointInWindow = view.convert(pointInView, to: nil)
        let screenPoint = window.convertPoint(toScreen: pointInWindow)
        if let screen = window.screen ?? NSScreen.main {
            CGWarpMouseCursorPosition(NSPoint(x: screenPoint.x, y: screen.frame.maxY - screenPoint.y))
            CGAssociateMouseAndMouseCursorPosition(1)
        }
        func mouse(_ type: NSEvent.EventType, pressure: Float) -> NSEvent? {
            NSEvent.mouseEvent(
                with: type,
                location: pointInWindow,
                modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: 0,
                clickCount: 1,
                pressure: pressure
            )
        }
        if let moved = mouse(.mouseMoved, pressure: 0) {
            NSApp.postEvent(moved, atStart: false)
        }
        if let down = mouse(.leftMouseDown, pressure: 1) {
            NSApp.postEvent(down, atStart: false)
        }
        guard let up = mouse(.leftMouseUp, pressure: 0) else {
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(holdMilliseconds)) {
            NSApp.postEvent(up, atStart: false)
        }
    }

    /// 把窗口视图树里所有控件、以及主菜单打印出来，用来定位折叠按钮。
    private static func dumpWindow(_ window: NSWindow, buttons: [NSControl]) async {
        let selector = #selector(NSSplitViewController.toggleSidebar(_:))

        func describe(_ view: NSView) -> String {
            var parts = [String(describing: type(of: view)), "frame=\(NSStringFromRect(view.frame))"]
            if view.responds(to: selector) {
                parts.append("RESPONDS-TOGGLE")
            }
            if let control = view as? NSControl {
                parts.append("action=\(control.action.map(NSStringFromSelector) ?? "nil")")
                if let target = control.target {
                    parts.append("target=\(String(describing: type(of: target)))")
                }
                if let button = view as? NSButton {
                    parts.append("title=\"\(button.title)\"")
                }
            }
            return parts.joined(separator: " ")
        }

        func walk(_ view: NSView, depth: Int) {
            guard depth <= 30 else {
                return
            }
            log(String(repeating: "  ", count: depth) + describe(view))
            for sub in view.subviews {
                walk(sub, depth: depth + 1)
            }
        }

        log("=== window hierarchy ===")
        if let root = window.contentView?.superview ?? window.contentView {
            walk(root, depth: 0)
        }
        log("=== main menu ===")
        if let menu = NSApp.mainMenu {
            for item in menu.items {
                log("menu: \(item.title)")
                for sub in item.submenu?.items ?? [] {
                    log("  item: \(sub.title) action=\(sub.action.map(NSStringFromSelector) ?? "nil") target=\(sub.target.map { String(describing: type(of: $0)) } ?? "nil") enabled=\(sub.isEnabled)")
                }
            }
        }
        if ProcessInfo.processInfo.environment["ENVPILOT_PERF_SETTINGS_PROBE"] == "1" {
            // 设置入口的回归检查：直接走生产路径 `WindowActions.openSettings()`，
            // 看它到底开没开出设置窗口。历史上这里坏过一次——`showSettingsWindow:`
            // 返回 true 但什么都不做，从界面上只看得到「按钮点了没反应」。
            let before = Set(NSApp.windows.map { "\($0.className)|\($0.title)" })
            WindowActions.openSettings()
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            let added = NSApp.windows.map { "\($0.className)|\($0.title)" }.filter { !before.contains($0) }
            log("=== settings probe ===")
            log(added.isEmpty ? "  FAIL 没有新窗口（设置入口又断了）" : "  OK 新窗口: \(added.joined(separator: " / "))")
        }
        log("=== hit test at toggle button ===")
        if let button = buttons.first ?? toolbarToggleButton(in: window),
           let root = window.contentView?.superview {
            let pointInWindow = button.convert(NSPoint(x: button.bounds.midX, y: button.bounds.midY), to: nil)
            let point = root.convert(pointInWindow, from: nil)
            var hit = root.hitTest(point)
            var chain: [String] = []
            while let current = hit {
                chain.append(String(describing: type(of: current)))
                hit = current.superview
            }
            log("  hit chain: \(chain.prefix(8).joined(separator: " < "))")
            log("  contains NSToolbarView: \(chain.contains("NSToolbarView"))")
        }
        log("=== toggle controls ===")
        for button in buttons {
            log("  \(String(describing: type(of: button))) frame=\(NSStringFromRect(button.frame)) target=\(button.target.map { String(describing: type(of: $0)) } ?? "nil")")
        }
        if let split = WidthTracker.findSplit(in: window) {
            log("=== split view ===")
            log("  autosaveName=\(split.autosaveName.map { String(describing: $0) } ?? "nil") dividerStyle=\(split.dividerStyle.rawValue)")
            for (index, sub) in split.subviews.enumerated() {
                log("  [\(index)] \(String(describing: type(of: sub))) hidden=\(sub.isHidden) frame=\(NSStringFromRect(sub.frame))")
            }
        }
    }

    // MARK: Run

    private static func run(store: NodeRuntimeStore) async {
        var waited = 0
        // 默认等首屏数据加载完再开测；`ENVPILOT_PERF_NO_WAIT=1` 则抢在加载中途点，
        // 用来验证「人一打开 app 就去点按钮」是不是卡顿的来源。
        let skipWait = ProcessInfo.processInfo.environment["ENVPILOT_PERF_NO_WAIT"] == "1"
        while !skipWait, (store.snapshot == nil || store.isLoading), waited < 250 {
            try? await Task.sleep(nanoseconds: 80_000_000)
            waited += 80
        }
        guard let window = targetWindow() else {
            log("probe: no window")
            NSApp.terminate(nil)
            return
        }
        if let size = settings.windowSize {
            window.setContentSize(size)
        }
        // 录屏取证时把窗口浮到最前，免得被别的 App 盖住（只影响层叠顺序）。
        if ProcessInfo.processInfo.environment["ENVPILOT_PERF_FLOAT"] == "1" {
            window.level = .floating
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        try? await Task.sleep(nanoseconds: 500_000_000)

        let buttons = toggleControls(in: window)
        if clearsAutosave, let split = WidthTracker.findSplit(in: window) {
            log("清掉拆分视图 autosaveName：\(split.autosaveName.map { String(describing: $0) } ?? "nil")")
            split.autosaveName = nil
        }
        if settings.dump {
            await dumpWindow(window, buttons: buttons)
            NSApp.terminate(nil)
            return
        }

        let recorder = StallRecorder()
        let tracker = WidthTracker(window: window)
        let tracker0 = tracker
        log("mode: \(settings)")
        // 心跳间隔可调：5ms 的心跳本身就会把主线程频繁叫醒，测卡顿时要能把这个干扰关小。
        let tickMilliseconds = ProcessInfo.processInfo.environment["ENVPILOT_PERF_TICK_MS"]
            .flatMap { Double($0) } ?? 5
        let timer = Timer(timeInterval: tickMilliseconds / 1000, repeats: true) { _ in
            MainActor.assumeIsolated {
                recorder.tick()
                tracker.tick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)

        if let raw = ProcessInfo.processInfo.environment["ENVPILOT_PERF_START_DELAY_MS"], let ms = UInt64(raw) {
            try? await Task.sleep(nanoseconds: ms * 1_000_000)
        }

        recorder.begin(phase: "idle")
        try? await Task.sleep(nanoseconds: 1_000_000_000)

        // 标定：主线程连续占住 120ms，确认这套测量本身测得出来
        recorder.begin(phase: "calib")
        let busyDeadline = DispatchTime.now().uptimeNanoseconds + 120_000_000
        while DispatchTime.now().uptimeNanoseconds < busyDeadline {}
        try? await Task.sleep(nanoseconds: 400_000_000)

        if settings.manual {
            // 手动模式：前 5 秒请什么都别做（基线），然后分三段点折叠按钮
            recorder.begin(phase: "别动（基线）")
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            for index in 0..<3 {
                recorder.begin(phase: "点击\(index + 1)")
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
            timer.invalidate()
            report(recorder: recorder)
            NSApp.terminate(nil)
            return
        }

        let togglers = sidebarTogglers(in: window)
        let menuItem = toggleMenuItem()
        let clickTarget = toolbarToggleButton(in: window)
        let toolbarToggle = toolbarToggleAction(in: window)
        if let item = window.toolbar?.items.first(where: { $0.action != nil }) {
            log("标准工具栏开关：identifier=\(item.itemIdentifier.rawValue) action=\(item.action.map(NSStringFromSelector) ?? "nil") target=\(item.target.map { String(describing: type(of: $0)) } ?? "nil")")
        } else {
            log("标准工具栏开关：没找到（window.toolbar=\(window.toolbar == nil ? "nil" : "有")，items=\(window.toolbar?.items.count ?? 0)）")
        }
        let chainToggle = settings.chainTrigger ? chainToggle(in: window) : nil
        if let chainToggle {
            let handled = chainToggle()
            try? await Task.sleep(nanoseconds: 400_000_000)
            log("响应链处理了这个动作：\(handled)，侧边栏现在\(tracker0.isSidebarOpen ? "是开的" : "已收起")")
        }
        log("响应链上能处理 toggleSidebar: 的接收者：\(togglers.isEmpty ? "没有" : togglers.map(\.label).joined(separator: " | "))")
        log("Toggle Sidebar 菜单项：\(menuItem == nil ? "没有" : "有，target=\(menuItem!.target.map { String(describing: type(of: $0)) } ?? "nil") enabled=\(menuItem!.isEnabled)")")
        log("标题栏折叠按钮：\(clickTarget == nil ? "没找到" : "找到 \(String(describing: type(of: clickTarget!)))")")
        log("触发方式：\(settings.toolbarTrigger ? "标准工具栏按钮的 action" : (chainToggle != nil ? "沿响应链发 toggleSidebar:" : (settings.humanTrigger ? "模拟人手点击（移光标+按住90ms）" : (settings.clickTrigger ? "合成鼠标事件点按钮" : (settings.menuTrigger ? "菜单项 toggleSidebar:" : (settings.buttonTrigger ? "点击标题栏按钮" : "直接发给拆分视图"))))))，找到按钮 \(buttons.count) 个")
        log("能处理 toggleSidebar: 的对象：\(togglers.isEmpty ? "没有" : togglers.map(\.label).joined(separator: " | "))")

        // 分方向统计：收起和展开走的不是同一条路（展开要把侧边栏内容重新铺出来）
        recorder.begin(phase: "收起")
        // 走 AppKit 触发时分不清方向，统一记在 toggle 名下
        let environment = ProcessInfo.processInfo.environment
        let gap: UInt64 = environment["ENVPILOT_PERF_GAP"]
            .flatMap { UInt64($0) }
            .map { $0 * 1_000_000 }
            ?? (settings.continuous ? 60_000_000 : 450_000_000)
        let flips = environment["ENVPILOT_PERF_FLIPS"].flatMap { Int($0) }
            ?? (settings.continuous ? 80 : 24)
        for _ in 0..<flips {
            // 看当前状态决定这次是「收起」还是「展开」
            recorder.begin(phase: tracker.isSidebarOpen ? "收起" : "展开")
            if let chain = chainToggle {
                _ = chain()
            } else if settings.toolbarTrigger, let toolbarToggle {
                toolbarToggle()
            } else if settings.cgTrigger, let target = clickTarget {
                _ = cgClick(target, in: window)
            } else if settings.clickTrigger, let target = clickTarget {
                click(target, in: window)
            } else if settings.humanTrigger, let target = clickTarget {
                humanClick(target, in: window, holdMilliseconds: 90)
            } else if settings.menuTrigger, let item = menuItem, let action = item.action {
                _ = NSApp.sendAction(action, to: item.target, from: item)
            } else if settings.buttonTrigger, let button = buttons.first {
                button.performClick(nil)
            } else if settings.appkitTrigger, let toggler = togglers.first {
                _ = NSApp.sendAction(#selector(NSSplitViewController.toggleSidebar(_:)), to: toggler.object, from: nil)
            } else {
                log("没有可用的触发方式：用 TRIGGER=toolbar（标准工具栏按钮）")
            }
            try? await Task.sleep(nanoseconds: gap)
        }
        log("collapse 期间侧栏宽度变化：\(tracker.timeline())")

        // 对照：只改窗口宽度。同样的重排，但没有列折叠。
        recorder.begin(phase: "只改窗口宽度")
        let wide = window.frame.size
        for index in 0..<6 {
            let narrow = NSSize(width: wide.width - 220, height: wide.height)
            let size = index.isMultiple(of: 2) ? narrow : wide
            window.setFrame(NSRect(origin: window.frame.origin, size: size), display: true)
            try? await Task.sleep(nanoseconds: 600_000_000)
        }
        timer.invalidate()

        report(recorder: recorder)
        log("collapse 结束时各栏 minX:width：\(tracker.layoutDump())")
        log("resize 期间侧栏宽度变化：\(tracker.timeline())")
        NSApp.terminate(nil)
    }

    private static func report(recorder: StallRecorder) {
        for (phase, stat) in recorder.snapshot().sorted(by: { $0.key < $1.key }) {
            log("[\(phase)] 卡顿 \(stat.count) 次 / \(String(format: "%.1f", stat.total)) ms（最大 \(String(format: "%.1f", stat.max)) ms）")
        }
        let bodies = bodyEvaluations.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }
        log("body 求值次数：\(bodies.isEmpty ? "无" : bodies.joined(separator: " "))")
        log("FlatTitleBar flatten 次数：\(flattenCalls)")
    }

    private static func targetWindow() -> NSWindow? {
        NSApp.windows.first { $0.frame.width > 400 && $0.contentView != nil }
    }
}

/// 主线程占用记录器。
@MainActor
final class StallRecorder {
    struct Stat {
        var count = 0
        var total: Double = 0
        var max: Double = 0
        /// 坑出现在哪个时刻（距离该阶段开始多少毫秒）
        var at: [Double] = []
    }

    private var phase = "idle"
    private var last = DispatchTime.now()
    private var phaseStart = DispatchTime.now().uptimeNanoseconds
    private var stats: [String: Stat] = [:]

    /// 切到某个阶段名下面继续累计（同一个名字可以出现多次）。
    func begin(phase newPhase: String) {
        phase = newPhase
        if stats[newPhase] == nil {
            stats[newPhase] = Stat()
        }
    }

    /// 重新开一个同名阶段，时刻从头算（比如「展开」一共做 12 次）。
    func restart(phase newPhase: String) {
        phase = newPhase
        phaseStart = DispatchTime.now().uptimeNanoseconds
        if stats[newPhase] == nil {
            stats[newPhase] = Stat()
        }
    }

    func tick() {
        let now = DispatchTime.now()
        let gap = Double(now.uptimeNanoseconds - last.uptimeNanoseconds) / 1_000_000
        last = now
        guard gap > 20 else {
            return
        }
        let at = Double(now.uptimeNanoseconds - phaseStart) / 1_000_000
        var stat = stats[phase] ?? Stat()
        stat.count += 1
        stat.total += gap
        stat.max = max(stat.max, gap)
        if stat.at.count < 30 {
            stat.at.append(at)
        }
        stats[phase] = stat
    }

    func snapshot() -> [String: Stat] {
        stats
    }
}

/// 侧边栏宽度随时间的变化：折叠到底有没有发生、有没有走动画。
///
/// 必须同时记 `minX`：折叠完成后 `_NSSplitViewItemViewWrapper` 会带着 220pt 的
/// 宽度整体挪到窗口左侧外面（`minX < 0`），只看宽度会把「已收起」误判成「展开」，
/// 早先按宽度判断开合状态的结论都是被这一点带偏的。
@MainActor
final class WidthTracker {
    private struct Sample {
        var t: Double
        var layout: String
    }

    private let startTime = DispatchTime.now().uptimeNanoseconds
    private var samples: [Sample] = []
    private var lastLayout: [Int] = []
    private weak var split: NSSplitView?

    init(window: NSWindow) {
        split = Self.findSplit(in: window)
    }

    /// 折叠没折叠，看分隔条的位置，而不是侧边栏的宽度。
    ///
    /// 实测：动画结束后 `_NSSplitViewItemViewWrapper` 会保留 220pt 宽度、停在
    /// `minX = 0`（直接盖在内容列上面，只是被隐藏了），而分隔条从 `minX≈217`
    /// 移到 `minX≈-3`。所以「宽度 220」在展开和收起两种状态下都成立，用宽度判断
    /// 开合的结论都是反的。
    var isSidebarOpen: Bool {
        guard let split else {
            return false
        }
        let divider = split.subviews.first { $0.frame.width > 0.5 && $0.frame.width < 8 }
        return (divider?.frame.minX ?? 0) > 60
    }

    static func findSplit(in window: NSWindow) -> NSSplitView? {
        guard let content = window.contentView else {
            return nil
        }
        var result: NSSplitView?
        func walk(_ view: NSView, depth: Int) {
            if result != nil || depth > 18 {
                return
            }
            if let candidate = view as? NSSplitView, candidate.subviews.count >= 2 {
                let widths = candidate.subviews.map { $0.frame.width }
                if widths.contains(where: { $0 > 150 && $0 < 400 }) {
                    result = candidate
                    return
                }
            }
            for sub in view.subviews {
                walk(sub, depth: depth + 1)
            }
        }
        walk(content, depth: 0)
        return result
    }

    func tick() {
        guard let split else {
            return
        }
        // 只在几何真的变了的时候记一笔：既让 timeline 只表达变化，
        // 也避免 200 次/秒的字符串格式化把主线程本身拖慢（测卡顿时这是自干扰）。
        var layout: [Int] = []
        for sub in split.subviews {
            layout.append(Int(sub.frame.minX.rounded()))
            layout.append(Int(sub.frame.width.rounded()))
        }
        guard layout != lastLayout else {
            return
        }
        lastLayout = layout
        let t = Double(DispatchTime.now().uptimeNanoseconds - startTime) / 1_000_000
        var parts: [String] = []
        for index in stride(from: 0, to: layout.count, by: 2) {
            parts.append("\(layout[index]):\(layout[index + 1])")
        }
        samples.append(Sample(t: t, layout: parts.joined(separator: ",")))
    }

    func timeline() -> String {
        samples.prefix(400).map { String(format: "%.0f:[%@]", $0.t, $0.layout) }.joined(separator: " → ")
    }

    /// 当前每一栏的 `minX:width`，用来核对折叠后侧边栏到底停在哪。
    func layoutDump() -> String {
        guard let split else {
            return "no split"
        }
        return split.subviews
            .map { String(format: "(%.0f,%.0f)", $0.frame.minX, $0.frame.width) }
            .joined(separator: " ")
    }
}

/// 开机自启动的一次性验证工具。默认不参与运行，只有 `ENVPILOT_LOGIN_PROBE` 给了值才生效。
///
/// 为什么需要它：登录项只有在 `.app` 里、带着实际签名才注册得上去，「代码编译通过」
/// 和「系统真的把它记下了」是两件事，后者光看代码看不出来。这条把三态读出来：
///
/// - `ENVPILOT_LOGIN_PROBE=status` 只打印当前状态
/// - `ENVPILOT_LOGIN_PROBE=on` / `off` 注册或注销，然后回读一次
///
/// 跑法（必须在 `.app` 里跑，裸二进制只会得到「不可用」）：
/// ```bash
/// ENVPILOT_LOGIN_PROBE=on ./dist/ENVPilot.app/Contents/MacOS/ENVPilotApp
/// ```
@MainActor
enum LoginItemProbe {
    static let environmentKey = "ENVPILOT_LOGIN_PROBE"

    static func runIfRequested() {
        guard let mode = ProcessInfo.processInfo.environment[environmentKey], !mode.isEmpty else {
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            let service = LoginItemService()
            func line(_ text: String) {
                FileHandle.standardError.write(Data(("login-probe: " + text + "\n").utf8))
            }
            line("mode=\(mode) bundle=\(Bundle.main.bundlePath)")
            line("初始状态 \(describe(service.status()))")
            if mode == "on" || mode == "off" {
                switch service.setEnabled(mode == "on") {
                case .success:
                    line("setEnabled(\(mode == "on")) 调用成功")
                case .failure(let error):
                    line("setEnabled 失败 → \(error.reason)")
                }
                line("回读 \(describe(service.status()))")
            }
            NSApp.terminate(nil)
        }
    }

    private static func describe(_ status: LoginItemService.Status) -> String {
        switch status {
        case .enabled:
            return "已开启"
        case .disabled:
            return "未开启"
        case .unavailable(let reason):
            return "不可用（\(reason)）"
        }
    }
}

#else

// Release 构建下这些探针整体不存在：它们是开发期排查折叠卡顿、离线出图和验证设置入口
// 用的工具，没有理由把上千行诊断代码、以及每次 body 求值都要跑一遍的环境变量检查
// 带进发布包。需要它们时用调试构建（`swift build` / `swift run`）。

import AppKit

/// 发布构建下的空实现（见文件顶部说明）。
@MainActor
enum PerfProbe {
    struct Settings {
        var section: AppSection?
    }

    static var settings = Settings()
    static var simpleSidebar: Bool { false }
    static var simpleDetail: Bool { false }

    static func load() {}
    static func runIfRequested(store: NodeRuntimeStore) {}
    static func noteBody(_ name: String) {}
    static func noteFlatten() {}
    static func trace(_ message: String) {}
}

@MainActor
enum LoginItemProbe {
    static func runIfRequested() {}
}

#endif
