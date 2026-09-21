import SwiftUI
import ENVPilotCore

// MARK: - 设置窗口（⌘,）

struct SettingsRootView: View {
    @ObservedObject var store: NodeRuntimeStore
    @ObservedObject var updates: AppUpdateModel
    @AppStorage(AppPreferenceKey.showsMenuBarMenu) private var showsMenuBarMenu = true

    private var scopeURL: URL? {
        store.inspectedDirectory
    }

    private var activationScript: String {
        guard let snapshot = store.snapshot else {
            return ""
        }
        return RuntimeSnapshotReader.activationScript(for: snapshot, directory: scopeURL)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                menuBarCard
                UpdateSettingsCard(model: updates)
                terminalCard
                storageCard
            }
            .padding(20)
            .frame(maxWidth: 560, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .frame(width: 600, height: 500)
        .scrollContentBackground(.hidden)
        .background(DesignColor.canvas)
    }

    // MARK: Cards

    private var menuBarCard: some View {
        Card("菜单栏") {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("在菜单栏显示 ENVPilot", isOn: $showsMenuBarMenu)
                    .toggleStyle(.switch)

                Text("关闭后仍可从 Dock 打开主窗口；需要再次切换菜单栏入口时回到这里。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var terminalCard: some View {
        Card(
            "终端环境",
            accessory: AnyView(
                Button {
                    WindowActions.copy(diagnostics)
                } label: {
                    Label("复制诊断信息", systemImage: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
            )
        ) {
            VStack(alignment: .leading, spacing: 10) {
                Text("新开的终端会执行以下语句。已打开的终端需重载 shell 才会更新。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if activationScript.isEmpty {
                    Text("当前没有需要导出的环境变量。")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                } else {
                    ScrollView {
                        Text(activationScript)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                    }
                    .frame(maxHeight: 150)
                    .background(DesignColor.well, in: RoundedRectangle(cornerRadius: 6))
                }
            }
        }
    }

    private var storageCard: some View {
        Card("存储位置") {
            VStack(spacing: 9) {
                ValueRow(label: "配置文件", value: SettingsPaths.settingsFile)
                ValueRow(label: "运行时目录", value: SettingsPaths.runtimeRoot)
                ValueRow(label: "Shell 配置", value: NSHomeDirectory() + "/.zshrc")
            }
        }
    }

    private var diagnostics: String {
        var lines: [String] = []
        lines.append("ENVPilot \(SettingsPaths.appVersion)")
        lines.append(store.statusSummary)
        lines.append("项目目录：\(store.inspectedDirectory?.path ?? "未选择")")
        lines.append("配置文件：\(SettingsPaths.settingsFile)")
        lines.append("运行时目录：\(SettingsPaths.runtimeRoot)")
        if !activationScript.isEmpty {
            lines.append("")
            lines.append(activationScript)
        }
        return lines.joined(separator: "\n")
    }
}

extension SettingsPaths {
    static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }
}
