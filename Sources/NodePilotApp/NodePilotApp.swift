import SwiftUI

@main
struct ENVPilotApp: App {
    @StateObject private var store: NodeRuntimeStore
    @StateObject private var updates: AppUpdateModel
    @AppStorage(AppPreferenceKey.showsMenuBarMenu) private var showsMenuBarMenu = true

    init() {
        let store = NodeRuntimeStore()
        let updates = AppUpdateModel()
        _store = StateObject(wrappedValue: store)
        _updates = StateObject(wrappedValue: updates)
        UpdateProbe.runIfRequested()
        MenuBarSnapshot.runIfRequested(store: store, updates: updates)
        WindowSnapshot.runIfRequested(store: store, updates: updates)
        PerfProbe.load()
        PerfProbe.runIfRequested(store: store)
        // 延后一点再自动检查：离屏探针/快照（WindowSnapshot、MenuBarSnapshot、
        // UpdateProbe）都在首秒内退出了，不该被顺带拖去联网。
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            updates.checkAutomaticallyIfNeeded()
        }
    }

    var body: some Scene {
        Window("ENVPilot", id: "main") {
            RootView(store: store, updates: updates)
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
        }

        MenuBarExtra(isInserted: $showsMenuBarMenu) {
            MenuBarView(store: store, updates: updates)
        } label: {
            Image(systemName: "terminal.fill")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsRootView(store: store, updates: updates)
        }
    }
}
