import SwiftUI
import ENVPilotCore

// MARK: - Editor model

@MainActor
final class ProfileEditorModel: ObservableObject {
    @Published var selectedProfileID: UUID?
    @Published var draft: EnvironmentProfile
    @Published var revealValues = false

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
        HStack(alignment: .top, spacing: 14) {
            listColumn
                .frame(width: 244)
            editorColumn
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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

    // MARK: List column

    private var listColumn: some View {
        Card("环境预设") {
            VStack(alignment: .leading, spacing: 10) {
                if model.profiles.isEmpty {
                    EmptyHint(
                        text: "创建预设后可配置 registry 与环境变量。",
                        symbol: "tray"
                    )
                } else {
                    List(selection: selectionBinding) {
                        ForEach(model.profiles) { profile in
                            HStack(spacing: 6) {
                                Text(profile.name)
                                    .font(.callout)
                                    .lineLimit(1)
                                Spacer(minLength: 4)
                                if store.snapshot?.settings.selectedProfileID == profile.id {
                                    Pill("使用中", tone: .positive, symbol: "checkmark.circle.fill")
                                }
                            }
                            .tag(profile.id)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .frame(maxHeight: .infinity)
                }

                Divider()

                VStack(alignment: .leading, spacing: 7) {
                    TextField("新预设名称，例如 公司网络", text: $newProfileName)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(createProfile)

                    Button {
                        createProfile()
                    } label: {
                        Label("创建预设", systemImage: "plus")
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(newProfileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
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

    private var selectionBinding: Binding<UUID?> {
        Binding(
            get: { model.selectedProfileID },
            set: { newValue in
                guard let newValue, newValue != model.selectedProfileID else {
                    return
                }
                if model.isDirty {
                    pendingSwitch = newValue
                } else {
                    model.select(newValue)
                }
            }
        )
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

    // MARK: Editor column

    private var editorColumn: some View {
        ScrollView {
            Card("预设编辑") {
                if model.selectedProfileID == nil {
                    EmptyHint(
                        text: "在左侧选择或创建一个预设。",
                        symbol: "questionmark.circle"
                    )
                } else {
                    VStack(alignment: .leading, spacing: 14) {
                        editorHeader
                        Divider()
                        settingsSection
                        variableSection
                        actionBar
                    }
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var editorHeader: some View {
        HStack(spacing: 8) {
            Text(model.draft.name.isEmpty ? "未命名预设" : model.draft.name)
                .font(.headline)
                .lineLimit(1)

            Spacer(minLength: 8)

            if let validation = model.validationMessage {
                Pill("无法保存", tone: .negative, symbol: "exclamationmark.triangle.fill")
                    .help(validation)
            }

            Pill(
                model.isDirty ? "未保存" : "已保存",
                tone: model.isDirty ? .warning : .positive,
                symbol: model.isDirty ? "circle.circle" : "checkmark.circle.fill"
            )
        }
    }

    private var settingsSection: some View {
        VStack(spacing: 0) {
            LabeledField(title: "预设名称") {
                TextField("例如 默认、公司网络", text: $model.draft.name)
                    .textFieldStyle(.roundedBorder)
            }
            Divider()
            LabeledField(title: "npm registry") {
                RegistryField(text: $model.draft.npmRegistry, placeholder: "https://registry.npmjs.org/")
            }
            Divider()
            LabeledField(title: "pnpm registry") {
                RegistryField(text: $model.draft.pnpmRegistry, placeholder: "留空则不设置")
            }
            Divider()
            LabeledField(title: "yarn registry") {
                RegistryField(text: $model.draft.yarnRegistry, placeholder: "留空则不设置")
            }
            Divider()
            LabeledField(title: "NODE_OPTIONS") {
                TextField("例如 --max-old-space-size=4096", text: $model.draft.nodeOptions)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    private var variableSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Text("自定义环境变量")
                    .font(.subheadline.weight(.medium))

                Spacer(minLength: 8)

                if !model.draft.variables.isEmpty {
                    Button {
                        model.revealValues.toggle()
                    } label: {
                        Label(model.revealValues ? "隐藏变量值" : "显示变量值", systemImage: model.revealValues ? "eye.slash" : "eye")
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

            if model.draft.variables.isEmpty {
                Text("暂无自定义变量。")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                VStack(spacing: 7) {
                    ForEach(Array(model.draft.variables.indices), id: \.self) { index in
                        HStack(spacing: 7) {
                            TextField("NAME", text: $model.draft.variables[index].key)
                                .textFieldStyle(.roundedBorder)
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

            if let validation = model.validationMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(validation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    @ViewBuilder
    private func variableValueField(_ index: Int) -> some View {
        if model.revealValues {
            SecureField("value", text: $model.draft.variables[index].value)
                .textFieldStyle(.roundedBorder)
        } else {
            TextField("value", text: $model.draft.variables[index].value)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var actionBar: some View {
        HStack(spacing: 8) {
            Text("修改后需保存，并在终端中重载才生效。")
                .font(.caption)
                .foregroundStyle(.tertiary)

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
    }
}

// MARK: - Field helpers

struct LabeledField<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 116, alignment: .leading)

            content
        }
        .padding(.vertical, 6)
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
