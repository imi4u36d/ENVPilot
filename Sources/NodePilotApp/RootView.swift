import SwiftUI

// MARK: - Root shell

struct RootView: View {
    @ObservedObject var store: NodeRuntimeStore
    @ObservedObject var updates: AppUpdateModel
    @StateObject private var profileEditor: ProfileEditorModel

    @State private var section: AppSection?
    @State private var runtimeKind: RuntimeKind = .node

    init(store: NodeRuntimeStore, updates: AppUpdateModel) {
        self.store = store
        self.updates = updates
        _profileEditor = StateObject(wrappedValue: ProfileEditorModel(store: store))
        // 离屏快照需要从任意页面启动；正常运行时固定停在概览页。
        _section = State(initialValue: WindowSnapshot.initialSection ?? PerfProbe.settings.section ?? .overview)
    }

    var body: some View {
        let _ = PerfProbe.noteBody("root")
        // 两栏交给 AppKit 原生的 NSSplitViewController（见 `NativeSidebarShell`）：
        // SwiftUI 的 `NavigationSplitView` 在这台机器上不是原生实现，折叠动画既不能
        // 反向重定向、又绕过 binding，点快了就是「跳一下」。
        NativeSidebarShell(
            sidebar: sidebarColumn,
            detail: detailColumnContent
        )
        // 铺满整个窗口高度：标题栏是隐藏的，红绿灯与那个伸缩按钮浮在侧边栏上面。
        // （AppKit 的 `allowsFullHeightLayout` 会自己给两栏留出标题栏的安全区。）
        .ignoresSafeArea(.container, edges: .top)
        .flatTitleBar()
    }

    @ViewBuilder
    private var sidebarColumn: some View {
        if PerfProbe.simpleSidebar {
            // 空壳：只剩两行字，侧边栏的组件（图标、渐变、页脚）全部不要
            List {
                Text("概览")
                Text("运行时")
            }
        } else {
            sidebar
        }
    }

    @ViewBuilder
    private var detailColumnContent: some View {
        if PerfProbe.simpleDetail {
            Text("x")
                .padding()
        } else {
            detailColumn
        }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        List(selection: $section) {
            brandRow

            ForEach(AppSection.grouped, id: \.title) { group in
                Section(group.title) {
                    ForEach(group.sections) { item in
                        Label(item.title, systemImage: item.symbol)
                            .tag(item)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        // 侧边栏默认是半透明的 sidebar 材质，铺在白/黑画布旁边会显出一块灰。
        // 整页统一成同一张白/黑台面，两栏只靠中间那条分隔线分开。
        .scrollContentBackground(.hidden)
        .background(DesignColor.canvas)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            sidebarFooter
        }
    }

    /// 品牌行。没有 `tag`，因此在选择型 `List` 里不可选中，只作为身份标识。
    private var brandRow: some View {
        HStack(spacing: 9) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.27, green: 0.55, blue: 0.93),
                            Color(red: 0.20, green: 0.42, blue: 0.82),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 26, height: 26)
                .overlay {
                    Image(systemName: "terminal.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                }

            VStack(alignment: .leading, spacing: 1) {
                Text("ENVPilot")
                    .font(.system(size: 13, weight: .semibold))
                Text("开发环境管理")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .listRowSeparator(.hidden)
    }

    /// 状态与动作都在侧边栏底部：顶部整条留给内容，不再有一个横贯窗口的工具栏。
    /// 版本摘要独占一行，按钮挂在提示语那一行的右端，两边都放得下、都不用截断。
    private var sidebarFooter: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                if store.isBusy {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.7)
                        .frame(width: 8, height: 8)
                } else {
                    Circle()
                        .fill(isErrorStatus ? Color.red : Color.green.opacity(0.85))
                        .frame(width: 6, height: 6)
                        .accessibilityHidden(true)
                }

                Text(store.progressMessage ?? store.statusSummary)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(store.progressMessage ?? store.statusSummary)
            }

            HStack(spacing: 6) {
                Text("新终端生效")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                Spacer(minLength: 4)

                if let badge = updates.badgeText {
                    Button {
                        WindowActions.openSettings()
                    } label: {
                        Pill("更新 \(badge)", tone: .warning, symbol: "arrow.down.circle")
                    }
                    .buttonStyle(.plain)
                    .help("发现新版本 \(badge)，点击查看并更新")
                }

                Button {
                    Task { await store.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .keyboardShortcut("r", modifiers: .command)
                .disabled(store.isBusy)
                .help("重新读取运行时信息 (⌘R)")
                .accessibilityLabel("刷新")

                Button {
                    WindowActions.openSettings()
                } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.borderless)
                .help("打开设置")
                .accessibilityLabel("打开设置")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(DesignColor.canvas)
    }

    private var isErrorStatus: Bool {
        store.statusMessage?.tone == .error
    }

    // MARK: Detail

    /// 页面身份由侧边栏的选中项表达，所以这里不再放标题和副标题。
    private var detailColumn: some View {
        VStack(spacing: 0) {
            detailContent
            if let status = store.statusMessage {
                StatusBar(
                    text: status.text,
                    tone: status.tone == .error ? .error : .notice,
                    onDismiss: { store.dismissStatus() }
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var detailContent: some View {
        switch section ?? .overview {
        case .overview:
            OverviewView(store: store) { kind in
                runtimeKind = kind
                section = .runtimes
            }
            .id(AppSection.overview)
        case .runtimes:
            RuntimesView(store: store, kind: $runtimeKind)
                .id(AppSection.runtimes)
        case .projects:
            ProjectsView(store: store) { kind in
                runtimeKind = kind
                section = .runtimes
            }
            .id(AppSection.projects)
        case .profiles:
            ProfilesView(store: store, model: profileEditor)
                .id(AppSection.profiles)
        }
    }
}
