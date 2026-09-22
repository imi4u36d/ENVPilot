import Foundation
import ENVPilotCore

// MARK: - 有界等待

/// 有界等待：任务完成、失败、超时，先到者决定结果。
///
/// 不能用 `withTaskGroup` 做超时——作用域退出会等所有子任务，被卡住的那个照样把
/// 超时分支一起拖住。这里用一个一次性结果槽让「等任务」和「超时」两条路径竞争，
/// 超时后不再等后台任务（Core 的同步 API 不响应取消，任务会自己跑完，只是没人再等它）。
enum BoundedAwait {
    /// - `.success(.some(value))`：任务成功返回；
    /// - `.failure(error)`：任务抛错；
    /// - `.success(.none)`：超时（`Duration` 到点）。
    static func value<T: Sendable, E: Error>(
        of task: Task<T, E>,
        timeout: Duration
    ) async -> Result<T?, E> {
        let slot = ResultSlot<T, E>()
        Task {
            slot.settle(await task.result.map { Optional($0) })
        }
        Task {
            try? await Task.sleep(for: timeout)
            slot.settle(.success(nil))
        }
        return await slot.wait()
    }
}

/// 一次性结果槽：`settle` 只认第一次调用，`wait` 无论先后都能拿到结果。
private final class ResultSlot<T: Sendable, E: Error>: @unchecked Sendable {
    private let lock = NSLock()
    private var finished = false
    private var stored: Result<T?, E>?
    private var continuation: CheckedContinuation<Result<T?, E>, Never>?

    func settle(_ result: Result<T?, E>) {
        lock.lock()
        guard !finished else {
            lock.unlock()
            return
        }
        finished = true
        stored = result
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(returning: result)
    }

    func wait() async -> Result<T?, E> {
        await withCheckedContinuation { continuation in
            lock.lock()
            if finished, let stored {
                lock.unlock()
                continuation.resume(returning: stored)
                return
            }
            self.continuation = continuation
            lock.unlock()
        }
    }
}

// MARK: - Status + candidates

struct StatusMessage: Equatable {
    enum Tone: Equatable {
        case notice
        case error
    }

    let text: String
    let tone: Tone
}

struct InstallCandidate: Identifiable, Hashable {
    let kind: RuntimeKind
    let displayVersion: String
    let subtitle: String
    let argument: String
    var isInstalled: Bool
    let isRecommended: Bool
    let badge: String?

    var id: String {
        "\(kind.rawValue):\(displayVersion)"
    }

    var title: String {
        switch kind {
        case .node:
            return "Node \(displayVersion)"
        case .java:
            return "JDK \(displayVersion)"
        case .python:
            return "Python \(displayVersion)"
        }
    }
}

// MARK: - Store

@MainActor
final class NodeRuntimeStore: ObservableObject {
    @Published private(set) var snapshot: NodeRuntimeSnapshot?
    @Published private(set) var summaries: [RuntimeSummary] = []
    @Published private(set) var candidates: [InstallCandidate] = []
    @Published private(set) var isLoading = false
    @Published private(set) var busyKey: String?
    /// 正在执行操作的运行时类别。安装/卸载都可能跑很久，界面据此显示取消入口。
    @Published private(set) var busyKinds: Set<RuntimeKind> = []
    /// 排在闸门后等待的操作数。前一个操作没结束时，刷新会排队而不是被静默丢弃。
    @Published private(set) var queuedOperationCount = 0
    @Published private(set) var progressMessage: String?
    @Published private(set) var progressFraction: Double?
    @Published private(set) var statusMessage: StatusMessage?
    @Published private(set) var lastRefreshSucceeded = false

    private let service: any NodeRuntimeServicing
    /// 每个运行时当前操作的取消令牌，由 `cancelOperation(_:)` 消费。
    private var cancellations: [RuntimeKind: ShellCommandCancellation] = [:]
    /// 串行闸门：同一时刻只跑一个操作，后来者挂在闸门上等前一个真正结束。
    private var gateBusy = false
    private var gateWaiters: [CheckedContinuation<Void, Never>] = []
    private var activeKeys: Set<String> = []
    private var activeOperations = 0

    /// 单个后台操作的最长等待：Core 的 shell 命令最长 60 分钟（Python 源码构建），
    /// 再留一点余量。超过说明连墙钟上限都没兜住，宁可放弃等待也不要永远挂住界面。
    private static let operationTimeout: Duration = .seconds(Int(ShellCommandRunner.longRunningTimeout) + 120)

    init(service: any NodeRuntimeServicing = LocalNodeRuntimeService()) {
        self.service = service
        Task { await self.refresh() }
    }

    // MARK: Derived state

    var isBusy: Bool {
        isLoading
    }

    func isBusy(key: String) -> Bool {
        busyKey == key
    }

    /// 该运行时是否有操作正在跑（与 `AIEnvironmentStore` / `PackageManagerStore` 同名同义）。
    func isBusy(_ kind: RuntimeKind) -> Bool {
        busyKinds.contains(kind)
    }

    /// 取消某个运行时正在进行的安装/卸载。
    ///
    /// 与另外两个 store 一样先判断有没有操作在跑：没有令牌就直接返回，
    /// 否则会把界面永久钉在「正在取消」上（只有操作的 `defer` 能清理这个状态）。
    func cancelOperation(_ kind: RuntimeKind) {
        guard let cancellation = cancellations[kind] else {
            return
        }
        if busyKinds.contains(kind) {
            progressMessage = "正在取消…"
            progressFraction = nil
        }
        cancellation.cancel()
    }

    func progress(forKey key: String) -> (message: String, fraction: Double?)? {
        guard busyKey == key, let progressMessage else {
            return nil
        }
        return (progressMessage, progressFraction)
    }

    func summary(for kind: RuntimeKind) -> RuntimeSummary {
        summaries.first(where: { $0.id == kind.rawValue }) ?? .empty(kind)
    }

    func candidates(for kind: RuntimeKind) -> [InstallCandidate] {
        candidates.filter { $0.kind == kind }
    }

    var hasAnyRuntime: Bool {
        summaries.contains { !$0.options.isEmpty }
    }

    var statusSummary: String {
        guard !summaries.isEmpty else {
            return "正在读取运行时信息…"
        }
        let parts = summaries.compactMap { summary -> String? in
            guard summary.version != RuntimeSummary.emptyVersion else {
                return nil
            }
            return "\(summary.kind.commandName) \(VersionLabel.display(summary.kind, summary.version))"
        }
        return parts.isEmpty ? "未选择任何运行时" : parts.joined(separator: " · ")
    }

    func dismissStatus() {
        statusMessage = nil
    }

    // MARK: Operations

    func refresh() async {
        let succeeded = await runSnapshotOperation(
            key: "refresh",
            message: "正在读取运行时信息…"
        ) { service, _, _ in
            return try service.loadSnapshot(progress: nil)
        } failure: { error in
            StatusMessage(text: "读取失败：\(error.localizedDescription)", tone: .error)
        }
        lastRefreshSucceeded = succeeded
        rebuildSummaries()
    }

    func loadCandidates(for kind: RuntimeKind, force: Bool = false) async {
        guard force || candidates(for: kind).isEmpty else {
            return
        }

        let installedSnapshot = snapshot
        let key = "candidates:\(kind.rawValue)"

        let loaded: [InstallCandidate]? = await runListOperation(
            key: key,
            message: "正在获取 \(kind.title) 版本列表…"
        ) { service, _ in
            switch kind {
            case .node:
                return try service.listAvailableNodeVersions(ltsOnly: false).map {
                    InstallCandidate(
                        kind: .node,
                        displayVersion: $0.version,
                        subtitle: $0.lts.map { "LTS \($0)" } ?? "Current",
                        argument: $0.version,
                        isInstalled: false,
                        isRecommended: $0.lts != nil,
                        badge: $0.lts == nil ? nil : "LTS"
                    )
                }
            case .java:
                return try service.listAvailableJavaVersions(ltsOnly: false).map {
                    let isLTS = $0.version.contains("LTS")
                    return InstallCandidate(
                        kind: .java,
                        displayVersion: "\($0.featureVersion) (\($0.version))",
                        subtitle: $0.vendor,
                        argument: String($0.featureVersion),
                        isInstalled: false,
                        isRecommended: isLTS,
                        badge: isLTS ? "LTS" : nil
                    )
                }
            case .python:
                return try service.listAvailablePythonVersions(stableOnly: false).map {
                    let isStable = !$0.version.contains("rc") && !$0.version.contains("b")
                    return InstallCandidate(
                        kind: .python,
                        displayVersion: $0.version,
                        subtitle: "CPython 源码构建",
                        argument: $0.version,
                        isInstalled: false,
                        isRecommended: isStable,
                        badge: nil
                    )
                }
            }
        } failure: { error in
            StatusMessage(text: "获取版本列表失败：\(error.localizedDescription)", tone: .error)
        }

        guard let loaded else {
            return
        }

        var updated = candidates.filter { $0.kind != kind }
        updated.append(contentsOf: loaded.map { candidate in
            guard let installedSnapshot else {
                return candidate
            }
            let isInstalled = RuntimeSnapshotReader
                .installations(for: candidate.kind, in: installedSnapshot)
                .contains { RuntimeSnapshotReader.matches(installed: $0.version, requested: candidate.argument, kind: candidate.kind) }
            var mutable = candidate
            mutable.isInstalled = isInstalled
            return mutable
        })
        candidates = updated
    }

    @discardableResult
    func selectDefault(_ runtime: InstalledRuntime) async -> Bool {
        let key = "switch:\(runtime.kind.rawValue)"
        guard !isBusy(key: key) else {
            statusMessage = StatusMessage(text: "已有操作正在进行，请稍候后再试。", tone: .notice)
            return false
        }
        let title = "\(runtime.kind.title) \(runtime.version)"
        let succeeded = await runSnapshotOperation(
            key: key,
            message: "正在切换 \(title)…"
        ) { service, _, progress in
            switch runtime.kind {
            case .node:
                return try service.setDefaultNode(version: runtime.version, progress: progress)
            case .java:
                return try service.setDefaultJava(version: runtime.version, homePath: runtime.path)
            case .python:
                return try service.setDefaultPython(version: runtime.version, homePath: runtime.path)
            }
        } failure: { error in
            StatusMessage(text: "切换失败：\(error.localizedDescription)", tone: .error)
        }
        if succeeded {
            statusMessage = StatusMessage(text: "已切换 \(title)，新开的终端将使用该版本。", tone: .notice)
        }
        rebuildSummaries()
        return succeeded
    }

    func install(_ candidate: InstallCandidate) async {
        let key = "install:\(candidate.id)"
        guard !candidate.isInstalled, !isBusy(key: key) else {
            return
        }
        let succeeded = await runSnapshotOperation(
            key: key,
            kind: candidate.kind,
            message: "正在安装 \(candidate.title)…"
        ) { service, cancellation, progress in
            switch candidate.kind {
            case .node:
                return try service.installNode(
                    version: candidate.argument,
                    cancellation: cancellation,
                    progress: progress
                )
            case .java:
                guard let featureVersion = Int(candidate.argument) else {
                    throw RuntimeStoreError.invalidVersion(candidate.argument)
                }
                return try service.installJava(
                    featureVersion: featureVersion,
                    cancellation: cancellation,
                    progress: progress
                )
            case .python:
                return try service.installPython(
                    version: candidate.argument,
                    cancellation: cancellation,
                    progress: progress
                )
            }
        } failure: { error in
            StatusMessage(text: "安装 \(candidate.title) 失败：\(error.localizedDescription)", tone: .error)
        }
        if succeeded {
            statusMessage = StatusMessage(text: "\(candidate.title) 安装完成，可在此设为默认。", tone: .notice)
        }
        rebuildSummaries()
    }

    func uninstall(kind: RuntimeKind, version: String, path: String) async {
        let succeeded = await runSnapshotOperation(
            key: "uninstall:\(kind.rawValue):\(path)",
            kind: kind,
            message: "正在卸载…"
        ) { service, cancellation, progress in
            switch kind {
            case .node:
                return try service.uninstallNode(
                    version: version,
                    cancellation: cancellation,
                    progress: progress
                )
            case .java:
                return try service.uninstallJava(
                    homePath: path,
                    cancellation: cancellation,
                    progress: progress
                )
            case .python:
                return try service.uninstallPython(
                    homePath: path,
                    cancellation: cancellation,
                    progress: progress
                )
            }
        } failure: { error in
            StatusMessage(text: "卸载失败：\(error.localizedDescription)", tone: .error)
        }
        if succeeded {
            statusMessage = StatusMessage(text: "已卸载。", tone: .notice)
        }
        rebuildSummaries()
    }

    // MARK: Plumbing

    /// 排队等闸门。
    ///
    /// 以前是「轮询 isLoading 最多 2 秒」，超过就把后来的请求静默丢掉：长安装期间点
    /// 「刷新」会毫无反应。现在后来者挂在闸门上等前一个操作真正结束，等待期间
    /// `queuedOperationCount > 0`，界面可以显示「等待当前操作结束」。
    /// 同一个 key 的操作不会重复排队。
    private func enterOperation(key: String) async -> Bool {
        guard !activeKeys.contains(key) else {
            statusMessage = StatusMessage(text: "已有相同操作正在进行，请稍候后再试。", tone: .notice)
            return false
        }
        activeKeys.insert(key)
        let shouldQueue = activeOperations > 0
        if shouldQueue {
            queuedOperationCount += 1
        }
        await acquireGate()
        if shouldQueue {
            queuedOperationCount -= 1
        }
        activeOperations += 1
        return true
    }

    private func leaveOperation(key: String) {
        activeKeys.remove(key)
        activeOperations -= 1
        releaseGate()
    }

    private func acquireGate() async {
        if !gateBusy {
            gateBusy = true
            return
        }
        await withCheckedContinuation { continuation in
            gateWaiters.append(continuation)
        }
    }

    /// 释放闸门：有排队者就把闸门直接交给它（闸门始终被持有），否则置空。
    private func releaseGate() {
        if gateWaiters.isEmpty {
            gateBusy = false
            return
        }
        gateWaiters.removeFirst().resume()
    }

    private func beginOperation(key: String, message: String) {
        isLoading = true
        busyKey = key
        progressMessage = message
        progressFraction = nil
        statusMessage = nil
    }

    private func endOperation() {
        isLoading = false
        busyKey = nil
        progressMessage = nil
        progressFraction = nil
    }

    private func makeProgress(for key: String) -> @Sendable (String) -> Void {
        { [weak self] message in
            Task { @MainActor [weak self] in
                guard let self, self.busyKey == key else {
                    return
                }
                self.progressMessage = message
                self.progressFraction = RuntimeInstallationProgress(candidateID: key, message: message).fractionCompleted
            }
        }
    }

    @discardableResult
    private func runSnapshotOperation(
        key: String,
        kind: RuntimeKind? = nil,
        message: String,
        _ work: @escaping @Sendable (any NodeRuntimeServicing, ShellCommandCancellation?, @escaping @Sendable (String) -> Void) throws -> NodeRuntimeSnapshot,
        failure: (Error) -> StatusMessage
    ) async -> Bool {
        guard await enterOperation(key: key) else {
            return false
        }
        let cancellation = kind.map { _ in ShellCommandCancellation() }
        if let kind, let cancellation {
            busyKinds.insert(kind)
            cancellations[kind] = cancellation
        }
        beginOperation(key: key, message: message)
        defer {
            if let kind {
                busyKinds.remove(kind)
                cancellations[kind] = nil
            }
            endOperation()
            leaveOperation(key: key)
        }

        let progress = makeProgress(for: key)
        let service = self.service
        let task = Task.detached(priority: .userInitiated) {
            try work(service, cancellation, progress)
        }
        switch await BoundedAwait.value(of: task, timeout: Self.operationTimeout) {
        case .success(.some(let updated)):
            snapshot = updated
            return true
        case .success(.none):
            statusMessage = StatusMessage(text: "操作超时，已放弃等待。后台任务可能仍在收尾。", tone: .error)
            return false
        case .failure(let error):
            if cancellation?.isCancelled == true || error is CancellationError {
                statusMessage = StatusMessage(text: "已取消操作。", tone: .notice)
            } else {
                statusMessage = failure(error)
            }
            return false
        }
    }

    private func runListOperation<T: Sendable>(
        key: String,
        message: String,
        _ work: @escaping @Sendable (any NodeRuntimeServicing, @escaping @Sendable (String) -> Void) throws -> T,
        failure: (Error) -> StatusMessage
    ) async -> T? {
        guard await enterOperation(key: key) else {
            return nil
        }
        beginOperation(key: key, message: message)
        defer {
            endOperation()
            leaveOperation(key: key)
        }

        let silentProgress: @Sendable (String) -> Void = { _ in }
        let service = self.service
        let task = Task.detached(priority: .userInitiated) {
            try work(service, silentProgress)
        }
        switch await BoundedAwait.value(of: task, timeout: Self.operationTimeout) {
        case .success(.some(let value)):
            return value
        case .success(.none):
            statusMessage = StatusMessage(text: "获取版本列表超时，已放弃等待。", tone: .error)
            return nil
        case .failure(let error):
            statusMessage = failure(error)
            return nil
        }
    }

    /// 快照一变就重算三类摘要。
    ///
    /// 这是纯计算，没有文件 IO，所以直接算完——原先挂在后台任务上只是为了给
    /// 「按项目目录向上查找 `.envpilot`」腾出 IO 时间，那条链路已随项目作用域一起删除。
    private func rebuildSummaries() {
        guard let snapshot else {
            summaries = []
            return
        }
        summaries = RuntimeSnapshotReader.summaries(for: snapshot)
    }
}

enum RuntimeStoreError: LocalizedError {
    case invalidVersion(String)

    var errorDescription: String? {
        switch self {
        case .invalidVersion(let value):
            return "无法识别的版本：\(value)"
        }
    }
}
