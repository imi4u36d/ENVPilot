import AppKit
import SwiftUI

/// 左右两栏用 AppKit 原生的 `NSSplitViewController` 承载。
///
/// 为什么不再用 `NavigationSplitView`：在这台机器（macOS 27）上它**不是**
/// `NSSplitViewController`，而是 SwiftUI 自己拿 `NSSplitView` +
/// `_NSSplitViewItemViewWrapper` 拼的一套（窗口视图树里一个 `NSSplitViewController`
/// 都没有）。那套折叠动画有两个毛病：
///
/// 1. 动画没跑完再点一次**不会反向重定向**，而是把侧边栏一步弹到目标宽度
///    （实测折叠到 115pt 时再点一次，侧边栏直接回到 220pt，内容列还会先被铺成
///    全宽 `minX:width = 0:1100` 再跳回来）；
/// 2. 标题栏那个开关**直接改 AppKit 的 item**，绕过 SwiftUI 的
///    `columnVisibility` binding（在 binding 的 `set` 里把改动全部排队也拦不住）。
///
/// 换成原生 `NSSplitViewController` 之后，折叠/展开、标题栏那个开关、拖拽调宽全部
/// 回到系统实现上：开关由 `NSSplitViewItem` 的折叠状态驱动，动画是系统侧边栏那一套，
/// 打断行为也由 AppKit 自己处理。
struct NativeSidebarShell<Sidebar: View, Detail: View>: NSViewControllerRepresentable {
    var minimumSidebarWidth: CGFloat = 190
    var maximumSidebarWidth: CGFloat = 340
    /// 与重做前实际渲染出来的侧边栏宽度保持一致（SwiftUI 那边给的是 ideal 214，
    /// 实际排到 220），避免换实现之后视觉上有肉眼可见的位移。
    var initialSidebarWidth: CGFloat = 220
    var sidebar: Sidebar
    var detail: Detail

    func makeNSViewController(context: Context) -> SidebarSplitViewController<Sidebar, Detail> {
        SidebarSplitViewController(
            sidebar: sidebar,
            detail: detail,
            minimumSidebarWidth: minimumSidebarWidth,
            maximumSidebarWidth: maximumSidebarWidth,
            initialSidebarWidth: initialSidebarWidth
        )
    }

    func updateNSViewController(_ controller: SidebarSplitViewController<Sidebar, Detail>, context: Context) {
        controller.update(sidebar: sidebar, detail: detail)
    }
}

/// 非泛型的基类：泛型类不能声明 `@objc` 成员，而工具栏项需要一个 selector，
/// 所以把折叠动作放在这里，泛型的 controller 继承它。
@MainActor
class SidebarToggleController: NSSplitViewController {
    /// 折叠/展开侧边栏。
    ///
    /// 没用 `NSSplitViewController.toggleSidebar(_:)`：它只对「真正的 sidebar item」
    /// （`NSSplitViewItem(sidebarWithViewController:)`）生效，而那个类型会让 AppKit 把
    /// 工具栏项摆到侧边栏右边界（x≈216）而不是红绿灯右边。这里直接动 item 的
    /// `isCollapsed`。
    ///
    /// 动画必须写成显式的 `NSAnimationContext`：只写 `animator().isCollapsed` 时，
    /// 启动后的**第一次**折叠会被直接应用（release 构建实测 220pt 一步变 0，没有动画），
    /// 之后的才走动画。显式给出时长与 `allowsImplicitAnimation` 就没有这个问题。
    @objc func toggleSidebarAction(_ sender: Any?) {
        guard let item = splitViewItems.first else {
#if DEBUG
            PerfProbe.trace("toggle: no split items")
#endif
            return
        }
        let collapsed = !item.isCollapsed
#if DEBUG
        PerfProbe.trace("toggle: items=\(splitViewItems.count) collapsed=\(item.isCollapsed) -> \(collapsed)")
#endif
        // 折叠状态要跨启动保留：以前关掉应用再打开，侧边栏总是重新展开。
        UserDefaults.standard.set(collapsed, forKey: Self.collapsedStateKey)
        // 推迟到下一轮 runloop 再起动画。窗口刚被程序改过尺寸时，这一轮往往还在布局
        // 事务里，隐式动画会被吞掉（实测：改完尺寸紧接着点第一次，折叠会一步到位、
        // 没有动画）。提交掉挂起的布局再起动画就稳定了。
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }
            self.splitView.layoutSubtreeIfNeeded()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = Self.collapseAnimationDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                context.allowsImplicitAnimation = true
                item.animator().isCollapsed = collapsed
            }
        }
    }

    /// 与系统侧边栏折叠动画相当的时长。
    static let collapseAnimationDuration: TimeInterval = 0.25
    /// 折叠状态的持久化键。
    static var collapsedStateKey: String { AppStateKey.sidebarCollapsed }
    /// 侧边栏宽度是否已经写过设计值。只在第一次启动时套用设计宽度。
    static var widthInitializedKey: String { AppStateKey.sidebarWidthInitialized }
}

@MainActor
final class SidebarSplitViewController<Sidebar: View, Detail: View>: SidebarToggleController {
    private let sidebarHost: NSHostingController<Sidebar>
    private let detailHost: NSHostingController<Detail>
    private let sidebarItem: NSSplitViewItem
    private let initialSidebarWidth: CGFloat
    private var didApplyInitialWidth = false
    private var didRestoreCollapseState = false
    private let toolbarDelegate = SidebarToolbarDelegate()
    private var toolbarIdentifier: NSToolbar.Identifier { "ENVPilotMainToolbar" }

    init(
        sidebar: Sidebar,
        detail: Detail,
        minimumSidebarWidth: CGFloat,
        maximumSidebarWidth: CGFloat,
        initialSidebarWidth: CGFloat
    ) {
        self.sidebarHost = NSHostingController(rootView: sidebar)
        self.detailHost = NSHostingController(rootView: detail)
        self.initialSidebarWidth = initialSidebarWidth
        self.sidebarItem = NSSplitViewItem(viewController: sidebarHost)
        super.init(nibName: nil, bundle: nil)

        // 让 AppKit 按列宽决定布局，而不是被 SwiftUI 内容的固有尺寸牵着走。
        sidebarHost.sizingOptions = []
        detailHost.sizingOptions = []

        sidebarItem.canCollapse = true
        sidebarItem.minimumThickness = minimumSidebarWidth
        sidebarItem.maximumThickness = maximumSidebarWidth
        // 侧边栏一直铺到窗口顶端：红绿灯是浮在它上面的。
        sidebarItem.allowsFullHeightLayout = true
        sidebarItem.holdingPriority = .init(260)

        let contentItem = NSSplitViewItem(viewController: detailHost)
        contentItem.minimumThickness = 400

        addSplitViewItem(sidebarItem)
        addSplitViewItem(contentItem)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// 页面状态变了就换掉两栏的 SwiftUI 内容。类型不变（`Sidebar`/`Detail` 稳定），
    /// 所以页面里的 `@State`（展开态、滚动位置等）仍然由 SwiftUI 按结构身份保留。
    func update(sidebar: Sidebar, detail: Detail) {
        sidebarHost.rootView = sidebar
        detailHost.rootView = detail
    }

    /// 折叠/展开由基类的 `toggleSidebarAction(_:)` 负责（泛型类不能声明 `@objc`）。

    override func viewDidAppear() {
        super.viewDidAppear()
        restorePersistedCollapseStateIfNeeded()
        applyInitialSidebarWidthIfNeeded()
        installToolbarIfNeeded()
    }

    /// 恢复上次退出时的折叠状态。
    private func restorePersistedCollapseStateIfNeeded() {
        guard !didRestoreCollapseState else {
            return
        }
        didRestoreCollapseState = true
        guard UserDefaults.standard.object(forKey: SidebarToggleController.collapsedStateKey) != nil else {
            return
        }
        sidebarItem.isCollapsed = UserDefaults.standard.bool(forKey: SidebarToggleController.collapsedStateKey)
    }

    /// 首次布局时把侧边栏定到设计宽度。
    ///
    /// 以前每次启动都无条件 `setPosition`：既覆盖掉 AppKit 可能已经恢复的宽度，也从来没设
    /// `autosaveName`，于是用户拖出来的宽度活不过一次重启。现在交给 autosave，只有从来没
    /// 初始化过（本机第一次启动）才套用设计值。
    private func applyInitialSidebarWidthIfNeeded() {
        guard !didApplyInitialWidth, splitView.subviews.count >= 2 else {
            return
        }
        didApplyInitialWidth = true
        splitView.autosaveName = "ENVPilotMainSplit"
        guard !UserDefaults.standard.bool(forKey: SidebarToggleController.widthInitializedKey) else {
            return
        }
        UserDefaults.standard.set(true, forKey: SidebarToggleController.widthInitializedKey)
        splitView.setPosition(initialSidebarWidth, ofDividerAt: 0)
    }

    /// 给窗口装一条只放折叠按钮的工具栏，位置就是红绿灯右边那一个按钮。
    private func installToolbarIfNeeded() {
        guard let window = view.window else {
            return
        }
        if window.toolbar?.identifier != toolbarIdentifier {
            toolbarDelegate.toggleTarget = self
            let toolbar = NSToolbar(identifier: toolbarIdentifier)
            toolbar.delegate = toolbarDelegate
            toolbar.displayMode = .iconOnly
            toolbar.allowsUserCustomization = false
            window.toolbar = toolbar
        }
    }
}

/// 只负责给出折叠按钮。
///
/// 单独一个非泛型对象，是因为泛型类不能声明 `@objc` 协议（`NSToolbarDelegate`）的
/// 一致性。`NSToolbar.delegate` 是弱引用，所以由 controller 持有它。
///
/// 这里**不用**标准的 `NSToolbarItem.Identifier.toggleSidebar`：只要侧边栏那一栏是
/// 真正的「sidebar item」（`NSSplitViewItem(sidebarWithViewController:)`），AppKit 就会
/// 把工具栏项摆到侧边栏右边界上（实测 x=216），而不是紧跟红绿灯 —— 那会改掉
/// 「按钮在红绿灯右边、浮在侧边栏上」的设计。换成普通工具栏项 + 显式 target 之后，
/// 位置回到 x=76（和重做前一致），动作仍然打到 `NSSplitViewController` 子类上。
@MainActor
final class SidebarToolbarDelegate: NSObject, NSToolbarDelegate {
    static let toggleIdentifier = NSToolbarItem.Identifier("ENVPilotSidebarToggle")

    weak var toggleTarget: SidebarToggleController?

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Self.toggleIdentifier, .flexibleSpace]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Self.toggleIdentifier, .flexibleSpace]
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        guard itemIdentifier == Self.toggleIdentifier else {
            return nil
        }
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.label = "侧边栏"
        item.paletteLabel = "侧边栏"
        item.toolTip = "显示或隐藏侧边栏"
        item.image = NSImage(systemSymbolName: "sidebar.leading", accessibilityDescription: "显示或隐藏侧边栏")
        item.isBordered = true
        item.target = toggleTarget
        item.action = #selector(SidebarToggleController.toggleSidebarAction(_:))
        return item
    }
}
