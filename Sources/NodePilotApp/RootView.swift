import SwiftUI

// MARK: - Root shell

struct RootView: View {
    @ObservedObject var store: NodeRuntimeStore
    @StateObject private var profileEditor: ProfileEditorModel

    @State private var section: AppSection? = .overview
    @State private var runtimeKind: RuntimeKind = .node

    private static let mainWindowID = "main"

    init(store: NodeRuntimeStore) {
        self.store = store
        _profileEditor = StateObject(wrappedValue: ProfileEditorModel(store: store))
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detailColumn
        }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        List(selection: $section) {
            ForEach(AppSection.allCases) { item in
                Label(item.title, systemImage: item.symbol)
                    .tag(item)
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 190, ideal: 212)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            sidebarFooter
        }
    }

    private var sidebarFooter: some View {
        HStack(alignment: .center, spacing: 8) {
            if store.isBusy {
                ProgressView()
                    .controlSize(.small)
                    .controlSize(.mini)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(store.progressMessage ?? store.statusSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)

                Text("当前终端需重载后生效")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 6)

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
        .padding(.vertical, 10)
        .background(.bar)
    }

    // MARK: Detail

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
        .navigationTitle(section?.title ?? AppSection.overview.title)
        .navigationSubtitle(section?.subtitle ?? AppSection.overview.subtitle)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    Task { await store.refresh() }
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(store.isBusy)
                .help("重新读取运行时信息 (⌘R)")
            }
        }
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

extension AppSection {
    static var allContentsIgnoringOrder: [AppSection] {
        AppSection.allCases
    }
}
