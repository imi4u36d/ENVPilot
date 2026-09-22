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
                    .font(.system(.title2, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .contentTransition(.opacity)
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("环境检查")
                    .font(.system(.title2, weight: .semibold))

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
            if store.isRepairing {
                // 修复会装命令行工具、下载 Node，只转一个不确定的菊花是不够的：
                // 把服务端发来的阶段文字显示出来，用户才知道在进行哪一步。
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(store.repairStage ?? "正在配置…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else if let message = store.message {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(store.needsRepair ? DesignColor.statusWarning : Color.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 18, alignment: .topLeading)
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

            if store.isRepairing {
                // 一键配置可能要几分钟，必须留一个能停下来的出口（HIG：让用户能中止处理）。
                Button("取消配置") {
                    store.cancelRepair()
                }
                .appButton(.secondary, size: .small)
            } else if store.needsRepair {
                Button {
                    Task { await store.repair() }
                } label: {
                    Label("一键配置", systemImage: "wand.and.stars")
                }
                .appButton(.primary, size: .small)
                .disabled(store.isBusy)
            } else {
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
                            .font(.system(.body, weight: .semibold))
                            .foregroundStyle(statusTint)
                            .accessibilityHidden(true)
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

                // 这段 detail 是这个面板存在的理由（缺什么、为什么），以前被
                // `lineLimit(1)` 裁成一行且没有 `.help()` 兜底，等于把结论藏起来。
                Text(check.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let repairHint = check.repairHint, check.status == .needsRepair || check.status == .failed {
                    Text(repairHint)
                        .font(.caption)
                        .foregroundStyle(statusTint)
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
        .accessibilityElement(children: .combine)
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
            return DesignColor.statusPositive
        case .needsRepair:
            return DesignColor.statusWarning
        case .optional:
            return .secondary
        case .failed:
            return DesignColor.statusNegative
        }
    }
}
