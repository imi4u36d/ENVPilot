import SwiftUI

@main
struct ENVPilotApp: App {
    @StateObject private var store: NodeRuntimeStore
    @AppStorage(AppPreferenceKey.showsMenuBarMenu) private var showsMenuBarMenu = true

    init() {
        let store = NodeRuntimeStore()
        _store = StateObject(wrappedValue: store)
        MenuBarSnapshot.runIfRequested(store: store)
    }

    var body: some Scene {
        Window("ENVPilot", id: "main") {
            RootView(store: store)
                .frame(minWidth: 880, minHeight: 560)
        }
        .defaultSize(width: 1120, height: 740)
        .windowResizability(.contentMinSize)

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
