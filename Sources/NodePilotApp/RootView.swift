import SwiftUI

// MARK: - Root shell

struct RootView: View {
    @ObservedObject var store: NodeRuntimeStore
    @ObservedObject var updates: AppUpdateModel
    @State private var section: AppSection?
    @State private var runtimeKind: RuntimeKind = .node

    init(store: NodeRuntimeStore, updates: AppUpdateModel) {
        self.store = store
        self.updates = updates
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

    /// 侧边栏分两区，都用留白隔开而不是分隔线：
    /// 上面的品牌区只表身份，下面的导航区只剩两项。
    /// 原来它们挤在同一个 `List` 里，三行等高的行贴在一起，
    /// 整块内容看起来「堆」在顶部。拆成两区之后，身份和导航各占一层，
    /// 行与行、区与区之间都有明确的呼吸感。
    private var sidebar: some View {
        VStack(spacing: 0) {
            brandHeader
            nav
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // 整页统一成同一张白/黑台面，两栏只靠中间那条分隔线分开。
        .background(DesignColor.canvas)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            sidebarFooter
        }
    }

    /// 品牌区：图标 + 名称 + 一句定位，只作身份标识，不可选中。
    /// 标题栏是隐藏的（内容铺到窗口最顶端），顶部留白要越过红绿灯。
    private var brandHeader: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
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
                .frame(width: 30, height: 30)
                .overlay {
                    Image(systemName: "terminal.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text("ENVPilot")
                    .font(.system(size: 14, weight: .semibold))
                Text("开发环境管理")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 32)
        .padding(.bottom, 18)
    }

    /// 导航区：两项平铺，不再分组。
    ///
    /// 用 `SelectableRowStyle`（强调色浅底 + 圆角）替代 `List` 的全宽选中条：
    /// 行高可以自己做主，行与行之间留出 6pt，读起来是两个独立入口而不是一条
    /// 挤在一起的列表。
    private var nav: some View {
        VStack(spacing: 6) {
            ForEach(AppSection.allCases) { item in
                Button {
                    section = item
                } label: {
                    Label(item.title, systemImage: item.symbol)
                        .font(.system(size: 13, weight: .medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(SelectableRowStyle(isSelected: (section ?? .overview) == item))
                .accessibilityAddTraits((section ?? .overview) == item ? [.isSelected] : [])
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 2)
    }

    /// 侧边栏底部只放动作：更新胶囊（有新版时才有）和设置按钮。
    ///
    /// 原来这里是两行小字（运行时版本摘要、「新终端生效」）加一个刷新按钮，现在都删了。
    /// 摘要跟概览页里的运行时状态重复；刷新挪到了「显示」菜单，`⌘R` 照旧能用。
    private var sidebarFooter: some View {
        HStack(spacing: 6) {
            if let badge = updates.badgeText {
                // 已经知道有新版本：这一行就是「一键更新」，进度在设置窗口里看。
                Button {
                    WindowActions.openSettings()
                } label: {
                    Pill("更新 \(badge)", tone: .warning, symbol: "arrow.down.circle")
                }
                .buttonStyle(.plain)
                .help("发现新版本 \(badge)，点击查看并更新")
            }

            Spacer(minLength: 4)

            Button {
                WindowActions.openSettings()
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help("打开设置")
            .accessibilityLabel("打开设置")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(DesignColor.canvas)
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
        }
    }
}
