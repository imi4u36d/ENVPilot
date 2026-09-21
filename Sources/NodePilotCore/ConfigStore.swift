import Foundation

public struct ConfigStore: Sendable {
    public init() {}

    /// 读 settings.json。
    ///
    /// 老文件里可能留着 `profiles` / `selectedProfileID` / `projectVersionPreference`
    /// 三个键（「项目与预设」功能删除前写的）。`AppSettings` 用合成的 `Codable`，
    /// 未知键会被直接忽略，所以不需要迁移：读得出来，下一次 `save` 也就把它们清掉了。
    public func load() throws -> AppSettings {
        let url = try settingsURL()
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else {
            let defaults = AppSettings()
            try save(defaults)
            return defaults
        }

        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(AppSettings.self, from: data)
    }

    public func save(_ settings: AppSettings) throws {
        let fileManager = FileManager.default
        let directoryURL = try applicationSupportDirectory()
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(settings)
        try data.write(to: settingsURL(), options: .atomic)
    }

    public func applicationSupportDirectory() throws -> URL {
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

    public func settingsURL() throws -> URL {
        try applicationSupportDirectory().appendingPathComponent("settings.json")
    }
}

public enum ConfigStoreError: Error {
    case unresolvedApplicationSupportDirectory
}
