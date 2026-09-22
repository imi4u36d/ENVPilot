import ENVPilotCore
import SwiftUI

struct EnvironmentCheckView: View {
    @ObservedObject var store: EnvironmentCheckStore
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            VStack(spacing: 6) {
                ForEach(store.checks) { check in
                    EnvironmentCheckRow(check: check)
                }
            }

            messageSlot

            footer
        }
        .padding(20)
        .frame(width: 540)
        .background(DesignColor.canvas)
        .interactiveDismissDisabled(store.isBusy)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Color.accentColor.opacity(0.13))
                    .frame(width: 44, height: 44)

                Image(systemName: store.needsRepair ? "wrench.and.screwdriver.fill" : "checkmark.shield.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .contentTransition(.opacity)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("环境检查")
                    .font(.system(size: 20, weight: .semibold))

                Text("检查 ENVPilot 运行 AI 工具所需的基础配置，缺少的必需项可以一键补齐。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)
        }
    }

    @ViewBuilder
    private var messageSlot: some View {
        Group {
            if let message = store.message {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(store.needsRepair ? .orange : .secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 18, maxHeight: 18, alignment: .topLeading)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button {
                Task { await store.refresh() }
            } label: {
                Label("重新检查", systemImage: "arrow.clockwise")
            }
            .appButton(.secondary, size: .small)
            .disabled(store.isBusy)

            Spacer(minLength: 8)

            Button("稍后") {
                onClose()
            }
            .appButton(.quiet, size: .small)
            .disabled(store.isBusy)

            if store.needsRepair || store.isRepairing {
                Button {
                    Task { await store.repair() }
                } label: {
                    Label(
                        store.isRepairing ? "正在配置" : "一键配置",
                        systemImage: store.isRepairing ? "hourglass" : "wand.and.stars"
                    )
                }
                .appButton(.primary, size: .small)
                .disabled(store.isBusy)
            }

            if !store.needsRepair {
                Button("完成") {
                    onClose()
                }
                .appButton(.primary, size: .small)
                .disabled(store.isBusy)
            }
        }
    }
}

private struct EnvironmentCheckRow: View {
    let check: EnvironmentSetupCheckResult

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Group {
                if check.status == .loading {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 30, height: 30)
                } else {
                    ZStack {
                        Circle()
                            .fill(statusTint.opacity(0.13))
                            .frame(width: 30, height: 30)

                        Image(systemName: statusSymbol)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(statusTint)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Text(check.kind.title)
                        .font(.callout.weight(.semibold))

                    if check.kind == .aiTools {
                        Pill("可选", tone: .neutral)
                    }
                }

                Text(check.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: false, vertical: true)

                if let repairHint = check.repairHint, check.status == .needsRepair || check.status == .failed {
                    Text(repairHint)
                        .font(.caption)
                        .foregroundStyle(statusTint)
                        .lineLimit(1)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 8)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(DesignColor.well, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(statusTint.opacity(0.16), lineWidth: 1)
        }
    }

    private var statusSymbol: String {
        switch check.status {
        case .loading:
            return "ellipsis"
        case .ok:
            return "checkmark"
        case .needsRepair:
            return "exclamationmark"
        case .optional:
            return "ellipsis"
        case .failed:
            return "xmark"
        }
    }

    private var statusTint: Color {
        switch check.status {
        case .loading:
            return .secondary
        case .ok:
            return Color(red: 0.18, green: 0.63, blue: 0.36)
        case .needsRepair:
            return Color(red: 0.88, green: 0.55, blue: 0.12)
        case .optional:
            return .secondary
        case .failed:
            return Color(red: 0.82, green: 0.25, blue: 0.22)
        }
    }
}
