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

public struct NodeDownloadCandidate: Identifiable, Codable, Hashable, Sendable {
    public let version: String
    public let lts: String?

    public init(version: String, lts: String? = nil) {
        self.version = version
        self.lts = lts
    }

    public var id: String {
        version
    }
}

public struct JavaDownloadCandidate: Identifiable, Codable, Hashable, Sendable {
    public let featureVersion: Int
    public let version: String
    public let vendor: String
    public let packageName: String
    public let downloadURL: String
    public let checksum: String?

    public init(
        featureVersion: Int,
        version: String,
        vendor: String,
        packageName: String,
        downloadURL: String,
        checksum: String? = nil
    ) {
        self.featureVersion = featureVersion
        self.version = version
        self.vendor = vendor
        self.packageName = packageName
        self.downloadURL = downloadURL
        self.checksum = checksum
    }

    public var id: String {
        "\(vendor)-\(featureVersion)-\(version)"
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
    public var selectedNodePath: String?
    public var selectedJavaVersion: String?
    public var selectedJavaHome: String?
    public var selectedProfileID: UUID?
    public var projectVersionPreference: ProjectVersionPreference
    public var profiles: [EnvironmentProfile]
    public var cachedNodeInstallations: [NodeInstallation]?
    public var cachedJavaInstallations: [JavaInstallation]?

    public init(
        selectedVersion: String? = nil,
        selectedNodePath: String? = nil,
        selectedJavaVersion: String? = nil,
        selectedJavaHome: String? = nil,
        selectedProfileID: UUID? = nil,
        projectVersionPreference: ProjectVersionPreference = .followProjectFiles,
        profiles: [EnvironmentProfile] = AppSettings.defaultProfiles,
        cachedNodeInstallations: [NodeInstallation]? = nil,
        cachedJavaInstallations: [JavaInstallation]? = nil
    ) {
        self.selectedVersion = selectedVersion
        self.selectedNodePath = selectedNodePath
        self.selectedJavaVersion = selectedJavaVersion
        self.selectedJavaHome = selectedJavaHome
        self.selectedProfileID = selectedProfileID
        self.projectVersionPreference = projectVersionPreference
        self.profiles = profiles
        self.cachedNodeInstallations = cachedNodeInstallations
        self.cachedJavaInstallations = cachedJavaInstallations
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
