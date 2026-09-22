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
    /// 上一次扫描完成的时间。`hasLoaded` 永不过期会把几小时前的结论当成现状，
    /// 所以改成「新鲜度窗口 + 时间戳」，环境检查面板拿到的一定是近期数据。
    private var loadedAt: Date?
    /// 正在进行的扫描。后来者 await 它，而不是轮询 `isLoading`。
    private var loadTask: Task<[AIEnvironmentStatus], Never>?

    /// 扫描结果的新鲜度窗口。`refreshIfNeeded()` 在这段时间内直接复用。
    static let statusTTL: TimeInterval = 60
    /// 等一次在途扫描的上限。Core 的 shell 命令默认有 30 分钟墙钟上限，
    /// 但界面不该陪着它等 30 分钟，所以这里单独收口。
    private static let scanTimeout: Duration = .seconds(150)

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

    /// 状态是否足够新，可以直接复用。
    var hasFreshStatuses: Bool {
        guard let loadedAt else {
            return false
        }
        return Date().timeIntervalSince(loadedAt) < Self.statusTTL
    }

    func refresh() async {
        guard !isUpdating else {
            return
        }
        // 已经有扫描在跑：等它，而不是再起一次。
        if let inFlight = loadTask {
            if case .success(.none) = await BoundedAwait.value(of: inFlight, timeout: Self.scanTimeout) {
                reportScanTimeout()
            }
            return
        }
        isLoading = true
        statusMessage = nil
        let service = self.service
        let task = Task.detached(priority: .userInitiated) {
            await service.loadStatuses()
        }
        loadTask = task
        defer {
            loadTask = nil
            isLoading = false
        }

        guard case .success(.some(let loaded)) = await BoundedAwait.value(of: task, timeout: Self.scanTimeout) else {
            reportScanTimeout()
            return
        }
        statuses = loaded
        loadedAt = Date()
    }

    /// 扫描超时：保留上一次结果并提示一次，避免把旧结论当成现状。
    private func reportScanTimeout() {
        guard statusMessage == nil else {
            return
        }
        statusMessage = StatusMessage(
            text: "读取 AI 环境状态超时，已放弃等待；稍后可以再刷新一次。",
            tone: .error
        )
    }

    func refreshIfNeeded() async {
        guard !hasFreshStatuses else {
            return
        }
        await refresh()
    }

    /// 「等到有结果再返回」。新的 `refresh()` 本身就会等在途扫描，
    /// 所以这里不再需要单独轮询 `isLoading`（原先的轮询没有上限）。
    func refreshIfNeededAndWait() async {
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
        // 没有在跑的操作时必须直接返回：`.cancelling` 的 rawValue 最大，
        // 一旦写上就只有 `perform` 的 defer 能清掉，会把这一行永久钉在「正在取消…」。
        guard isBusy(kind) else {
            return
        }
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
