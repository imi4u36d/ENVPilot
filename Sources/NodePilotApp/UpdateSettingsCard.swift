import SwiftUI
import ENVPilotCore

/// 设置窗口里的「软件更新」卡片：当前版本、检查结果、更新说明与一键更新。
struct UpdateSettingsCard: View {
    @ObservedObject var model: AppUpdateModel
    @AppStorage(AppUpdateModel.automaticCheckKey) private var automaticCheck = true

    var body: some View {
        Card("软件更新", accessory: AnyView(checkButton)) {
            VStack(alignment: .leading, spacing: 12) {
                versionRow

                if let message = statusMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                progressRow

                if let release = model.phase.release, !release.notes.isEmpty {
                    notesWell(for: release)
                }

                if !model.canSelfUpdate, model.phase.isUpdateAvailable {
                    Text(model.installMode.manualReason ?? "当前运行位置不支持自动替换，将下载 dmg。")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                actionRow

                Divider()

                VStack(alignment: .leading, spacing: 4) {
                    Toggle("每天自动检查更新", isOn: $automaticCheck)
                        .toggleStyle(.switch)
                    Text(lastCheckedText)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    // MARK: 头部

    private var versionRow: some View {
        HStack(spacing: 8) {
            Text("当前版本")
                .font(.callout)
                .foregroundStyle(.secondary)

            Text(currentVersionText)
                .font(.callout.monospacedDigit().weight(.medium))

            Spacer(minLength: 8)

            statusPill
        }
    }

    private var currentVersionText: String {
        model.currentVersion == "dev" ? "开发构建" : "v\(model.currentVersion)"
    }

    @ViewBuilder
    private var statusPill: some View {
        switch model.phase {
        case .idle:
            Pill("尚未检查")
        case .checking:
            Pill("检查中…", tone: .informative, symbol: "arrow.triangle.2.circlepath")
        case .upToDate:
            Pill("已是最新", tone: .positive, symbol: "checkmark")
        case .available(let release):
            Pill("发现 v\(release.version)", tone: .warning, symbol: "arrow.down.circle")
        case .downloading:
            Pill("下载中", tone: .informative, symbol: "arrow.down")
        case .installing(let release):
            Pill("正在更新到 v\(release.version)", tone: .informative, symbol: "arrow.triangle.2.circlepath")
        case .manual:
            Pill("dmg 已下载", tone: .informative, symbol: "checkmark")
        case .failed:
            Pill("检查失败", tone: .negative, symbol: "exclamationmark.triangle")
        }
    }

    private var checkButton: some View {
        Button {
            Task { await model.check() }
        } label: {
            Label("检查更新", systemImage: "arrow.triangle.2.circlepath")
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .disabled(model.isBusy)
    }

    // MARK: 状态

    private var statusMessage: String? {
        switch model.phase {
        case .idle:
            return nil
        case .checking:
            return "正在从 GitHub 查询最新版本…"
        case .upToDate(_, let latest):
            return "GitHub 上最新的发布是 v\(latest)。"
        case .available(let release):
            // 有更新说明时只留说明区，避免「新版本 vX：ENVPilot vX」这种重复。
            return release.notes.isEmpty ? "新版本 v\(release.version) 可以更新。" : nil
        case .downloading:
            // 进度行里已经有这句话了。
            return nil
        case .installing:
            return "正在替换应用并重新启动，窗口稍后会自动关闭。"
        case .manual(_, let location):
            return "已下载到 \(location.path)。打开后把 ENVPilot 拖到「应用程序」即可完成更新。"
        case .failed(let message):
            return message
        }
    }

    @ViewBuilder
    private var progressRow: some View {
        if case .downloading(let message, let fraction) = model.phase {
            if let fraction {
                ProgressView(value: fraction) {
                    Text(message)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            } else {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(message)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private func notesWell(for release: AppRelease) -> some View {
        ScrollView {
            Text(ReleaseNotesFormatter.plainText(release.notes))
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
        }
        .frame(maxHeight: 132)
        .background(DesignColor.well, in: RoundedRectangle(cornerRadius: 6))
    }

    // MARK: 动作

    @ViewBuilder
    private var actionRow: some View {
        HStack(spacing: 10) {
            switch model.phase {
            case .available(let release):
                Button(model.canSelfUpdate ? "更新到 v\(release.version)" : "下载 ENVPilot \(release.version)") {
                    Task { await model.install() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            case .failed:
                Button("重试") {
                    Task { await model.check() }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            case .manual(_, let location):
                Button("在 Finder 中显示") {
                    model.revealDownload(location)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            default:
                EmptyView()
            }

            if model.phase.release?.pageURL != nil {
                Button("打开发布页") {
                    model.openReleasePage()
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
            }

            Spacer(minLength: 0)
        }
        .controlSize(.small)
    }

    private var lastCheckedText: String {
        guard let lastCheckedAt = model.lastCheckedAt else {
            return "尚未检查过。"
        }
        return "上次检查：\(lastCheckedAt.formatted(date: .abbreviated, time: .shortened))"
    }
}
