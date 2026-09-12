import Foundation
import ENVPilotCore

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
    @Published private(set) var projectSnapshot: ProjectEnvironmentSnapshot?
    @Published private(set) var inspectedDirectory: URL?
    @Published private(set) var candidates: [InstallCandidate] = []
    @Published private(set) var isLoading = false
    @Published private(set) var busyKey: String?
    @Published private(set) var progressMessage: String?
    @Published private(set) var progressFraction: Double?
    @Published private(set) var statusMessage: StatusMessage?
    @Published private(set) var recentProjectPaths: [String]

    private let service: any NodeRuntimeServicing
    private let defaults: UserDefaults
    private var deriveTask: Task<Void, Never>?

    private static let recentProjectsKey = "envpilot.recentProjectPaths"
    private static let maxRecentProjects = 6

    init(
        service: any NodeRuntimeServicing = LocalNodeRuntimeService(),
        defaults: UserDefaults = .standard
    ) {
        self.service = service
        self.defaults = defaults
        self.recentProjectPaths = defaults.stringArray(forKey: Self.recentProjectsKey) ?? []
        Task { await self.refresh() }
    }

    // MARK: Derived state

    var isBusy: Bool {
        isLoading
    }

    func isBusy(key: String) -> Bool {
        busyKey == key
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

    // MARK: Project scope

    func setProjectDirectory(_ path: String?) {
        guard let path, !path.isEmpty else {
            inspectedDirectory = nil
            projectSnapshot = nil
            scheduleDerive()
            return
        }
        let url = URL(fileURLWithPath: path).standardizedFileURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            statusMessage = StatusMessage(text: "路径不存在：\(path)", tone: .error)
            return
        }
        inspectedDirectory = url
        rememberProject(url.path)
        scheduleDerive()
    }

    func forgetProject(_ path: String) {
        recentProjectPaths.removeAll { $0 == path }
        defaults.set(recentProjectPaths, forKey: Self.recentProjectsKey)
        if inspectedDirectory?.path == path {
            setProjectDirectory(nil)
        }
    }

    private func rememberProject(_ path: String) {
        var paths = recentProjectPaths
        paths.removeAll { $0 == path }
        paths.insert(path, at: 0)
        recentProjectPaths = Array(paths.prefix(Self.maxRecentProjects))
        defaults.set(recentProjectPaths, forKey: Self.recentProjectsKey)
    }

    // MARK: Operations

    func refresh() async {
        await runSnapshotOperation(
            key: "refresh",
            message: "正在读取运行时信息…"
        ) { service, _ in
            return try service.loadSnapshot(progress: nil)
        } failure: { error in
            StatusMessage(text: "读取失败：\(error.localizedDescription)", tone: .error)
        }
        scheduleDerive()
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

    func selectDefault(_ runtime: InstalledRuntime) async {
        let key = "switch:\(runtime.kind.rawValue)"
        guard !isBusy(key: key) else {
            return
        }
        let title = "\(runtime.kind.title) \(runtime.version)"
        let succeeded = await runSnapshotOperation(
            key: key,
            message: "正在切换 \(title)…"
        ) { service, progress in
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
        scheduleDerive()
    }

    func install(_ candidate: InstallCandidate) async {
        let key = "install:\(candidate.id)"
        guard !candidate.isInstalled, !isBusy(key: key) else {
            return
        }
        let succeeded = await runSnapshotOperation(
            key: key,
            message: "正在安装 \(candidate.title)…"
        ) { service, progress in
            switch candidate.kind {
            case .node:
                return try service.installNode(version: candidate.argument, progress: progress)
            case .java:
                guard let featureVersion = Int(candidate.argument) else {
                    throw RuntimeStoreError.invalidVersion(candidate.argument)
                }
                return try service.installJava(featureVersion: featureVersion, progress: progress)
            case .python:
                return try service.installPython(version: candidate.argument, progress: progress)
            }
        } failure: { error in
            StatusMessage(text: "安装 \(candidate.title) 失败：\(error.localizedDescription)", tone: .error)
        }
        if succeeded {
            statusMessage = StatusMessage(text: "\(candidate.title) 安装完成，可在概览中设为默认。", tone: .notice)
        }
        scheduleDerive()
    }

    func uninstall(kind: RuntimeKind, version: String, path: String) async {
        let succeeded = await runSnapshotOperation(
            key: "uninstall:\(kind.rawValue):\(path)",
            message: "正在卸载…"
        ) { service, progress in
            switch kind {
            case .node:
                return try service.uninstallNode(version: version, progress: progress)
            case .java:
                return try service.uninstallJava(homePath: path, progress: progress)
            case .python:
                return try service.uninstallPython(homePath: path, progress: progress)
            }
        } failure: { error in
            StatusMessage(text: "卸载失败：\(error.localizedDescription)", tone: .error)
        }
        if succeeded {
            statusMessage = StatusMessage(text: "已卸载。", tone: .notice)
        }
        scheduleDerive()
    }

    func setProjectPreference(_ preference: ProjectVersionPreference) async {
        await runSnapshotOperation(
            key: "preference",
            message: "正在更新项目策略…"
        ) { service, _ in
            return try service.setProjectVersionPreference(preference)
        } failure: { error in
            StatusMessage(text: "更新失败：\(error.localizedDescription)", tone: .error)
        }
        scheduleDerive()
    }

    // MARK: Profiles

    func setSelectedProfile(id: UUID) async {
        let succeeded = await runSnapshotOperation(
            key: "profile",
            message: "正在切换环境预设…"
        ) { service, _ in
            return try service.setSelectedProfile(id: id)
        } failure: { error in
            StatusMessage(text: "切换预设失败：\(error.localizedDescription)", tone: .error)
        }
        if succeeded, let name = snapshot?.settings.profiles.first(where: { $0.id == id })?.name {
            statusMessage = StatusMessage(text: "已切换到环境预设「\(name)」。", tone: .notice)
        }
        scheduleDerive()
    }

    @discardableResult
    func saveProfile(_ profile: EnvironmentProfile) async -> Bool {
        let succeeded = await runSnapshotOperation(
            key: "profile",
            message: "正在保存环境预设…"
        ) { service, _ in
            return try service.saveProfile(profile)
        } failure: { error in
            StatusMessage(text: "保存失败：\(error.localizedDescription)", tone: .error)
        }
        if succeeded {
            statusMessage = StatusMessage(text: "环境预设「\(profile.name)」已保存。", tone: .notice)
        }
        scheduleDerive()
        return succeeded
    }

    func createProfile(named name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }
        let succeeded = await runSnapshotOperation(
            key: "profile",
            message: "正在创建环境预设…"
        ) { service, _ in
            return try service.createProfile(named: trimmed)
        } failure: { error in
            StatusMessage(text: "创建失败：\(error.localizedDescription)", tone: .error)
        }
        if succeeded {
            statusMessage = StatusMessage(text: "已创建环境预设「\(trimmed)」。", tone: .notice)
        }
        scheduleDerive()
    }

    // MARK: Plumbing

    /// 串行化：所有写操作等待前一个操作结束（最多 2 秒），避免并发下载/切换互相覆盖状态。
    private func acquireOrSkip() async -> Bool {
        var remaining = 40
        while isLoading, remaining > 0 {
            try? await Task.sleep(nanoseconds: 50_000_000)
            remaining -= 1
        }
        guard isLoading else {
            return true
        }
        statusMessage = StatusMessage(text: "已有操作正在进行，请稍候后再试。", tone: .notice)
        return false
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
        { message in
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
        message: String,
        _ work: @escaping @Sendable (any NodeRuntimeServicing, @escaping @Sendable (String) -> Void) throws -> NodeRuntimeSnapshot,
        failure: (Error) -> StatusMessage
    ) async -> Bool {
        guard await acquireOrSkip() else {
            return false
        }
        beginOperation(key: key, message: message)
        defer { endOperation() }

        let progress = makeProgress(for: key)
        do {
            let service = self.service
            let updated = try await Task.detached(priority: .userInitiated) {
                try work(service, progress)
            }.value
            snapshot = updated
            return true
        } catch {
            statusMessage = failure(error)
            return false
        }
    }

    private func runListOperation<T: Sendable>(
        key: String,
        message: String,
        _ work: @escaping @Sendable (any NodeRuntimeServicing, @escaping @Sendable (String) -> Void) throws -> T,
        failure: (Error) -> StatusMessage
    ) async -> T? {
        guard await acquireOrSkip() else {
            return nil
        }
        beginOperation(key: key, message: message)
        defer { endOperation() }

        let silentProgress: @Sendable (String) -> Void = { _ in }
        do {
            let service = self.service
            return try await Task.detached(priority: .userInitiated) {
                try work(service, silentProgress)
            }.value
        } catch {
            statusMessage = failure(error)
            return nil
        }
    }

    private func scheduleDerive() {
        deriveTask?.cancel()
        guard let snapshot else {
            projectSnapshot = nil
            summaries = []
            return
        }
        guard let inspectedDirectory else {
            projectSnapshot = nil
            summaries = RuntimeSnapshotReader.summaries(for: snapshot, directory: nil)
            return
        }

        deriveTask = Task { [weak self, snapshot] in
            guard let self else {
                return
            }
            let directory = inspectedDirectory
            let derived = await Task.detached(priority: .userInitiated) { () -> ([RuntimeSummary], ProjectEnvironmentSnapshot) in
                let summaries = RuntimeSnapshotReader.summaries(for: snapshot, directory: directory)
                let project = ProjectInspector.inspect(directory: directory, snapshot: snapshot)
                return (summaries, project)
            }.value
            guard !Task.isCancelled else {
                return
            }
            self.summaries = derived.0
            self.projectSnapshot = derived.1
        }
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
