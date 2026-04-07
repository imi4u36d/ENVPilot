import Foundation
import ENVPilotCore

protocol NodeRuntimeServicing: Sendable {
    func loadSnapshot(progress: (@Sendable (String) -> Void)?) throws -> NodeRuntimeSnapshot
    func setDefaultNode(version: String, progress: (@Sendable (String) -> Void)?) throws
    func installNode(version: String, progress: (@Sendable (String) -> Void)?) throws
    func uninstallNode(version: String, progress: (@Sendable (String) -> Void)?) throws
    func installSDKMAN(progress: (@Sendable (String) -> Void)?) throws
    func listAvailableJavaCandidatesWithSDKMAN() throws -> [SDKMANJavaCandidate]
    func installJavaWithSDKMAN(identifier: String, progress: (@Sendable (String) -> Void)?) throws
    func uninstallJava(homePath: String, progress: (@Sendable (String) -> Void)?) throws
    func uninstallJavaWithSDKMAN(identifier: String, progress: (@Sendable (String) -> Void)?) throws
    func setDefaultJava(version: String, homePath: String) throws
    func setSelectedProfile(id: UUID) throws
    func saveProfile(_ profile: EnvironmentProfile) throws
    func createProfile(named name: String) throws -> UUID
    func setProjectVersionPreference(_ preference: ProjectVersionPreference) throws
}

struct LocalNodeRuntimeService: NodeRuntimeServicing {
    private let configStore: ConfigStore
    private let environmentService: NodeEnvironmentService

    init(
        configStore: ConfigStore = ConfigStore(),
        commandRunner: any ShellCommandRunning = ShellCommandRunner()
    ) {
        self.configStore = configStore
        self.environmentService = NodeEnvironmentService(
            configStore: configStore,
            shellRunner: commandRunner
        )
    }

    func loadSnapshot(progress: (@Sendable (String) -> Void)? = nil) throws -> NodeRuntimeSnapshot {
        try environmentService.loadSnapshot(progress: progress)
    }

    func setDefaultNode(version: String, progress: (@Sendable (String) -> Void)? = nil) throws {
        _ = try environmentService.selectDefaultNode(version: version, progress: progress)
    }

    func installNode(version: String, progress: (@Sendable (String) -> Void)? = nil) throws {
        _ = try environmentService.installNode(version: version, progress: progress)
    }

    func uninstallNode(version: String, progress: (@Sendable (String) -> Void)? = nil) throws {
        _ = try environmentService.uninstallNode(version: version, progress: progress)
    }

    func installSDKMAN(progress: (@Sendable (String) -> Void)? = nil) throws {
        _ = try environmentService.installSDKMAN(progress: progress)
    }

    func listAvailableJavaCandidatesWithSDKMAN() throws -> [SDKMANJavaCandidate] {
        try environmentService.listAvailableJavaCandidatesWithSDKMAN()
    }

    func installJavaWithSDKMAN(identifier: String, progress: (@Sendable (String) -> Void)? = nil) throws {
        _ = try environmentService.installJavaWithSDKMAN(identifier: identifier, progress: progress)
    }

    func uninstallJava(homePath: String, progress: (@Sendable (String) -> Void)? = nil) throws {
        _ = try environmentService.uninstallJava(homePath: homePath, progress: progress)
    }

    func uninstallJavaWithSDKMAN(identifier: String, progress: (@Sendable (String) -> Void)? = nil) throws {
        _ = try environmentService.uninstallJavaWithSDKMAN(identifier: identifier, progress: progress)
    }

    func setDefaultJava(version: String, homePath: String) throws {
        _ = try environmentService.selectDefaultJava(version: version, homePath: homePath)
    }

    func setSelectedProfile(id: UUID) throws {
        _ = try environmentService.updateSelectedProfile(id)
    }

    func saveProfile(_ profile: EnvironmentProfile) throws {
        var settings = try configStore.load()
        if let index = settings.profiles.firstIndex(where: { $0.id == profile.id }) {
            settings.profiles[index] = profile
        } else {
            settings.profiles.append(profile)
        }
        if settings.selectedProfileID == nil {
            settings.selectedProfileID = profile.id
        }
        try configStore.save(settings)
    }

    func createProfile(named name: String) throws -> UUID {
        var settings = try configStore.load()
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = normalized.isEmpty ? "新配置" : normalized
        let uniqueName = uniqueProfileName(base: base, existing: settings.profiles.map(\.name))
        let profile = EnvironmentProfile(name: uniqueName)
        settings.profiles.append(profile)
        settings.selectedProfileID = profile.id
        try configStore.save(settings)
        return profile.id
    }

    func setProjectVersionPreference(_ preference: ProjectVersionPreference) throws {
        var settings = try configStore.load()
        settings.projectVersionPreference = preference
        try configStore.save(settings)
    }

    private func uniqueProfileName(base: String, existing: [String]) -> String {
        let existingLowercased = Set(existing.map { $0.lowercased() })
        if !existingLowercased.contains(base.lowercased()) {
            return base
        }

        var suffix = 2
        while true {
            let candidate = "\(base) \(suffix)"
            if !existingLowercased.contains(candidate.lowercased()) {
                return candidate
            }
            suffix += 1
        }
    }
}
