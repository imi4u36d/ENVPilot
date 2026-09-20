import SwiftUI

// MARK: - Root shell

struct RootView: View {
    @ObservedObject var store: NodeRuntimeStore
    @StateObject private var profileEditor: ProfileEditorModel

    @State private var section: AppSection?
    @State private var runtimeKind: RuntimeKind = .node

    init(store: NodeRuntimeStore) {
        self.store = store
        _profileEditor = StateObject(wrappedValue: ProfileEditorModel(store: store))
        // 离屏快照需要从任意页面启动；正常运行时固定停在概览页。
        _section = State(initialValue: WindowSnapshot.initialSection ?? .overview)
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detailColumn
        }
        .flatTitleBar()
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
        .navigationSplitViewColumnWidth(min: 190, ideal: 214)
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
