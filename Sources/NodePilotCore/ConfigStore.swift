import Foundation

/// 读取 settings.json 时的诊断信息。
///
/// 以前解码失败会直接 throw，而调用方清一色 `try?`，于是「文件损坏」和「没有设置」
/// 无法区分，下一次 `save` 还会把坏文件覆盖掉。现在损坏文件先被移到一边，读取回落
/// 默认值，并把这件事报上来。
public enum ConfigStoreWarning: Sendable, Equatable {
    case corruptFileQuarantined(backupPath: String)

    public var message: String {
        switch self {
        case .corruptFileQuarantined(let backupPath):
            return "设置文件无法解析，已备份到 \(backupPath) 并使用默认设置。"
        }
    }
}

public struct ConfigStore: Sendable {
    /// 测试用的配置根目录覆盖。为 nil 时走真实的 `~/Library/Application Support/ENVPilot`。
    ///
    /// 没有这个入口时，任何针对「损坏文件会被隔离」「读操作不落盘」的测试都会去写用户
    /// 真实的设置文件——那是不能接受的副作用。
    private let baseDirectoryOverride: URL?

    public init() {
        baseDirectoryOverride = nil
    }

    /// 仅供测试：把配置根目录指到临时目录。
    public init(baseDirectory: URL) {
        baseDirectoryOverride = baseDirectory
    }

    /// 串行化 load / save / update：`NodeEnvironmentService` 与 `PackageManagerService`
    /// 各有多个「读-改-写」路径，没有这把锁时后写的会静默覆盖先写的。
    private static let gate = NSLock()
    private static let cache = SettingsCache()

    /// 读 settings.json。文件不存在时返回默认值，**不写文件**（写盘只由 `save` 触发）。
    public func load() throws -> AppSettings {
        try loadWithDiagnostics().settings
    }

    /// 带诊断的读取。`warning` 非空表示本次回落到了默认值。
    public func loadWithDiagnostics() throws -> (settings: AppSettings, warning: ConfigStoreWarning?) {
        let url = try settingsURL()
        Self.gate.lock()
        defer { Self.gate.unlock() }
        return try loadLocked(url: url)
    }

    public func save(_ settings: AppSettings) throws {
        let url = try settingsURL()
        Self.gate.lock()
        defer { Self.gate.unlock() }
        try saveLocked(settings, url: url)
    }

    /// 原子的「读-改-写」。用它替代散落的 `load()` + 改动 + `save()`。
    ///
    /// 返回值里的 `warning` 与 `loadWithDiagnostics()` 同义：文件损坏时本次读到的其实是
    /// 默认值，改完再写回去就等于用默认值覆盖了坏文件——调用方应当把这个警告显示出来。
    /// （`Q:` 以前这里用 `try?` 吞掉了解码错误，损坏事件在 update 路径上完全不可见。）
    @discardableResult
    public func updateWithDiagnostics(
        _ mutate: (inout AppSettings) throws -> Void
    ) throws -> (settings: AppSettings, warning: ConfigStoreWarning?) {
        let url = try settingsURL()
        Self.gate.lock()
        defer { Self.gate.unlock() }
        let loaded = try loadLocked(url: url)
        var settings = loaded.settings
        try mutate(&settings)
        try saveLocked(settings, url: url)
        return (settings, loaded.warning)
    }

    /// 便利版本，丢弃警告；需要区分「文件损坏」时请用 `updateWithDiagnostics`。
    @discardableResult
    public func update(_ mutate: (inout AppSettings) throws -> Void) throws -> AppSettings {
        try updateWithDiagnostics(mutate).settings
    }

    // MARK: - 内部（调用方必须已持有 gate）

    private func loadLocked(url: URL) throws -> (settings: AppSettings, warning: ConfigStoreWarning?) {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else {
            return (AppSettings(), nil)
        }

        let stamp = FileStamp(url: url)
        if let cached = Self.cache.value(for: url, stamp: stamp) {
            return (cached, nil)
        }

        let data = try Data(contentsOf: url)
        do {
            let settings = try JSONDecoder().decode(AppSettings.self, from: data)
            Self.cache.store(settings, for: url, stamp: stamp)
            return (settings, nil)
        } catch {
            let backup = try? quarantineCorruptFile(at: url)
            Self.cache.invalidate()
            return (AppSettings(), backup.map { .corruptFileQuarantined(backupPath: $0.path) })
        }
    }

    private func saveLocked(_ settings: AppSettings, url: URL) throws {
        let fileManager = FileManager.default
        let directoryURL = try applicationSupportDirectory()
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(settings)
        try data.write(to: url, options: .atomic)
        Self.cache.store(settings, for: url, stamp: FileStamp(url: url))
    }

    /// 把坏文件改名留档，返回备份路径。
    private func quarantineCorruptFile(at url: URL) throws -> URL {
        let stamp = Self.timestampFormatter.string(from: Date())
        let backup = url.deletingLastPathComponent()
            .appendingPathComponent("\(url.lastPathComponent).corrupt-\(stamp)")
        try FileManager.default.moveItem(at: url, to: backup)
        return backup
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()

    // MARK: - 路径

    public func applicationSupportDirectory() throws -> URL {
        if let baseDirectoryOverride {
            return baseDirectoryOverride
        }
        let fileManager = FileManager.default
        guard let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw ConfigStoreError.unresolvedApplicationSupportDirectory
        }
        let envPilotURL = baseURL.appendingPathComponent("ENVPilot", isDirectory: true)
        if !fileManager.fileExists(atPath: envPilotURL.path) {
            let oldURL = baseURL.appendingPathComponent("NodePilot", isDirectory: true)
            if fileManager.fileExists(atPath: oldURL.path) {
                try? fileManager.createDirectory(at: envPilotURL, withIntermediateDirectories: true)
                let oldSettingsURL = oldURL.appendingPathComponent("settings.json")
                let newSettingsURL = envPilotURL.appendingPathComponent("settings.json")
                if fileManager.fileExists(atPath: oldSettingsURL.path), !fileManager.fileExists(atPath: newSettingsURL.path) {
                    try? fileManager.copyItem(at: oldSettingsURL, to: newSettingsURL)
                }
            }
        }
        return envPilotURL
    }

    /// `applicationSupportDirectory()` 会按需建目录，所以 `settingsURL()` 本身也有副作用。
    /// `update` / `save` 需要它；纯读路径靠 `fileExists` 判断，不落盘。
    public func settingsURL() throws -> URL {
        try applicationSupportDirectory().appendingPathComponent("settings.json")
    }
}

public enum ConfigStoreError: Error {
    case unresolvedApplicationSupportDirectory
}

/// 文件身份：路径 + 修改时间 + 大小。任一变化即视为缓存失效。
private struct FileStamp: Equatable {
    let modificationDate: Date?
    let size: UInt64?

    init(url: URL) {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        modificationDate = attributes?[.modificationDate] as? Date
        size = (attributes?[.size] as? NSNumber)?.uint64Value
    }
}

/// 进程内缓存，避免单次操作里反复读盘解码（`PackageManagerService` 曾一次操作读 4 次）。
private final class SettingsCache: @unchecked Sendable {
    private let lock = NSLock()
    private var url: URL?
    private var stamp: FileStamp?
    private var settings: AppSettings?

    func value(for url: URL, stamp: FileStamp) -> AppSettings? {
        lock.lock()
        defer { lock.unlock() }
        guard self.url == url, self.stamp == stamp else {
            return nil
        }
        return settings
    }

    func store(_ settings: AppSettings, for url: URL, stamp: FileStamp) {
        lock.lock()
        self.url = url
        self.stamp = stamp
        self.settings = settings
        lock.unlock()
    }

    func invalidate() {
        lock.lock()
        url = nil
        stamp = nil
        settings = nil
        lock.unlock()
    }
}
