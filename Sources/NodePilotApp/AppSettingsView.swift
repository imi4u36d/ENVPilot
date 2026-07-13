import SwiftUI

struct AppSettingsView: View {
    @AppStorage(AppPreferenceKey.showsMenuBarMenu) private var showsMenuBarMenu = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox("菜单栏") {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle(isOn: $showsMenuBarMenu) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("在菜单栏显示 ENVPilot")
                                .font(.body.weight(.medium))
                            Text("快速查看当前运行时，并切换 Node、JDK 和 Python 版本。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.switch)

                    Divider()

                    Label(statusMessage, systemImage: statusIcon)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var statusMessage: String {
        showsMenuBarMenu
            ? "菜单栏入口已启用。"
            : "菜单栏入口已隐藏；你仍可从 Dock 打开 ENVPilot 并在此重新启用。"
    }

    private var statusIcon: String {
        showsMenuBarMenu ? "menubar.rectangle" : "eye.slash"
    }
}
