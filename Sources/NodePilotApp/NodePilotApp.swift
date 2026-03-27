import SwiftUI

@main
struct ENVPilotApp: App {
    @NSApplicationDelegateAdaptor(ENVPilotApplicationDelegate.self) private var appDelegate
    @StateObject private var store = NodeRuntimeStore(service: LocalNodeRuntimeService())

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(store: store)
        } label: {
            Label(store.menuBarTitle, systemImage: "terminal.fill")
        }

        Window("ENVPilot 设置", id: "settings") {
            SettingsView(store: store)
                .frame(minWidth: 620, minHeight: 520)
        }

        Settings {
            SettingsView(store: store)
                .frame(minWidth: 620, minHeight: 520)
        }
    }
}

final class ENVPilotApplicationDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
