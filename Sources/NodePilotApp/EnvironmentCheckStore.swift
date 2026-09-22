import ENVPilotCore
import Foundation
import SwiftUI

@MainActor
final class EnvironmentCheckStore: ObservableObject {
    @Published var isPresented = false
    @Published private(set) var checks = EnvironmentSetupCheckKind.allCases.map(EnvironmentSetupCheckResult.pending)
    @Published private(set) var message: String?
    @Published private(set) var isChecking = false
    @Published private(set) var isRepairing = false
    /// 「一键配置」当前阶段的说明。装命令行工具、写 .zshrc、下载 Node……每一步都会更新，
    /// 界面据此显示进度文案而不是一个转不完的圈。
    @Published private(set) var repairStage: String?

    /// 报告的新鲜度窗口。面板每次打开都重跑一遍检查（几次 shell + 读 ~/.zshrc）不值得，
    /// 60 秒内直接复用上次结果；界面上的「重新检查」走 `refresh()`，永远是强制重扫。
    private static let reportTTL: TimeInterval = 60

    private let runtimeStore: NodeRuntimeStore
    private let aiStore: AIEnvironmentStore
    private let service: EnvironmentSetupService
    /// 注入给 `service` 的运行时包装，用来把取消令牌接到 Core 的 Node 安装上。
    private let runtimeProvider: CancellableNodeRuntimeProvider
    private var reportDate: Date?
    private var repairCancellation: ShellCommandCancellation?

    init(
        runtimeStore: NodeRuntimeStore,
        aiStore: AIEnvironmentStore,
        service: EnvironmentSetupService? = nil
    ) {
        self.runtimeStore = runtimeStore
        self.aiStore = aiStore
        let provider = CancellableNodeRuntimeProvider()
        self.runtimeProvider = provider
        // 只有默认构造的 service 才拿到可取消的 provider；外部传进来的 service 保持原样。
        self.service = service ?? EnvironmentSetupService(runtimeProvider: provider)
    }

    var isBusy: Bool {
        isChecking || isRepairing
    }

    var needsRepair: Bool {
        checks.contains { $0.status == .needsRepair || $0.status == .failed }
    }

    /// 是否已有一份足够新的报告可以复用。
    var hasFreshReport: Bool {
        guard let reportDate else {
            return false
        }
        return Date().timeIntervalSince(reportDate) < Self.reportTTL
    }

    func present() {
        isPresented = true
        guard !isBusy, !hasFreshReport else {
            return
        }
        Task { await refresh() }
    }

    func dismiss() {
        guard !isBusy else {
            return
        }
        isPresented = false
    }

    /// 重新检查。这是强制重扫路径（面板里的「重新检查」按钮），不吃 TTL。
    func refresh() async {
        guard !isBusy else {
            return
        }
        isChecking = true
        defer { isChecking = false }
        message = nil
        checks = EnvironmentSetupCheckKind.allCases.map(EnvironmentSetupCheckResult.pending)

        await aiStore.refreshIfNeededAndWait()
        let statuses = aiStore.statuses
        let service = self.service
        let report = await Task.detached(priority: .userInitiated) {
            service.check(aiStatuses: statuses)
        }.value

        checks = report.checks
        message = report.message
        reportDate = Date()
    }

    /// 一键配置。进度与取消令牌都接到 Core 上：下载 Node 这类长任务不再是黑盒。
    func repair() async {
        guard !isBusy else {
            return
        }
        isRepairing = true
        defer {
            isRepairing = false
            repairStage = nil
            repairCancellation = nil
            runtimeProvider.setCancellation(nil)
        }
        message = nil

        let cancellation = ShellCommandCancellation()
        repairCancellation = cancellation
        runtimeProvider.setCancellation(cancellation)
        repairStage = "正在准备配置…"

        let statuses = aiStore.statuses
        let service = self.service
        let report = await Task.detached(priority: .userInitiated) { [weak self] in
            service.repair(aiStatuses: statuses) { stage in
                Task { @MainActor in
                    self?.repairStage = stage
                }
            }
        }.value

        await runtimeStore.refresh()
        await aiStore.refresh()
        checks = report.checks
        message = cancellation.isCancelled ? "已取消环境配置。" : report.message
        reportDate = Date()
    }

    /// 取消正在进行的「一键配置」。
    ///
    /// 令牌经 `CancellableNodeRuntimeProvider` 传到 Node 安装那一段（下载/源码构建），
    /// 这是整个流程里唯一会跑很久的部分；复制命令行工具和写 `.zshrc` 都是瞬时的，
    /// 没有中间可中断点。没有在配置时直接返回，避免把界面钉在「正在取消」。
    func cancelRepair() {
        guard isRepairing else {
            return
        }
        repairStage = "正在取消…"
        repairCancellation?.cancel()
    }
}

/// 把取消令牌接到 Node 安装上的 provider 包装。
///
/// `EnvironmentSetupService.repair` 自己没有取消参数，但它只通过
/// `EnvironmentNodeRuntimeProviding` 使用运行时能力，所以在 store 这一层包一层：
/// 配置过程中点取消，正在下载/构建的 Node 安装能收到令牌。
private final class CancellableNodeRuntimeProvider: EnvironmentNodeRuntimeProviding, @unchecked Sendable {
    private let service: NodeEnvironmentService
    private let lock = NSLock()
    private var cancellation: ShellCommandCancellation?

    init(service: NodeEnvironmentService = NodeEnvironmentService()) {
        self.service = service
    }

    func setCancellation(_ cancellation: ShellCommandCancellation?) {
        lock.lock()
        self.cancellation = cancellation
        lock.unlock()
    }

    private var token: ShellCommandCancellation? {
        lock.lock()
        defer { lock.unlock() }
        return cancellation
    }

    func loadSnapshot(progress: (@Sendable (String) -> Void)?) throws -> NodeRuntimeSnapshot {
        try service.loadSnapshot(progress: progress)
    }

    func listAvailableNodeVersions(ltsOnly: Bool) throws -> [NodeDownloadCandidate] {
        try service.listAvailableNodeVersions(ltsOnly: ltsOnly)
    }

    func selectDefaultNode(version: String, progress: (@Sendable (String) -> Void)?) throws -> NodeRuntimeSnapshot {
        try service.selectDefaultNode(version: version, progress: progress)
    }

    /// 这里持有的是具体的 `NodeEnvironmentService`（而不是 `any EnvironmentNodeRuntimeProviding`），
    /// 因为只有具体类型能拿到带 `cancellation:` 的安装入口——repair 里最耗时的下载/构建就靠它。
    func installNode(version: String, progress: (@Sendable (String) -> Void)?) throws -> NodeRuntimeSnapshot {
        try service.installNode(
            version: version,
            cancellation: token,
            progress: progress
        )
    }
}
