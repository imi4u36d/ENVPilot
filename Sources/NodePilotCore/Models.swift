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

public struct PythonInstallation: Identifiable, Codable, Hashable, Sendable {
    public let version: String
    public let homePath: String
    public let executablePath: String
    public let isDefault: Bool

    public init(version: String, homePath: String, executablePath: String, isDefault: Bool = false) {
        self.version = version
        self.homePath = homePath
        self.executablePath = executablePath
        self.isDefault = isDefault
    }

    public var id: String {
        executablePath
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

public struct PythonDownloadCandidate: Identifiable, Codable, Hashable, Sendable {
    public let version: String
    public let packageName: String
    public let downloadURL: String

    public init(version: String, packageName: String, downloadURL: String) {
        self.version = version
        self.packageName = packageName
        self.downloadURL = downloadURL
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

/// 终端要用的运行时版本只来自这里（全局选择）。
///
/// 旧版本在这里还有 `selectedProfileID` / `profiles`（环境预设）与
/// `projectVersionPreference`（项目 `.envpilot` 文件优先）三个字段。整条「项目与预设」
/// 链路已经删除：磁盘上的 settings.json 里可能仍留着这些键，`Codable` 合成的解码器会
/// 忽略未知键，因此老配置照样能读，下一次保存就把它们清掉了。
public struct AppSettings: Codable, Sendable {
    public var selectedVersion: String?
    public var selectedNodePath: String?
    public var selectedJavaVersion: String?
    public var selectedJavaHome: String?
    public var selectedPythonVersion: String?
    public var selectedPythonHome: String?
    public var cachedNodeInstallations: [NodeInstallation]?
    public var cachedJavaInstallations: [JavaInstallation]?
    public var cachedPythonInstallations: [PythonInstallation]?

    public init(
        selectedVersion: String? = nil,
        selectedNodePath: String? = nil,
        selectedJavaVersion: String? = nil,
        selectedJavaHome: String? = nil,
        selectedPythonVersion: String? = nil,
        selectedPythonHome: String? = nil,
        cachedNodeInstallations: [NodeInstallation]? = nil,
        cachedJavaInstallations: [JavaInstallation]? = nil,
        cachedPythonInstallations: [PythonInstallation]? = nil
    ) {
        self.selectedVersion = selectedVersion
        self.selectedNodePath = selectedNodePath
        self.selectedJavaVersion = selectedJavaVersion
        self.selectedJavaHome = selectedJavaHome
        self.selectedPythonVersion = selectedPythonVersion
        self.selectedPythonHome = selectedPythonHome
        self.cachedNodeInstallations = cachedNodeInstallations
        self.cachedJavaInstallations = cachedJavaInstallations
        self.cachedPythonInstallations = cachedPythonInstallations
    }
}

public struct NodeRuntimeSnapshot: Sendable {
    public var installations: [NodeInstallation]
    public var activeVersion: String?
    public var activeNodePath: String?
    public var javaInstallations: [JavaInstallation]
    public var activeJavaVersion: String?
    public var activeJavaHome: String?
    public var pythonInstallations: [PythonInstallation]
    public var activePythonVersion: String?
    public var activePythonHome: String?
    public var settings: AppSettings

    public init(
        installations: [NodeInstallation],
        activeVersion: String?,
        activeNodePath: String? = nil,
        javaInstallations: [JavaInstallation] = [],
        activeJavaVersion: String? = nil,
        activeJavaHome: String? = nil,
        pythonInstallations: [PythonInstallation] = [],
        activePythonVersion: String? = nil,
        activePythonHome: String? = nil,
        settings: AppSettings
    ) {
        self.installations = installations
        self.activeVersion = activeVersion
        self.activeNodePath = activeNodePath
        self.javaInstallations = javaInstallations
        self.activeJavaVersion = activeJavaVersion
        self.activeJavaHome = activeJavaHome
        self.pythonInstallations = pythonInstallations
        self.activePythonVersion = activePythonVersion
        self.activePythonHome = activePythonHome
        self.settings = settings
    }
}
