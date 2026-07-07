import Foundation

public protocol AppSettingsStoring: Sendable {
    func load() throws -> AppSettings
    func save(_ settings: AppSettings) throws
}

extension ConfigStore: AppSettingsStoring {}

public final class NodeEnvironmentService: Sendable {
    private let configStore: any AppSettingsStoring
    private let detector: any NodeInstallationDetecting
    private let javaDetector: any JavaRuntimeDetecting
    private let componentInstaller: any RuntimeComponentInstalling
    private let shellRunner: any ShellCommandRunning

    public init(
        configStore: any AppSettingsStoring = ConfigStore(),
        detector: (any NodeInstallationDetecting)? = nil,
        javaDetector: (any JavaRuntimeDetecting)? = nil,
        componentInstaller: (any RuntimeComponentInstalling)? = nil,
        shellRunner: any ShellCommandRunning = ShellCommandRunner()
    ) {
        self.configStore = configStore
        self.shellRunner = shellRunner
        self.detector = detector ?? NodeInstallationDetector(shellRunner: shellRunner)
        self.javaDetector = javaDetector ?? JavaRuntimeDetector(shellRunner: shellRunner)
        self.componentInstaller = componentInstaller ?? RuntimeComponentInstaller(shellRunner: shellRunner)
    }

    public func loadSnapshot() throws -> NodeRuntimeSnapshot {
        try loadSnapshot(progress: nil)
    }

    public func loadSnapshot(progress: (@Sendable (String) -> Void)?) throws -> NodeRuntimeSnapshot {
        var settings = try configStore.load()
        let detectedActiveVersion = detector.detectActiveVersion()
        let detectedActiveNodePath = detector.detectActiveNodePath()
        let activeNodePath = managedActiveNodePath(detectedActiveNodePath)
        let activeVersion = activeNodePath == nil ? nil : detectedActiveVersion
        let installations = mergeDuplicateNodeVersions(
            installations: mergeDefaultSelection(
                installations: managedNodeInstallations(from: detector.detectInstallations()),
                selectedVersion: settings.selectedVersion,
                selectedNodePath: settings.selectedNodePath
            ),
            selectedNodePath: settings.selectedNodePath,
            activeNodePath: activeNodePath
        )
        let detectedActiveJavaHome = javaDetector.detectActiveJavaHome()
        let activeJavaHome = managedActiveJavaHome(detectedActiveJavaHome)
        let detectedActiveJavaVersion = javaDetector.detectActiveVersion()
        let activeJavaVersion = activeJavaHome == nil ? nil : detectedActiveJavaVersion
        let javaInstallations = mergeDefaultJavaSelection(
            installations: managedJavaInstallations(from: javaDetector.detectInstallations()),
            selectedJavaHome: settings.selectedJavaHome
        )
        if settings.cachedNodeInstallations != installations || settings.cachedJavaInstallations != javaInstallations {
            settings.cachedNodeInstallations = installations
            settings.cachedJavaInstallations = javaInstallations
            try configStore.save(settings)
        }

        return NodeRuntimeSnapshot(
            installations: installations,
            activeVersion: activeVersion,
            activeNodePath: activeNodePath,
            javaInstallations: javaInstallations,
            activeJavaVersion: activeJavaVersion,
            activeJavaHome: activeJavaHome,
            settings: settings
        )
    }

    @discardableResult
    public func selectDefaultNode(version: String) throws -> NodeRuntimeSnapshot {
        try selectDefaultNode(version: version, progress: nil)
    }

    @discardableResult
    public func selectDefaultNode(version: String, progress: (@Sendable (String) -> Void)?) throws -> NodeRuntimeSnapshot {
        let normalizedVersion = try normalizeOrThrow(version)
        let installations = managedNodeInstallations(from: detector.detectInstallations())
        guard let selectedInstallation = installations.first(where: { $0.version == normalizedVersion }) else {
            throw NodeEnvironmentServiceError.nodeVersionNotInstalled(normalizedVersion)
        }

        var settings = try configStore.load()
        settings.selectedVersion = normalizedVersion
        settings.selectedNodePath = selectedInstallation.installPath
        try configStore.save(settings)

        return try loadSnapshot(progress: progress)
    }

    @discardableResult
    public func installNode(version: String) throws -> NodeRuntimeSnapshot {
        try installNode(version: version, progress: nil)
    }

    @discardableResult
    public func installNode(version: String, progress: (@Sendable (String) -> Void)?) throws -> NodeRuntimeSnapshot {
        let installation = try componentInstaller.installNode(version: version, progress: progress)

        var settings = try configStore.load()
        settings.selectedVersion = installation.version
        settings.selectedNodePath = installation.installPath
        try configStore.save(settings)

        return try loadSnapshot(progress: progress)
    }

    @discardableResult
    public func uninstallNode(version: String) throws -> NodeRuntimeSnapshot {
        try uninstallNode(version: version, progress: nil)
    }

    @discardableResult
    public func uninstallNode(version: String, progress: (@Sendable (String) -> Void)?) throws -> NodeRuntimeSnapshot {
        let normalizedVersion = try normalizeOrThrow(version)
        let installations = managedNodeInstallations(from: detector.detectInstallations()).filter { $0.version == normalizedVersion }
        guard let selectedInstallation = installations.first else {
            throw NodeEnvironmentServiceError.nodeVersionNotInstalled(normalizedVersion)
        }

        progress?("正在卸载 ENVPilot Node \(normalizedVersion)...")
        try componentInstaller.uninstallManagedNode(installation: selectedInstallation)

        var settings = try configStore.load()
        if settings.selectedVersion == normalizedVersion || settings.selectedNodePath == selectedInstallation.installPath {
            settings.selectedVersion = nil
            settings.selectedNodePath = nil
        }
        try configStore.save(settings)

        return try loadSnapshot(progress: progress)
    }

    @discardableResult
    public func updateSelectedProfile(_ profileID: UUID?) throws -> NodeRuntimeSnapshot {
        var settings = try configStore.load()
        settings.selectedProfileID = profileID
        try configStore.save(settings)
        return try loadSnapshot()
    }

    @discardableResult
    public func selectDefaultJava(version: String, homePath: String) throws -> NodeRuntimeSnapshot {
        let installations = managedJavaInstallations(from: javaDetector.detectInstallations())
        guard installations.contains(where: { $0.homePath == homePath }) else {
            throw NodeEnvironmentServiceError.javaHomeNotInstalled(homePath)
        }

        var settings = try configStore.load()
        settings.selectedJavaVersion = version
        settings.selectedJavaHome = homePath
        try configStore.save(settings)
        return try loadSnapshot()
    }

    public func listAvailableNodeVersions(ltsOnly: Bool = false) throws -> [NodeDownloadCandidate] {
        try componentInstaller.listAvailableNodeVersions(ltsOnly: ltsOnly)
    }

    public func listAvailableJavaVersions(ltsOnly: Bool = false) throws -> [JavaDownloadCandidate] {
        try componentInstaller.listAvailableJavaVersions(ltsOnly: ltsOnly)
    }

    @discardableResult
    public func installJava(featureVersion: Int, progress: (@Sendable (String) -> Void)?) throws -> NodeRuntimeSnapshot {
        let installation = try componentInstaller.installJava(featureVersion: featureVersion, progress: progress)
        var settings = try configStore.load()
        settings.selectedJavaVersion = installation.version
        settings.selectedJavaHome = installation.homePath
        try configStore.save(settings)
        return try loadSnapshot(progress: progress)
    }

    @discardableResult
    public func uninstallJava(
        homePath: String,
        progress: (@Sendable (String) -> Void)?
    ) throws -> NodeRuntimeSnapshot {
        let normalizedHomePath = homePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedHomePath.isEmpty else {
            throw NodeEnvironmentServiceError.javaHomeNotInstalled(homePath)
        }

        let installations = managedJavaInstallations(from: javaDetector.detectInstallations())
        guard installations.contains(where: { $0.homePath == normalizedHomePath }) else {
            throw NodeEnvironmentServiceError.javaHomeNotInstalled(normalizedHomePath)
        }

        progress?("正在卸载 JDK \(normalizedHomePath)...")
        do {
            try componentInstaller.uninstallManagedJava(homePath: normalizedHomePath)
        } catch let error as NodeEnvironmentServiceError {
            throw error
        } catch {
            throw NodeEnvironmentServiceError.javaUninstallFailed(
                path: normalizedHomePath,
                message: error.localizedDescription
            )
        }

        var settings = try configStore.load()
        if settings.selectedJavaHome == normalizedHomePath {
            settings.selectedJavaHome = nil
            settings.selectedJavaVersion = nil
            try configStore.save(settings)
        }

        return try loadSnapshot(progress: progress)
    }

    func normalizeOrThrow(_ version: String) throws -> String {
        if let normalized = NodeInstallationDetector.normalizeVersion(version) {
            return normalized
        }
        throw NodeEnvironmentServiceError.invalidVersion(version)
    }

    func managedNodeInstallations(from installations: [NodeInstallation]) -> [NodeInstallation] {
        installations.filter { RuntimeComponentInstaller.isManagedNodePath($0.installPath) }
    }

    func managedJavaInstallations(from installations: [JavaInstallation]) -> [JavaInstallation] {
        installations.filter { RuntimeComponentInstaller.isManagedJavaHomePath($0.homePath) }
    }

    func managedActiveNodePath(_ path: String?) -> String? {
        guard let path, !path.isEmpty else {
            return nil
        }
        let nodeHomePath = nodeHomePath(fromExecutablePath: standardizedPath(path))
        return RuntimeComponentInstaller.isManagedNodePath(nodeHomePath) ? path : nil
    }

    func managedActiveJavaHome(_ homePath: String?) -> String? {
        guard let homePath, !homePath.isEmpty else {
            return nil
        }
        return RuntimeComponentInstaller.isManagedJavaHomePath(homePath) ? homePath : nil
    }

    func mergeDefaultSelection(
        installations: [NodeInstallation],
        selectedVersion: String?,
        selectedNodePath: String?
    ) -> [NodeInstallation] {
        let normalizedSelection = NodeInstallationDetector.normalizeVersion(selectedVersion)
        let normalizedSelectedNodePath = selectedNodePath.map(standardizedPath)

        return installations.map { installation in
            let normalizedInstallPath = standardizedPath(installation.installPath)
            let isSelected = normalizedSelectedNodePath.map { $0 == normalizedInstallPath }
                ?? (installation.version == normalizedSelection)
            if isSelected && !installation.isDefault {
                return NodeInstallation(
                    version: installation.version,
                    installPath: installation.installPath,
                    executablePath: installation.executablePath,
                    isDefault: true
                )
            }
            return installation
        }
    }

    func mergeDuplicateNodeVersions(
        installations: [NodeInstallation],
        selectedNodePath: String?,
        activeNodePath: String?
    ) -> [NodeInstallation] {
        let normalizedSelectedNodePath = selectedNodePath.map(standardizedPath)
        let normalizedActiveNodePath = activeNodePath.map(standardizedPath)
        let normalizedActiveNodeHome = normalizedActiveNodePath.map { nodeHomePath(fromExecutablePath: $0) }
        var installationsByVersion: [String: NodeInstallation] = [:]

        for installation in installations {
            guard let current = installationsByVersion[installation.version] else {
                installationsByVersion[installation.version] = installation
                continue
            }

            if shouldPreferNodeInstallation(
                installation,
                over: current,
                selectedNodePath: normalizedSelectedNodePath,
                activeNodePath: normalizedActiveNodePath,
                activeNodeHome: normalizedActiveNodeHome
            ) {
                installationsByVersion[installation.version] = installation
            }
        }

        return installationsByVersion.values.sorted(by: sortNodeInstallations(_:_:))
    }

    func shouldPreferNodeInstallation(
        _ candidate: NodeInstallation,
        over current: NodeInstallation,
        selectedNodePath: String?,
        activeNodePath: String?,
        activeNodeHome: String?
    ) -> Bool {
        let candidateScore = nodeInstallationPreferenceScore(
            candidate,
            selectedNodePath: selectedNodePath,
            activeNodePath: activeNodePath,
            activeNodeHome: activeNodeHome
        )
        let currentScore = nodeInstallationPreferenceScore(
            current,
            selectedNodePath: selectedNodePath,
            activeNodePath: activeNodePath,
            activeNodeHome: activeNodeHome
        )

        if candidateScore != currentScore {
            return candidateScore > currentScore
        }

        return candidate.installPath < current.installPath
    }

    func nodeInstallationPreferenceScore(
        _ installation: NodeInstallation,
        selectedNodePath: String?,
        activeNodePath: String?,
        activeNodeHome: String?
    ) -> Int {
        let installPath = standardizedPath(installation.installPath)
        let executablePath = standardizedPath(installation.executablePath)
        var score = 0

        // Precedence is selected path, active shell path, then detector default.
        if selectedNodePath == installPath {
            score += 400
        }
        if activeNodePath == executablePath || activeNodeHome == installPath {
            score += 300
        }
        if installation.isDefault {
            score += 200
        }

        return score
    }

    func sortNodeInstallations(_ lhs: NodeInstallation, _ rhs: NodeInstallation) -> Bool {
        if lhs.version == rhs.version {
            return lhs.installPath < rhs.installPath
        }
        return NodeInstallationDetector.isVersionGreater(lhs.version, rhs.version)
    }

    func standardizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
    }

    func nodeHomePath(fromExecutablePath executablePath: String) -> String {
        URL(fileURLWithPath: executablePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .standardizedFileURL
            .path
    }

    func mergeDefaultJavaSelection(
        installations: [JavaInstallation],
        selectedJavaHome: String?
    ) -> [JavaInstallation] {
        guard let selectedJavaHome, !selectedJavaHome.isEmpty else {
            return installations
        }
        return installations.map {
            JavaInstallation(version: $0.version, homePath: $0.homePath, isDefault: $0.homePath == selectedJavaHome)
        }
    }

}

public enum NodeEnvironmentServiceError: Error, LocalizedError {
    case invalidVersion(String)
    case nodeVersionNotInstalled(String)
    case javaHomeNotInstalled(String)
    case javaUninstallFailed(path: String, message: String)

    public var errorDescription: String? {
        switch self {
        case .invalidVersion(let version):
            return "Invalid Node version: \(version)"
        case .nodeVersionNotInstalled(let version):
            return "Node \(version) is not detected as a local runtime."
        case .javaHomeNotInstalled(let homePath):
            return "JDK home is not installed: \(homePath)"
        case .javaUninstallFailed(let path, let message):
            return "Failed to uninstall JDK at \(path): \(message)"
        }
    }
}
