import SwiftUI

@main
struct ENVPilotApp: App {
    @StateObject private var store: NodeRuntimeStore
    @AppStorage(AppPreferenceKey.showsMenuBarMenu) private var showsMenuBarMenu = true

    init() {
        let store = NodeRuntimeStore()
        _store = StateObject(wrappedValue: store)
        MenuBarSnapshot.runIfRequested(store: store)
        WindowSnapshot.runIfRequested(store: store)
    }

    var body: some Scene {
        Window("ENVPilot", id: "main") {
            RootView(store: store)
                .frame(minWidth: 880, minHeight: 560)
        }
        .defaultSize(width: 1120, height: 740)
        .windowResizability(.contentMinSize)
        // 左右布局为主，顶部不再切一刀：标题栏透明、内容铺满整个窗口高度。
        .windowStyle(.hiddenTitleBar)

        MenuBarExtra(isInserted: $showsMenuBarMenu) {
            MenuBarView(store: store)
        } label: {
            Image(systemName: "terminal.fill")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsRootView(store: store)
        }
    }
}
