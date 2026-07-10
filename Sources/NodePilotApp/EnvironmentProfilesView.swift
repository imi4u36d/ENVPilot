import SwiftUI
import ENVPilotCore

struct EnvironmentProfilesView: View {
    let profiles: [EnvironmentProfile]
    let selectedProfileID: UUID?
    @Binding var draftProfile: EnvironmentProfile
    @Binding var newProfileName: String
    let isLoading: Bool
    let isDirty: Bool
    let validationMessage: String?
    let onSelectProfile: (UUID?) -> Void
    let onCreateProfile: () -> Void
    let onResetProfile: () -> Void
    let onSaveProfile: () -> Void

    @State private var concealVariableValues = false

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 16) {
                profileListPanel
                    .frame(minWidth: 200, idealWidth: 220, maxWidth: 240)
                profileEditorPanel
                    .frame(minWidth: 420, maxWidth: .infinity, alignment: .top)
            }

            VStack(alignment: .leading, spacing: 16) {
                profileListPanel
                profileEditorPanel
            }
        }
    }

    private var profileListPanel: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(
                    title: "环境预设",
                    subtitle: "选择当前使用的配置组合。",
                    systemImage: "slider.horizontal.3"
                )

                if profiles.isEmpty {
                    EmptyState(
                        title: "当前没有环境预设",
                        message: "创建一个预设后即可编辑 registry 与环境变量。",
                        systemImage: "slider.horizontal.3"
                    )
                } else {
                    VStack(spacing: 6) {
                        ForEach(profiles) { profile in
                            EnvironmentProfileSelectionRow(
                                profile: profile,
                                isSelected: profile.id == selectedProfileID,
                                action: { onSelectProfile(profile.id) }
                            )
                        }
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("新建预设")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    TextField("例如：公司网络", text: $newProfileName)
                        .textFieldStyle(EnvPilotTextFieldStyle())
                        .onSubmit(onCreateProfile)
                        .disabled(isLoading)
                    Button {
                        onCreateProfile()
                    } label: {
                        Label("创建预设", systemImage: "plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isLoading || newProfileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private var profileEditorPanel: some View {
        GroupBox("预设编辑") {
            if selectedProfileID == nil {
                EmptyState(
                    title: "请选择一个环境预设",
                    message: "选中或创建预设后再编辑环境变量。",
                    systemImage: "pencil"
                )
            } else {
                profileEditor
            }
        }
    }

    private var profileEditor: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Text(draftProfile.name.isEmpty ? "未命名预设" : draftProfile.name)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                StatusBadge(
                    text: isDirty ? "有未保存更改" : "已保存",
                    systemImage: isDirty ? "pencil.circle.fill" : "checkmark.circle.fill",
                    color: isDirty ? .orange : .green
                )
            }

            VStack(alignment: .leading, spacing: 12) {
                ProfileInputRow(title: "预设名称") {
                    TextField("例如：默认、公司网络、私有源", text: $draftProfile.name)
                        .textFieldStyle(EnvPilotTextFieldStyle())
                        .disabled(isLoading)
                }
                ProfileInputRow(title: "npm registry") {
                    TextField("https://registry.npmjs.org/", text: $draftProfile.npmRegistry)
                        .textFieldStyle(EnvPilotTextFieldStyle())
                        .disabled(isLoading)
                }
                ProfileInputRow(title: "pnpm registry") {
                    TextField("留空则不设置", text: $draftProfile.pnpmRegistry)
                        .textFieldStyle(EnvPilotTextFieldStyle())
                        .disabled(isLoading)
                }
                ProfileInputRow(title: "yarn registry") {
                    TextField("留空则不设置", text: $draftProfile.yarnRegistry)
                        .textFieldStyle(EnvPilotTextFieldStyle())
                        .disabled(isLoading)
                }
                ProfileInputRow(title: "NODE_OPTIONS") {
                    TextField("例如 --max-old-space-size=4096", text: $draftProfile.nodeOptions)
                        .textFieldStyle(EnvPilotTextFieldStyle())
                        .disabled(isLoading)
                }
            }
            .settingsControlGroup()

            if let validationMessage {
                InlineMessage(
                    message: validationMessage,
                    systemImage: "exclamationmark.triangle.fill",
                    color: .red
                )
            }

            Divider()

            HStack {
                Text("自定义环境变量")
                    .font(.headline)
                Spacer()
                Button {
                    concealVariableValues.toggle()
                } label: {
                    Label(
                        concealVariableValues ? "显示变量值" : "隐藏变量值",
                        systemImage: concealVariableValues ? "eye" : "eye.slash"
                    )
                }
                .buttonStyle(.borderless)
                .disabled(draftProfile.variables.isEmpty)

                Button {
                    draftProfile.variables.append(CustomEnvironmentVariable(key: "", value: ""))
                } label: {
                    Label("新增变量", systemImage: "plus")
                }
                .disabled(isLoading)
            }

            if draftProfile.variables.isEmpty {
                Text("暂无自定义变量。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(draftProfile.variables.indices), id: \.self) { index in
                        HStack(spacing: 8) {
                            TextField("KEY", text: $draftProfile.variables[index].key)
                                .textFieldStyle(EnvPilotTextFieldStyle())
                                .disabled(isLoading)
                            variableValueField(at: index)
                            Button(role: .destructive) {
                                draftProfile.variables.remove(at: index)
                            } label: {
                                Image(systemName: "minus.circle")
                                    .frame(width: 28, height: 28)
                            }
                            .buttonStyle(.borderless)
                            .help("删除变量")
                            .accessibilityLabel("删除环境变量")
                            .disabled(isLoading)
                        }
                    }
                }
            }

            HStack {
                Spacer()
                Button {
                    onResetProfile()
                } label: {
                    Label("重置", systemImage: "arrow.uturn.backward")
                }
                .disabled(isLoading || !isDirty)

                Button {
                    onSaveProfile()
                } label: {
                    Label("保存预设", systemImage: "checkmark")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut("s", modifiers: .command)
                .disabled(isLoading || !isDirty || validationMessage != nil)
            }
        }
    }

    @ViewBuilder
    private func variableValueField(at index: Int) -> some View {
        if concealVariableValues {
            SecureField("VALUE", text: $draftProfile.variables[index].value)
                .textFieldStyle(EnvPilotTextFieldStyle())
                .disabled(isLoading)
        } else {
            TextField("VALUE", text: $draftProfile.variables[index].value)
                .textFieldStyle(EnvPilotTextFieldStyle())
                .disabled(isLoading)
        }
    }
}

private struct EnvironmentProfileSelectionRow: View {
    let profile: EnvironmentProfile
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            HStack(spacing: 9) {
                Image(systemName: "slider.horizontal.3")
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .frame(width: 18)
                Text(profile.name)
                    .font(.subheadline.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 6)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 10)
            .frame(minHeight: 36)
            .contentShape(Rectangle())
            .background(
                isSelected ? Color.accentColor.opacity(0.12) : Color.clear,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("环境预设 \(profile.name)")
        .accessibilityValue(isSelected ? "当前使用" : "未选择")
    }
}
