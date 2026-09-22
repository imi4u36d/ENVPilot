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

    init(
        service: any PackageManagerServicing = LocalPackageManagerService(),
        configStore: ConfigStore = ConfigStore()
    ) {
        self.service = service
        self.configStore = configStore
        self.statuses = PackageManagerKind.allCases.map { PackageManagerStatus(kind: $0) }
        self.mirrorSettings = (try? configStore.load().packageManagerMirrors)
            ?? PackageManagerMirrorSettings()
        Task { await refresh() }
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
        isLoading = false
    }

    func refreshIfNeeded() async {
        guard !hasLoaded else {
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
        var settings: AppSettings
        do {
            settings = try configStore.load()
        } catch {
            statusMessage = StatusMessage(
                text: "读取设置失败：\(error.localizedDescription)",
                tone: .error
            )
            return
        }
        settings.packageManagerMirrors.setAddress(address, for: kind)

        do {
            try configStore.save(settings)
            mirrorSettings = settings.packageManagerMirrors
            statusMessage = StatusMessage(
                text: settings.packageManagerMirrors.address(for: kind) == nil
                    ? "\(kind.displayName) 已恢复为官方地址。"
                    : "\(kind.displayName) 镜像地址已保存。",
                tone: .notice
            )
            await refresh(clearStatus: false)
        } catch {
            statusMessage = StatusMessage(
                text: "保存 \(kind.displayName) 镜像地址失败：\(error.localizedDescription)",
                tone: .error
            )
        }
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
                    text: "\(kind.displayName) 已切换到 ENVPilot 安装，当前版本 \(updated.currentVersion ?? "最新版")。",
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
