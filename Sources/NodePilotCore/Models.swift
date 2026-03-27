import Foundation

public struct NodeInstallation: Identifiable, Codable, Hashable, Sendable {
    public let version: String
    public let installPath: String
    public let executablePath: String
    public let isDefault: Bool

    public init(version: String, installPath: String, executablePath: String, isDefault: Bool = false) {
        self.version = version
        self.installPath = installPath
        self.executablePath = executablePath
        self.isDefault = isDefault
    }

    public var id: String {
        executablePath
    }
}

public struct JavaInstallation: Identifiable, Codable, Hashable, Sendable {
    public let version: String
    public let homePath: String
    public let isDefault: Bool

    public init(version: String, homePath: String, isDefault: Bool = false) {
        self.version = version
        self.homePath = homePath
        self.isDefault = isDefault
    }

    public var id: String {
        homePath
    }
}

public struct CustomEnvironmentVariable: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var key: String
    public var value: String

    public init(id: UUID = UUID(), key: String, value: String) {
        self.id = id
        self.key = key
        self.value = value
    }
}

public struct EnvironmentProfile: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var npmRegistry: String
    public var pnpmRegistry: String
    public var yarnRegistry: String
    public var nodeOptions: String
    public var variables: [CustomEnvironmentVariable]

    public init(
        id: UUID = UUID(),
        name: String,
        npmRegistry: String = "",
        pnpmRegistry: String = "",
        yarnRegistry: String = "",
        nodeOptions: String = "",
        variables: [CustomEnvironmentVariable] = []
    ) {
        self.id = id
        self.name = name
        self.npmRegistry = npmRegistry
        self.pnpmRegistry = pnpmRegistry
        self.yarnRegistry = yarnRegistry
        self.nodeOptions = nodeOptions
        self.variables = variables
    }
}

public enum ProjectVersionPreference: String, Codable, CaseIterable, Sendable {
    case globalDefault
    case followProjectFiles
}

public struct AppSettings: Codable, Sendable {
    public var selectedVersion: String?
    public var selectedJavaVersion: String?
    public var selectedJavaHome: String?
    public var selectedProfileID: UUID?
    public var projectVersionPreference: ProjectVersionPreference
    public var profiles: [EnvironmentProfile]

    public init(
        selectedVersion: String? = nil,
        selectedJavaVersion: String? = nil,
        selectedJavaHome: String? = nil,
        selectedProfileID: UUID? = nil,
        projectVersionPreference: ProjectVersionPreference = .followProjectFiles,
        profiles: [EnvironmentProfile] = AppSettings.defaultProfiles
    ) {
        self.selectedVersion = selectedVersion
        self.selectedJavaVersion = selectedJavaVersion
        self.selectedJavaHome = selectedJavaHome
        self.selectedProfileID = selectedProfileID
        self.projectVersionPreference = projectVersionPreference
        self.profiles = profiles
    }

    public static let defaultProfiles: [EnvironmentProfile] = [
        EnvironmentProfile(name: "默认"),
    ]
}

public struct NodeRuntimeSnapshot: Sendable {
    public var installations: [NodeInstallation]
    public var activeVersion: String?
    public var activeNodePath: String?
    public var javaInstallations: [JavaInstallation]
    public var activeJavaVersion: String?
    public var activeJavaHome: String?
    public var settings: AppSettings

    public init(
        installations: [NodeInstallation],
        activeVersion: String?,
        activeNodePath: String? = nil,
        javaInstallations: [JavaInstallation] = [],
        activeJavaVersion: String? = nil,
        activeJavaHome: String? = nil,
        settings: AppSettings
    ) {
        self.installations = installations
        self.activeVersion = activeVersion
        self.activeNodePath = activeNodePath
        self.javaInstallations = javaInstallations
        self.activeJavaVersion = activeJavaVersion
        self.activeJavaHome = activeJavaHome
        self.settings = settings
    }
}
