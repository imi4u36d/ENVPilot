import SwiftUI
import ENVPilotCore

// MARK: - Editor model

@MainActor
final class ProfileEditorModel: ObservableObject {
    @Published var selectedProfileID: UUID?
    @Published var draft: EnvironmentProfile
    /// 变量值默认遮蔽，需要时再显式显示。
    @Published var masksValues = true

    private let store: NodeRuntimeStore

    init(store: NodeRuntimeStore) {
        self.store = store
        self.draft = EnvironmentProfile(name: "")
    }

    var profiles: [EnvironmentProfile] {
        store.snapshot?.settings.profiles ?? []
    }

    var saved: EnvironmentProfile? {
        profiles.first(where: { $0.id == selectedProfileID })
    }

    var isDirty: Bool {
        guard let saved else {
            return false
        }
        return draft != saved
    }

    var validationMessage: String? {
        if draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "预设名称不能为空。"
        }

        let registries = [
            ("npm registry", draft.npmRegistry),
            ("pnpm registry", draft.pnpmRegistry),
            ("yarn registry", draft.yarnRegistry),
        ]
        for (label, value) in registries {
            let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty else {
                continue
            }
            guard let components = URLComponents(string: normalized),
                  let scheme = components.scheme?.lowercased(),
                  ["http", "https"].contains(scheme),
                  components.host?.isEmpty == false else {
                return "\(label) 需要填写完整的 http 或 https 地址。"
            }
        }

        let keys = draft.variables.map { $0.key.trimmingCharacters(in: .whitespacesAndNewlines) }
        if keys.contains(where: { $0.isEmpty }) {
            return "环境变量名称不能为空。"
        }
        if let invalid = keys.first(where: {
            $0.range(of: #"^[A-Za-z_][A-Za-z0-9_]*$"#, options: .regularExpression) == nil
        }) {
            return "「\(invalid)」不是合法的环境变量名。"
        }
        if Set(keys).count != keys.count {
            return "环境变量名称不能重复。"
        }
        return nil
    }

    var canSave: Bool {
        saved != nil && isDirty && validationMessage == nil
    }

    func select(_ profileID: UUID) {
        guard let profile = profiles.first(where: { $0.id == profileID }) else {
            return
        }
        selectedProfileID = profileID
        draft = profile
        Task { await store.setSelectedProfile(id: profileID) }
    }

    func reset() {
        if let saved {
            draft = saved
        }
    }

    func save() {
        guard canSave else {
            return
        }
        Task { await store.saveProfile(draft) }
    }

    func syncFromSnapshot() {
        guard let preferred = store.snapshot?.settings.selectedProfileID ?? profiles.first?.id,
              let profile = profiles.first(where: { $0.id == preferred }) else {
            if selectedProfileID != nil {
                selectedProfileID = nil
            }
            return
        }
        if preferred != selectedProfileID {
            selectedProfileID = preferred
            draft = profile
        }
    }
}

// MARK: - 环境预设

struct ProfilesView: View {
    @ObservedObject var store: NodeRuntimeStore
    @ObservedObject var model: ProfileEditorModel

    @State private var pendingSwitch: UUID?
    @State private var newProfileName = ""

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            listColumn
                .frame(width: 248)
                .padding(.bottom, 20)

            editorColumn
        }
        .padding(.horizontal, Metric.pagePadding)
        .padding(.top, 20)
        .frame(maxWidth: Metric.pageMaxWidth, alignment: .topLeading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(DesignColor.canvas)
        .onAppear {
            model.syncFromSnapshot()
        }
        .onChange(of: store.snapshot?.settings.profiles) { _, _ in
            model.syncFromSnapshot()
        }
        .confirmationDialog(
            "有未保存的更改",
            isPresented: switchDialogBinding,
            titleVisibility: .visible
        ) {
            Button("放弃更改") {
                if let pendingSwitch {
                    model.draft = model.profiles.first(where: { $0.id == pendingSwitch }) ?? model.draft
                    model.select(pendingSwitch)
                }
                pendingSwitch = nil
            }
            Button("取消", role: .cancel) {
                pendingSwitch = nil
            }
        } message: {
            Text("切换预设会丢弃当前编辑，请先保存。")
        }
    }

    // MARK: 预设列表

    private var listColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            GroupSection(
                title: "环境预设",
                hint: model.profiles.isEmpty ? nil : "\(model.profiles.count) 个"
            ) {
                VStack(spacing: 2) {
                    if model.profiles.isEmpty {
                        InlineHint(symbol: "tray", text: "还没有预设，在下方新建一个。")
                            .padding(.horizontal, 3)
                            .padding(.vertical, 4)
                    } else {
                        ForEach(model.profiles) { profile in
                            profileButton(profile)
                        }
                    }
                }
                .padding(6)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .frame(maxHeight: .infinity)

            createRow
        }
    }

    private func profileButton(_ profile: EnvironmentProfile) -> some View {
        let isSelected = model.selectedProfileID == profile.id
        let isCurrent = store.snapshot?.settings.selectedProfileID == profile.id

        return Button {
            requestSelect(profile.id)
        } label: {
            HStack(spacing: 8) {
                Text(profile.name)
                    .font(.callout)
                    .lineLimit(1)

                Spacer(minLength: 6)

                if isCurrent {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.green)
                        .help("当前使用")
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(SelectableRowStyle(isSelected: isSelected))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func requestSelect(_ profileID: UUID) {
        guard profileID != model.selectedProfileID else {
            return
        }
        if model.isDirty {
            pendingSwitch = profileID
        } else {
            model.select(profileID)
        }
    }

    private var createRow: some View {
        HStack(spacing: 7) {
            TextField("新预设名称，例如 公司网络", text: $newProfileName)
                .textFieldStyle(.roundedBorder)
                .onSubmit(createProfile)

            Button {
                createProfile()
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.bordered)
            .disabled(newProfileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .help("创建预设")
            .accessibilityLabel("创建预设")
        }
        .padding(.top, 10)
    }

    private func createProfile() {
        let name = newProfileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            return
        }
        newProfileName = ""
        Task {
            await store.createProfile(named: name)
            model.syncFromSnapshot()
        }
    }

    private var switchDialogBinding: Binding<Bool> {
        Binding(
            get: { pendingSwitch != nil },
            set: { isPresented in
                if !isPresented {
                    pendingSwitch = nil
                }
            }
        )
    }

    // MARK: 编辑器

    private var editorColumn: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metric.sectionSpacing) {
                if model.selectedProfileID == nil {
                    GroupSection {
                        EmptyState(
                            symbol: "slider.horizontal.3",
                            title: "还没有选中预设",
                            message: "在左侧选择或创建一个预设，然后在这里配置 registry 与环境变量。"
                        )
                    }
                } else {
                    editorHeader
                    nameSection
                    registrySection
                    nodeSection
                    variablesSection
                }
            }
            .padding(.bottom, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if model.selectedProfileID != nil {
                editorActionBar
            }
        }
    }

    private var editorHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(model.draft.name.isEmpty ? "未命名预设" : model.draft.name)
                .font(.title3.weight(.semibold))
                .lineLimit(1)

            Spacer(minLength: 8)

            Pill(
                model.isDirty ? "未保存" : "已保存",
                tone: model.isDirty ? .warning : .positive,
                symbol: model.isDirty ? "circle.circle" : "checkmark.circle.fill"
            )
        }
    }

    private var nameSection: some View {
        GroupSection(title: "预设", footer: "预设名称会显示在终端提示符与概览页中。") {
            GroupRow {
                LabeledField(title: "名称") {
                    TextField("例如 默认、公司网络", text: $model.draft.name)
                        .textFieldStyle(.roundedBorder)
                }
            }
        }
    }

    private var registrySection: some View {
        GroupSection(
            title: "包管理器 registry",
            footer: "留空的 registry 不会写入终端环境。"
        ) {
            VStack(spacing: 0) {
                GroupRow {
                    LabeledField(title: "npm") {
                        RegistryField(text: $model.draft.npmRegistry, placeholder: "https://registry.npmjs.org/")
                    }
                }
                GroupRow(dividerAbove: true) {
                    LabeledField(title: "pnpm") {
                        RegistryField(text: $model.draft.pnpmRegistry, placeholder: "留空则不设置")
                    }
                }
                GroupRow(dividerAbove: true) {
                    LabeledField(title: "yarn") {
                        RegistryField(text: $model.draft.yarnRegistry, placeholder: "留空则不设置")
                    }
                }
            }
        }
    }

    private var nodeSection: some View {
        GroupSection(title: "Node") {
            GroupRow {
                LabeledField(title: "NODE_OPTIONS") {
                    TextField("例如 --max-old-space-size=4096", text: $model.draft.nodeOptions)
                        .textFieldStyle(.roundedBorder)
                }
            }
        }
    }

    private var variablesSection: some View {
        GroupSection(
            title: "自定义环境变量",
            footer: "变量名需以字母或下划线开头，只包含字母、数字和下划线。",
            accessory: AnyView(
                HStack(spacing: 12) {
                    if !model.draft.variables.isEmpty {
                        Button {
                            model.masksValues.toggle()
                        } label: {
                            Label(
                                model.masksValues ? "显示变量值" : "隐藏变量值",
                                systemImage: model.masksValues ? "eye" : "eye.slash"
                            )
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                    }

                    Button {
                        model.draft.variables.append(CustomEnvironmentVariable(key: "", value: ""))
                    } label: {
                        Label("新增变量", systemImage: "plus")
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                }
            )
        ) {
            if model.draft.variables.isEmpty {
                GroupRow {
                    InlineHint(
                        symbol: "text.badge.plus",
                        text: "暂无自定义变量。可用它配置代理地址、私有仓库令牌等。"
                    )
                }
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(model.draft.variables.indices), id: \.self) { index in
                        GroupRow(dividerAbove: index > 0) {
                            HStack(spacing: 8) {
                                TextField("NAME", text: $model.draft.variables[index].key)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.callout.monospaced())
                                    .frame(width: 180)

                                variableValueField(index)

                                Button {
                                    model.draft.variables.remove(at: index)
                                } label: {
                                    Image(systemName: "minus.circle")
                                }
                                .buttonStyle(.borderless)
                                .help("删除变量")
                                .accessibilityLabel("删除变量")
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func variableValueField(_ index: Int) -> some View {
        if model.masksValues {
            SecureField("value", text: $model.draft.variables[index].value)
                .textFieldStyle(.roundedBorder)
        } else {
            TextField("value", text: $model.draft.variables[index].value)
                .textFieldStyle(.roundedBorder)
        }
    }

    /// 固定在底部的保存栏：长表单滚动时保存按钮始终可见。
    private var editorActionBar: some View {
        HStack(spacing: 8) {
            if let validation = model.validationMessage {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                Text(validation)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else {
                Image(systemName: model.isDirty ? "circle.circle" : "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(model.isDirty ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                Text(model.isDirty ? "有未保存的更改" : "已保存，终端重载后生效")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Button("重置") {
                model.reset()
            }
            .disabled(!model.isDirty)

            Button {
                model.save()
            } label: {
                Label("保存预设", systemImage: "checkmark")
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut("s", modifiers: .command)
            .disabled(!model.canSave)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(DesignColor.canvas)
        .overlay(alignment: .top) { Divider() }
    }
}

// MARK: - Field helpers

struct LabeledField<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 96, alignment: .leading)

            content
        }
    }
}

struct RegistryField: View {
    @Binding var text: String
    let placeholder: String

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.roundedBorder)
    }
}
