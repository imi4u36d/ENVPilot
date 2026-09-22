import ENVPilotCore
import Foundation

enum PackageManagerStoreAction: Equatable, Sendable {
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
            return "正在切换到 ENVPilot 安装"
        }
    }
}

@MainActor
final class PackageManagerStore: ObservableObject {
    @Published private(set) var statuses: [PackageManagerStatus]
    @Published private(set) var isLoading = false
    @Published private(set) var busyKinds: Set<PackageManagerKind> = []
    @Published private(set) var busyActions: [PackageManagerKind: PackageManagerStoreAction] = [:]
    @Published private(set) var updateStages: [PackageManagerKind: AIEnvironmentUpdateStage] = [:]
    @Published private(set) var statusMessage: StatusMessage?
    @Published private(set) var mirrorSettings: PackageManagerMirrorSettings

    private let service: any PackageManagerServicing
    private let configStore: ConfigStore
    private var cancellations: [PackageManagerKind: ShellCommandCancellation] = [:]
    private var hasLoaded = false
    /// 上次刷新的时间。`hasLoaded` 永不过期的话，切回这个页面永远看不到新的包管理器状态。
    private var loadedAt: Date?
    private let statusTTL: TimeInterval = 60

    init(
        service: any PackageManagerServicing = LocalPackageManagerService(),
        configStore: ConfigStore = ConfigStore()
    ) {
        self.service = service
        self.configStore = configStore
        self.statuses = PackageManagerKind.allCases.map { PackageManagerStatus(kind: $0) }

        // 设置文件损坏（或读不出来）时不再静默回落默认值：`loadWithDiagnostics`
        // 会把坏文件挪到一边并给出一条中文说明，这里把它挂到状态栏上。
        var mirrors = PackageManagerMirrorSettings()
        var loadMessage: StatusMessage?
        do {
            let diagnostics = try configStore.loadWithDiagnostics()
            mirrors = diagnostics.settings.packageManagerMirrors
            if let warning = diagnostics.warning {
                loadMessage = StatusMessage(text: warning.message, tone: .error)
            }
        } catch {
            loadMessage = StatusMessage(text: "读取设置失败：\(error.localizedDescription)", tone: .error)
        }
        self.statusMessage = loadMessage
        self.mirrorSettings = mirrors
        // 首次刷新不清状态栏，否则刚发现的损坏警告会被立刻冲掉。
        Task { await refresh(clearStatus: false) }
    }

    var installedCount: Int {
        statuses.filter(\.isInstalled).count
    }

    var availableUpdateCount: Int {
        statuses.filter(\.updateAvailable).count
    }

    var isBusy: Bool {
        !busyKinds.isEmpty
    }

    var canUpdateAnyTool: Bool {
        statuses.contains { $0.updateAvailable && !isBusy($0.kind) }
    }

    func isBusy(_ kind: PackageManagerKind) -> Bool {
        busyKinds.contains(kind)
    }

    func busyAction(for kind: PackageManagerKind) -> PackageManagerStoreAction? {
        busyActions[kind]
    }

    func updateStage(for kind: PackageManagerKind) -> AIEnvironmentUpdateStage? {
        updateStages[kind]
    }

    func refresh(clearStatus: Bool = true) async {
        guard !isLoading, !isBusy else {
            return
        }
        isLoading = true
        if clearStatus {
            statusMessage = nil
        }

        let service = self.service
        let loaded = await Task.detached(priority: .userInitiated) {
            await service.loadStatuses()
        }.value

        statuses = loaded
        hasLoaded = true
        loadedAt = Date()
        isLoading = false
    }

    /// 首次进入、或上次结果超过 `statusTTL` 才重扫；`refresh()` 仍然是强制路径。
    func refreshIfNeeded() async {
        if hasLoaded, let loadedAt, Date().timeIntervalSince(loadedAt) < statusTTL {
            return
        }
        await refresh()
    }

    func install(_ kind: PackageManagerKind) async {
        await perform(kind, action: .install)
    }

    func update(_ kind: PackageManagerKind) async {
        await perform(kind, action: .update)
    }

    func switchToEnvPilot(_ kind: PackageManagerKind) async {
        await perform(kind, action: .switchToEnvPilot)
    }

    func cancelOperation(_ kind: PackageManagerKind) {
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

    func mirrorAddress(for kind: PackageManagerKind) -> String {
        mirrorSettings.address(for: kind) ?? ""
    }

    func saveMirror(_ address: String, for kind: PackageManagerKind) async {
        let configStore = self.configStore
        // 先带诊断读一次：设置文件损坏时 Core 会把它挪到一边并给出警告，
        // 这条警告必须让用户看到，不能再被 `try?` 吞掉。
        var warning: ConfigStoreWarning?
        do {
            warning = try configStore.loadWithDiagnostics().warning
        } catch {
            statusMessage = StatusMessage(
                text: "读取设置失败：\(error.localizedDescription)",
                tone: .error
            )
            return
        }

        do {
            // 原子「读-改-写」：两个并发的镜像保存不会再互相覆盖（load + save 之间的窗口没了）。
            let outcome = try await Task.detached(priority: .userInitiated) {
                try configStore.updateWithDiagnostics { settings in
                    settings.packageManagerMirrors.setAddress(address, for: kind)
                }
            }.value
            let settings = outcome.settings
            warning = outcome.warning ?? warning
            mirrorSettings = settings.packageManagerMirrors
            let saved = settings.packageManagerMirrors.address(for: kind) == nil
                ? "\(kind.displayName) 已恢复为官方地址。"
                : "\(kind.displayName) 镜像地址已保存。"
            if let warning {
                statusMessage = StatusMessage(text: "\(saved)\(warning.message)", tone: .error)
            } else {
                statusMessage = StatusMessage(text: saved, tone: .notice)
            }
            await refresh(clearStatus: false)
        } catch {
            statusMessage = StatusMessage(
                text: "保存 \(kind.displayName) 镜像地址失败：\(error.localizedDescription)",
                tone: .error
            )
        }
    }

    /// Core 把替用户挪进废纸篓的文件列在这里。它必须出现在成功提示里：
    /// 静默清掉别人 PATH 上的 `pnpm` / `uv` 最容易被当成「应用把我的环境搞坏了」。
    private func cleanupSuffix(_ status: PackageManagerStatus) -> String {
        guard let notice = status.cleanupNotice, !notice.isEmpty else {
            return ""
        }
        return " " + notice
    }

    private func perform(_ kind: PackageManagerKind, action: PackageManagerStoreAction) async {
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
                    text: "\(kind.displayName) 已安装 \(updated.currentVersion ?? "最新版")。\(cleanupSuffix(updated))",
                    tone: .notice
                )
            case .update:
                statusMessage = StatusMessage(
                    text: (updated.updateAvailable
                        ? "\(kind.displayName) 更新命令已执行，但仍有新版本可用。"
                        : "\(kind.displayName) 已更新到 \(updated.currentVersion ?? "最新版")。") + cleanupSuffix(updated),
                    tone: .notice
                )
            case .switchToEnvPilot:
                statusMessage = StatusMessage(
                    text: "\(kind.displayName) 已切换到 ENVPilot 安装，当前版本 \(updated.currentVersion ?? "最新版")。\(cleanupSuffix(updated))",
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

    private func replace(_ status: PackageManagerStatus) {
        guard let index = statuses.firstIndex(where: { $0.kind == status.kind }) else {
            statuses.append(status)
            return
        }
        statuses[index] = status
    }
}
