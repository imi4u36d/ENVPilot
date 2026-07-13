import SwiftUI

@main
struct ENVPilotApp: App {
    @NSApplicationDelegateAdaptor(ENVPilotApplicationDelegate.self) private var appDelegate
    @StateObject private var store: NodeRuntimeStore
    @AppStorage(AppPreferenceKey.showsMenuBarMenu) private var showsMenuBarMenu = true

    init() {
        let runtimeStore = NodeRuntimeStore(service: LocalNodeRuntimeService())
        _store = StateObject(wrappedValue: runtimeStore)
        ENVPilotApplicationDelegate.store = runtimeStore
    }

    var body: some Scene {
        MenuBarExtra(isInserted: $showsMenuBarMenu) {
            MenuBarContentView(store: store)
        } label: {
            Label(store.menuBarTitle, systemImage: "terminal.fill")
        }

        Settings {
            SettingsView(store: store)
                .frame(minWidth: 900, minHeight: 640)
        }
    }
}

@MainActor
final class ENVPilotApplicationDelegate: NSObject, NSApplicationDelegate {
    static var store: NodeRuntimeStore?
    private static weak var shared: ENVPilotApplicationDelegate?
    private var mainWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.shared = self
        NSApp.setActivationPolicy(.regular)
        showMainWindow()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow()
        return false
    }

    static func showMainWindow() {
        shared?.showMainWindow()
    }

    func showMainWindow() {
        if mainWindow == nil {
            guard let store = Self.store else {
                assertionFailure("ENVPilot store is not configured before opening the main window.")
                return
            }

            let contentView = SettingsView(store: store)
                .frame(minWidth: 900, minHeight: 640)
            let hostingView = NSHostingView(rootView: contentView)
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1100, height: 720),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "ENVPilot"
            window.titleVisibility = .visible
            window.titlebarAppearsTransparent = false
            window.titlebarSeparatorStyle = .automatic
            window.toolbarStyle = .unified
            window.contentView = hostingView
            window.center()
            window.isReleasedWhenClosed = false
            mainWindow = window
        }

        mainWindow?.makeKeyAndOrderFront(nil)
        Self.bringAppToFront()
    }

    static func bringAppToFront() {
        DispatchQueue.main.async {
            NSRunningApplication.current.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
            NSApp.activate(ignoringOtherApps: true)
            for window in NSApp.windows where window.canBecomeKey {
                window.makeKeyAndOrderFront(nil)
            }
        }
    }
}
