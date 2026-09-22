import AppKit
import SwiftUI

@main
struct ENVPilotApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store: NodeRuntimeStore
    @StateObject private var aiStore: AIEnvironmentStore
    @StateObject private var packageManagerStore: PackageManagerStore
    @StateObject private var updates: AppUpdateModel
    @StateObject private var loginItem: LoginItemModel
    @StateObject private var environmentCheck: EnvironmentCheckStore
    @AppStorage(AppPreferenceKey.showsMenuBarMenu) private var showsMenuBarMenu = true

    init() {
        let store = NodeRuntimeStore()
        let aiStore = AIEnvironmentStore()
        let packageManagerStore = PackageManagerStore()
        let updates = AppUpdateModel()
        let environmentCheck = EnvironmentCheckStore(runtimeStore: store, aiStore: aiStore)
        _store = StateObject(wrappedValue: store)
        _aiStore = StateObject(wrappedValue: aiStore)
        _packageManagerStore = StateObject(wrappedValue: packageManagerStore)
        _updates = StateObject(wrappedValue: updates)
        _loginItem = StateObject(wrappedValue: LoginItemModel())
        _environmentCheck = StateObject(wrappedValue: environmentCheck)
        LoginItemProbe.runIfRequested()
        UpdateProbe.runIfRequested()
        MenuBarSnapshot.runIfRequested(store: store, updates: updates)
        WindowSnapshot.runIfRequested(store: store, aiStore: aiStore, updates: updates)
        PerfProbe.load()
        PerfProbe.runIfRequested(store: store)
        // 延后一点再自动检查：离屏探针/快照（WindowSnapshot、MenuBarSnapshot、
        // UpdateProbe）都在首秒内退出了，不该被顺带拖去联网。
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            updates.checkAutomaticallyIfNeeded()
        }
    }

    /// 帮助入口指向仓库里的 README，不依赖打包 Help Book。
    private func openGitHubDocs() {
        if let url = URL(string: "https://github.com/imi4u36d/ENVPilot") {
            NSWorkspace.shared.open(url)
        }
    }

    var body: some Scene {
        Window("ENVPilot", id: "main") {
            RootView(
                store: store,
                aiStore: aiStore,
                packageManagerStore: packageManagerStore,
                updates: updates,
                environmentCheck: environmentCheck
            )
                .frame(minWidth: 880, minHeight: 560)
        }
        .defaultSize(width: 1120, height: 740)
        .windowResizability(.contentMinSize)
        // 左右布局为主，顶部不再切一刀：标题栏透明、内容铺满整个窗口高度。
        .windowStyle(.hiddenTitleBar)
        .commands {
            // 惯例位置：与「关于 ENVPilot」同组，紧跟其后。
            CommandGroup(after: .appInfo) {
                Button("检查更新…") {
                    Task { await UpdatePrompter.checkAndPresent(model: updates) }
                }
                .disabled(updates.isBusy)
            }

            // 刷新原来是侧边栏底部的一个小按钮，现在挪进「显示」菜单。
            // `⌘R` 保持不变，只是不再占底部那一行。
            CommandGroup(after: .sidebar) {
                Button("重新读取运行时信息") {
                    Task { await store.refresh() }
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(store.isBusy)

                Button("切换侧边栏") {
                    WindowActions.toggleSidebar()
                }
                .keyboardShortcut("s", modifiers: [.command, .control])
            }

            // 「帮助」菜单里那条 Toggle Sidebar 是 SwiftUI 自己塞的，标题是硬编码英文，
            // 本 App 的 Localizable.strings 管不到它。整个菜单接管过来：折叠侧边栏挪到
            // 「显示」，这里只留一条中文的帮助入口。
            CommandGroup(replacing: .help) {
                Button("ENVPilot 帮助") {
                    openGitHubDocs()
                }
                .keyboardShortcut("?", modifiers: .command)
            }
        }

        MenuBarExtra(isInserted: $showsMenuBarMenu) {
            MenuBarView(store: store, updates: updates)
        } label: {
            Image(nsImage: MenuBarIcon.image)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsRootView(store: store, updates: updates, loginItem: loginItem)
        }
    }
}
