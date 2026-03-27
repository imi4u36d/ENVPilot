import Foundation
import ENVPilotCore

protocol NodeRuntimeServicing: Sendable {
    func loadSnapshot() throws -> NodeRuntimeSnapshot
    func setDefaultNode(version: String) throws
    func installNode(version: String) throws
    func uninstallNode(version: String) throws
    func setDefaultJava(version: String, homePath: String) throws
    func setSelectedProfile(id: UUID) throws
    func installComponent(_ component: InstallableComponent) throws
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

    func loadSnapshot() throws -> NodeRuntimeSnapshot {
        try environmentService.loadSnapshot()
    }

    func setDefaultNode(version: String) throws {
        _ = try environmentService.selectDefaultNode(version: version)
    }

    func installNode(version: String) throws {
        _ = try environmentService.installNode(version: version)
    }

    func uninstallNode(version: String) throws {
        _ = try environmentService.uninstallNode(version: version)
    }

    func setDefaultJava(version: String, homePath: String) throws {
        _ = try environmentService.selectDefaultJava(version: version, homePath: homePath)
    }

    func setSelectedProfile(id: UUID) throws {
        _ = try environmentService.updateSelectedProfile(id)
    }

    func installComponent(_ component: InstallableComponent) throws {
        _ = try environmentService.installComponent(component)
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
