import SwiftUI
import AppKit

// MARK: - 菜单栏

struct MenuBarView: View {
    @ObservedObject var store: NodeRuntimeStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(store.statusSummary)

        Divider()

        ForEach(RuntimeKind.allCases) { kind in
            switcher(for: kind)
        }

        Divider()

        Button("刷新运行时信息") {
            Task { await store.refresh() }
        }

        Button("打开 ENVPilot 主窗口") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }

        Button("设置…") {
            WindowActions.openSettings()
        }

        Divider()

        Button("退出 ENVPilot") {
            NSApp.terminate(nil)
        }
    }

    @ViewBuilder
    private func switcher(for kind: RuntimeKind) -> some View {
        let summary = store.summary(for: kind)

        if summary.options.isEmpty {
            Text("\(kind.title)：未发现 ENVPilot 运行时")
        } else {
            Picker(
                kind.title,
                selection: Binding(
                    get: { summary.current?.version ?? "未选择" },
                    set: { newValue in
                        guard let option = summary.options.first(where: { $0.version == newValue }),
                              option.id != summary.current?.id else {
                            return
                        }
                        Task { await store.selectDefault(option) }
                    }
                )
            ) {
                ForEach(summary.options) { option in
                    Text(VersionLabel.display(kind, option.version)).tag(option.version)
                }
            }
        }
    }
}
