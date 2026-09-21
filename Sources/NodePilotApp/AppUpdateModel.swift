import AppKit
import Foundation
import ENVPilotCore

/// 「检查更新」的状态机。网络与磁盘全部在 `ENVPilotCore.AppUpdateService` 里，
/// 这里只负责把它跑在后台线程、把结果整理成界面状态。
@MainActor
final class AppUpdateModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        case checking
        case upToDate(current: String, latest: String)
        case available(AppRelease)
        case downloading(message: String, fraction: Double?)
        case installing(AppRelease)
        /// 无法自动替换时，dmg 已下载并打开。
        case manual(release: AppRelease, location: URL)
        case failed(String)

        var release: AppRelease? {
            switch self {
            case .available(let release), .installing(let release), .manual(let release, _):
                return release
            default:
                return nil
            }
        }

        var isBusy: Bool {
            switch self {
            case .checking, .downloading, .installing:
                return true
            default:
                return false
            }
        }

        var isUpdateAvailable: Bool {
            if case .available = self {
                return true
            }
            return false
        }
    }

    /// 自动检查的开关与上次检查时间。设置页用 `@AppStorage` 绑同一个 key。
    static let automaticCheckKey = "envpilot.automaticUpdateCheck"
    private static let lastCheckKey = "envpilot.lastUpdateCheckAt"
    private static let automaticCheckInterval: TimeInterval = 24 * 60 * 60

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var lastCheckedAt: Date?

    let currentVersion: String
    private let service: AppUpdateService
    private let defaults: UserDefaults
    private let mode: AppUpdateInstallMode
    private var checkTask: Task<Void, Never>?

    init(
        service: AppUpdateService = AppUpdateService(configuration: .live()),
        defaults: UserDefaults = .standard
    ) {
        self.service = service
        self.defaults = defaults
        self.currentVersion = service.currentVersion
        self.mode = service.installMode()
        self.lastCheckedAt = defaults.object(forKey: Self.lastCheckKey) as? Date
    }

    // MARK: 派生状态

    /// 落点在启动时定一次就够：运行期间当前 app 的位置不会变。
    var installMode: AppUpdateInstallMode { mode }

    var hasUpdate: Bool { phase.isUpdateAvailable }

    var latestVersion: String? { phase.release?.version }

    var isBusy: Bool { phase.isBusy }

    var canSelfUpdate: Bool { mode.canSelfUpdate }

    var automaticCheckEnabled: Bool {
        defaults.object(forKey: Self.automaticCheckKey) as? Bool ?? true
    }

    /// 面板/页脚用的一句话摘要。
    var badgeText: String? {
        guard let version = latestVersion else {
            return nil
        }
        return "v\(version)"
    }

    // MARK: 检查

    /// 启动时静默检查，24 小时内只做一次。不会打断用户。
    func checkAutomaticallyIfNeeded() {
        guard automaticCheckEnabled else {
            return
        }
        if let lastCheckedAt, Date().timeIntervalSince(lastCheckedAt) < Self.automaticCheckInterval {
            return
        }
        checkTask?.cancel()
        checkTask = Task { [weak self] in
            await self?.check()
        }
    }

    @discardableResult
    func check() async -> AppUpdateCheck? {
        guard !phase.isBusy else {
            return nil
        }
        phase = .checking
        do {
            let service = self.service
            let check = try await Task.detached(priority: .userInitiated) {
                try service.checkForUpdate()
            }.value
            let now = Date()
            lastCheckedAt = now
            defaults.set(now, forKey: Self.lastCheckKey)
            switch check {
            case .upToDate(let current, let latest):
                phase = .upToDate(current: current, latest: latest)
            case .updateAvailable(let release):
                phase = .available(release)
            }
            return check
        } catch {
            phase = .failed(error.localizedDescription)
            return nil
        }
    }

    // MARK: 更新

    /// 一键更新。能原地替换就下载 zip、校验后换掉当前 app 并重启；
    /// 不能（`swift run`、只读位置）就退回下载 dmg 打开。
    func install() async {
        guard let release = phase.release, !phase.isBusy else {
            return
        }
        if mode.canSelfUpdate {
            await downloadAndApply(release)
        } else {
            await downloadDiskImage(release)
        }
    }

    private func downloadAndApply(_ release: AppRelease) async {
        phase = .downloading(message: "正在下载 ENVPilot \(release.version)…", fraction: nil)
        do {
            let service = self.service
            let staged = try await Task.detached(priority: .userInitiated) { [weak self] in
                try service.downloadAndStage(release) { progress in
                    Task { @MainActor in
                        self?.report(progress)
                    }
                }
            }.value

            phase = .installing(release)
            _ = try service.apply(staged)
            // 替换脚本已经在等本进程退出；这里主动退出，让它接着换包并重启。
            NSApp.terminate(nil)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func downloadDiskImage(_ release: AppRelease) async {
        phase = .downloading(message: "正在下载 ENVPilot \(release.version)…", fraction: nil)
        do {
            let service = self.service
            let location = try await Task.detached(priority: .userInitiated) { [weak self] in
                try service.downloadDiskImage(release) { progress in
                    Task { @MainActor in
                        self?.report(progress)
                    }
                }
            }.value
            phase = .manual(release: release, location: location)
            NSWorkspace.shared.open(location)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func report(_ progress: AppUpdateProgress) {
        guard case .downloading = phase else {
            return
        }
        phase = .downloading(message: progress.message, fraction: progress.fraction)
    }

    // MARK: 动作

    func openReleasePage() {
        guard let url = phase.release?.pageURL else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    func revealDownload(_ location: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([location])
    }

    // MARK: 探针/快照钩子

    /// 离屏快照与探针专用：直接注入一个状态，不联网。正常运行路径不会用到。
    func applyPreviewPhase(_ phase: Phase) {
        self.phase = phase
    }

    /// 等价于「检查到了这个版本」，用于菜单栏面板的「更新到 …」行快照。
    func applyPreviewRelease(_ release: AppRelease?) {
        phase = release.map { .available($0) } ?? .idle
    }
}

// MARK: - 更新说明

/// GitHub Release 的正文是 Markdown。设置窗口里只做一个轻量降级（去 `#`、`-` 换成
/// `•`、去掉强调符），不引入完整的 Markdown 渲染。
enum ReleaseNotesFormatter {
    static func plainText(_ markdown: String) -> String {
        var lines: [String] = []
        for rawLine in markdown.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false) {
            var line = String(rawLine)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#") {
                line = String(trimmed.drop { $0 == "#" }).trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                line = "• " + trimmed.dropFirst(2)
            } else {
                line = trimmed
            }
            line = line
                .replacingOccurrences(of: "**", with: "")
                .replacingOccurrences(of: "`", with: "")
            lines.append(line)
        }
        // 收掉开头/结尾的空行，避免卡片里出现一段空白。
        while let first = lines.first, first.isEmpty {
            lines.removeFirst()
        }
        while let last = lines.last, last.isEmpty {
            lines.removeLast()
        }
        return lines.joined(separator: "\n")
    }
}
