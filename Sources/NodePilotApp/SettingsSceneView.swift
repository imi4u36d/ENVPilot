import SwiftUI
import ENVPilotCore

// MARK: - 设置窗口（⌘,）

struct SettingsRootView: View {
    @ObservedObject var store: NodeRuntimeStore
    @ObservedObject var updates: AppUpdateModel
    @ObservedObject var loginItem: LoginItemModel
    @AppStorage(AppPreferenceKey.showsMenuBarMenu) private var showsMenuBarMenu = true
    @AppStorage(AppPreferenceKey.keepsMenuBarIconAfterClose) private var keepsMenuBarIconAfterClose = true

    private var activationScript: String {
        guard let snapshot = store.snapshot else {
            return ""
        }
        return RuntimeSnapshotReader.activationScript(for: snapshot)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                settingsHeader
                menuBarCard
                launchCard
                UpdateSettingsCard(model: updates)
                terminalCard
                storageCard
            }
            .padding(22)
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        // 固定 640×560 不可缩放：说明文案换行后没地方展开。给下限、允许用户拉大。
        .frame(minWidth: 640, minHeight: 520)
        .scrollContentBackground(.hidden)
        .background(DesignColor.canvas)
    }

    // MARK: Cards

    private var settingsHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                // 不在内容里复述窗口标题（HIG：标题栏已经说明了这是什么窗口）。
                Text("配置菜单栏、启动方式和终端环境")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            // 以前是孤零零一行 `ENVPilot dev`：没有「版本」二字，构建号回落值也不可读。
            Text("版本 \(SettingsPaths.appVersionLabel)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(DesignColor.tertiaryText)
                .accessibilityLabel("当前版本 \(SettingsPaths.appVersionLabel)")
        }
        .padding(.bottom, 2)
    }

    private var menuBarCard: some View {
        Card("菜单栏") {
            VStack(alignment: .leading, spacing: 12) {
                SettingsToggleRow(title: "在菜单栏显示 ENVPilot", isOn: $showsMenuBarMenu)

                Text("关闭后仍可从 Dock 打开主窗口；需要再次切换菜单栏入口时回到这里。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Divider()

                SettingsToggleRow(title: "关闭主窗口后保留菜单栏图标", isOn: $keepsMenuBarIconAfterClose)

                Text("开着时，关掉主窗口只是把窗口收起来，应用继续留在菜单栏；关掉后，最后一个窗口一关就退出 ENVPilot。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var launchCard: some View {
        Card("启动") {
            VStack(alignment: .leading, spacing: 8) {
                SettingsToggleRow(
                    title: "开机自启动",
                    isOn: Binding(
                        get: { loginItem.isOn },
                        set: { loginItem.toggle($0) }
                    ),
                    isEnabled: loginItem.canToggle
                )

                if let notice = loginItem.notice {
                    Text(notice)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("登录 macOS 后自动运行 ENVPilot（系统「登录项」）。改动立即生效，不需要重启应用。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
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
                .appButton(.quiet, size: .small)
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
                        .foregroundStyle(DesignColor.tertiaryText)
                } else {
                    // 不套内层 ScrollView：设置页本身就在滚动，两层滚动会把滚轮困在
                    // 这块 150pt 的well 里。让内容自然长高，整页滚动。
                    Text(activationScript)
                        .font(DesignType.monoCaption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
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
        lines.append("配置文件：\(SettingsPaths.settingsFile)")
        lines.append("运行时目录：\(SettingsPaths.runtimeRoot)")
        if !activationScript.isEmpty {
            lines.append("")
            lines.append(activationScript)
        }
        return lines.joined(separator: "\n")
    }
}

/// 设置行里的开关：文案在左、控件贴到行尾。
///
/// 直接把 `Toggle` 放进 `VStack(alignment: .leading)` 时，开关宽度取固有值、紧跟文案，
/// 于是同一张卡片里两个开关会落在不同的 x 上（截图里一眼可见）。
struct SettingsToggleRow: View {
    let title: String
    @Binding var isOn: Bool
    var isEnabled: Bool = true

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(DesignType.bodyText)

            Spacer(minLength: 12)

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .disabled(!isEnabled)
                .accessibilityLabel(title)
        }
    }
}

extension SettingsPaths {
    static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }

    /// 人能读的版本串：正式包是 `0.6.7`；开发构建回落成「开发构建」而不是裸 `dev`。
    static var appVersionLabel: String {
        let short = appVersion
        guard !short.isEmpty else {
            return "开发构建"
        }
        if let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String,
           !build.isEmpty,
           build != short,
           build.lowercased() != "dev"
        {
            return "\(short)（\(build)）"
        }
        return short
    }
}
