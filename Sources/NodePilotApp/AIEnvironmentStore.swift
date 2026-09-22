import ENVPilotCore
import Foundation

enum AIEnvironmentStoreAction: Equatable, Sendable {
    case install
    case update
    case switchToEnvPilot

    var progressFallback: String {
        switch self {
        case .install:
            return "正在准备安装"
        case .update:
            return "正在准备更新"
        case .switchToEnvPilot:
            return "正在切换到 ENVPilot 管理"
        }
    }
}

@MainActor
final class AIEnvironmentStore: ObservableObject {
    @Published private(set) var statuses: [AIEnvironmentStatus]
    @Published private(set) var isLoading = false
    @Published private(set) var busyKinds: Set<AIEnvironmentKind> = []
    @Published private(set) var busyActions: [AIEnvironmentKind: AIEnvironmentStoreAction] = [:]
    @Published private(set) var updateStages: [AIEnvironmentKind: AIEnvironmentUpdateStage] = [:]
    @Published private(set) var statusMessage: StatusMessage?

    private let service: any AIEnvironmentServicing
    private var cancellations: [AIEnvironmentKind: ShellCommandCancellation] = [:]
    private var hasLoaded = false

    init(service: any AIEnvironmentServicing = LocalAIEnvironmentService()) {
        self.service = service
        self.statuses = AIEnvironmentKind.allCases.map { AIEnvironmentStatus(kind: $0) }
        Task { await refresh() }
    }

    var installedCount: Int {
        statuses.filter(\.isInstalled).count
    }

    var availableUpdateCount: Int {
        statuses.filter(\.updateAvailable).count
    }

    func isBusy(_ kind: AIEnvironmentKind) -> Bool {
        busyKinds.contains(kind)
    }

    func updateStage(for kind: AIEnvironmentKind) -> AIEnvironmentUpdateStage? {
        updateStages[kind]
    }

    func busyAction(for kind: AIEnvironmentKind) -> AIEnvironmentStoreAction? {
        busyActions[kind]
    }

    var isUpdating: Bool {
        !busyKinds.isEmpty
    }

    var canUpdateAnyTool: Bool {
        statuses.contains { $0.updateAvailable && !isBusy($0.kind) }
    }

    func refresh() async {
        guard !isLoading, !isUpdating else {
            return
        }
        isLoading = true
        statusMessage = nil

        let service = self.service
        let loaded = await Task.detached(priority: .userInitiated) {
            await service.loadStatuses()
        }.value

        statuses = loaded
        hasLoaded = true
        isLoading = false
    }

    func refreshIfNeeded() async {
        guard !hasLoaded else {
            return
        }
        await refresh()
    }

    func refreshIfNeededAndWait() async {
        if isLoading {
            while isLoading {
                try? await Task.sleep(for: .milliseconds(60))
            }
            if hasLoaded {
                return
            }
        }
        await refreshIfNeeded()
    }

    func update(_ kind: AIEnvironmentKind) async {
        await perform(kind, action: .update)
    }

    func install(_ kind: AIEnvironmentKind) async {
        await perform(kind, action: .install)
    }

    func switchToEnvPilot(_ kind: AIEnvironmentKind) async {
        await perform(kind, action: .switchToEnvPilot)
    }

    func cancelOperation(_ kind: AIEnvironmentKind) {
        updateStages[kind] = .cancelling
        cancellations[kind]?.cancel()
    }

    func updateAvailableTools() async {
        let kinds = statuses
            .filter { $0.updateAvailable && !isBusy($0.kind) }
            .map(\.kind)
        guard !kinds.isEmpty else {
            return
        }
        for kind in kinds {
            await update(kind)
        }
    }

    func dismissStatus() {
        statusMessage = nil
    }

    private func perform(_ kind: AIEnvironmentKind, action: AIEnvironmentStoreAction) async {
        guard !isBusy(kind) else {
            return
        }
        busyKinds.insert(kind)
        busyActions[kind] = action
        let cancellation = ShellCommandCancellation()
        cancellations[kind] = cancellation
        updateStages[kind] = .connecting
        defer {
            busyKinds.remove(kind)
            busyActions[kind] = nil
            cancellations[kind] = nil
            updateStages[kind] = nil
        }
        statusMessage = nil

        let service = self.service
        do {
            let updated = try await Task.detached(priority: .userInitiated) {
                switch action {
                case .install:
                    return try await service.install(kind, cancellation: cancellation) { stage in
                        Task { @MainActor in
                            guard self.isBusy(kind) else {
                                return
                            }
                            if (self.updateStages[kind]?.rawValue ?? -1) <= stage.rawValue {
                                self.updateStages[kind] = stage
                            }
                        }
                    }
                case .update:
                    return try await service.update(kind, cancellation: cancellation) { stage in
                        Task { @MainActor in
                            guard self.isBusy(kind) else {
                                return
                            }
                            if (self.updateStages[kind]?.rawValue ?? -1) <= stage.rawValue {
                                self.updateStages[kind] = stage
                            }
                        }
                    }
                case .switchToEnvPilot:
                    return try await service.switchToEnvPilot(kind, cancellation: cancellation) { stage in
                        Task { @MainActor in
                            guard self.isBusy(kind) else {
                                return
                            }
                            if (self.updateStages[kind]?.rawValue ?? -1) <= stage.rawValue {
                                self.updateStages[kind] = stage
                            }
                        }
                    }
                }
            }.value
            replace(updated)
            switch action {
            case .install:
                statusMessage = StatusMessage(
                    text: "\(kind.displayName) 已安装 \(updated.currentVersion ?? "最新版")。",
                    tone: .notice
                )
            case .update:
                statusMessage = StatusMessage(
                    text: updated.updateAvailable
                        ? "\(kind.displayName) 更新命令已执行，但仍有新版本可用。"
                        : "\(kind.displayName) 已更新到 \(updated.currentVersion ?? "最新版")。",
                    tone: .notice
                )
            case .switchToEnvPilot:
                statusMessage = StatusMessage(
                    text: "\(kind.displayName) 已切换到 ENVPilot 管理，当前版本 \(updated.currentVersion ?? "最新版")。",
                    tone: .notice
                )
            }
        } catch {
            if cancellation.isCancelled || error is CancellationError {
                statusMessage = StatusMessage(
                    text: action == .install
                        ? "已取消安装 \(kind.displayName)。"
                        : action == .switchToEnvPilot
                            ? "已取消切换 \(kind.displayName)。"
                            : "已取消更新 \(kind.displayName)。",
                    tone: .notice
                )
            } else {
                statusMessage = StatusMessage(
                    text: action == .install
                        ? "安装 \(kind.displayName) 失败：\(error.localizedDescription)"
                        : action == .switchToEnvPilot
                            ? "切换 \(kind.displayName) 失败：\(error.localizedDescription)"
                            : "更新 \(kind.displayName) 失败：\(error.localizedDescription)",
                    tone: .error
                )
            }
        }
    }

    private func replace(_ status: AIEnvironmentStatus) {
        guard let index = statuses.firstIndex(where: { $0.kind == status.kind }) else {
            statuses.append(status)
            return
        }
        statuses[index] = status
    }
}
