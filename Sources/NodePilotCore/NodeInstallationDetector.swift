import Foundation

public protocol NodeInstallationDetecting: Sendable {
    func detectInstallations() -> [NodeInstallation]
    func detectActiveVersion() -> String?
    func detectActiveNodePath() -> String?
}

public struct NodeInstallationDetector: NodeInstallationDetecting, Sendable {
    private let shellRunner: any ShellCommandRunning

    public init(shellRunner: any ShellCommandRunning = ShellCommandRunner()) {
        self.shellRunner = shellRunner
    }

    public func detectInstallations() -> [NodeInstallation] {
        let fileManager = FileManager.default
        let defaultVersion = detectDefaultVersion()
        var executablePaths = Set<String>()

        if let nvmDirectory = resolvedNVMDirectory() {
            let versionsRoot = nvmDirectory.appendingPathComponent("versions/node", isDirectory: true)
            if let entries = try? fileManager.contentsOfDirectory(
                at: versionsRoot,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) {
                for versionDirectory in entries {
                    executablePaths.insert(versionDirectory.appendingPathComponent("bin/node").path)
                }
            }
        }

        executablePaths.formUnion(directNodeExecutableCandidates(fileManager: fileManager))

        var installationsByExecutablePath: [String: NodeInstallation] = [:]
        for executablePath in executablePaths {
            guard let installation = installationFromNodeExecutable(
                executablePath,
                defaultVersion: defaultVersion,
                fileManager: fileManager
            ) else {
                continue
            }
            installationsByExecutablePath[installation.executablePath] = installation
        }

        return installationsByExecutablePath.values.sorted(by: sortInstallation(_:_:))
    }

    public func detectActiveVersion() -> String? {
        Self.normalizeVersion(runShellOutput("node -v"))
    }

    public func detectActiveNodePath() -> String? {
        let output = runShellOutput("node_bin=$(command -v node); [ -n \"$node_bin\" ] && (realpath \"$node_bin\" 2>/dev/null || readlink \"$node_bin\" 2>/dev/null || echo \"$node_bin\")")
        let path = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : path
    }

    public func detectDefaultVersion() -> String? {
        nil
    }

    func resolvedNVMDirectory() -> URL? {
        let fileManager = FileManager.default
        let basePath = (ProcessInfo.processInfo.environment["NVM_DIR"] ?? "~/.nvm") as NSString
        let expanded = basePath.expandingTildeInPath
        let url = URL(fileURLWithPath: expanded, isDirectory: true)
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }

    func runShellOutput(_ command: String) -> String {
        let wrappedCommand = """
        export ENVPILOT_ACTIVATING=1
        if [ -f "$HOME/.zshrc" ]; then
          . "$HOME/.zshrc" >/dev/null 2>&1 || true
        fi
        \(command)
        """

        guard let result = try? shellRunner.runShell(wrappedCommand, environment: ProcessInfo.processInfo.environment) else {
            return ""
        }
        if !result.standardOutput.isEmpty {
            return result.standardOutput
        }
        return result.standardError
    }

    func versionFromNodeBinary(_ executablePath: String) -> String? {
        let output = runShellOutput("\(Self.singleQuoted(executablePath)) -v")
        return Self.normalizeVersion(output)
    }

    func directNodeExecutableCandidates(fileManager: FileManager) -> Set<String> {
        var candidates = Set<String>()
        if let activeNodePath = detectActiveNodePath() {
            candidates.insert(activeNodePath)
        }

        for prefix in ["/opt/homebrew", "/usr/local", "/usr"] {
            candidates.insert("\(prefix)/bin/node")
        }

        for optRoot in ["/opt/homebrew/opt", "/usr/local/opt"] {
            candidates.formUnion(nodeExecutablesInOptRoot(optRoot, fileManager: fileManager))
        }

        for cellarRoot in ["/opt/homebrew/Cellar", "/usr/local/Cellar"] {
            candidates.formUnion(nodeExecutablesInCellarRoot(cellarRoot, fileManager: fileManager))
        }

        for userRoot in [
            "~/.envpilot/runtimes/node",
            "~/.envpilot/node",
            "~/.local/share/envpilot/node",
            "~/.local/node",
        ] {
            candidates.formUnion(nodeExecutablesInVersionedRoot(userRoot, fileManager: fileManager))
        }

        return candidates
    }

    func nodeExecutablesInOptRoot(_ root: String, fileManager: FileManager) -> Set<String> {
        guard let entries = try? fileManager.contentsOfDirectory(atPath: root) else {
            return []
        }
        return Set(entries.filter { $0 == "node" || $0.hasPrefix("node@") }.map { "\(root)/\($0)/bin/node" })
    }

    func nodeExecutablesInCellarRoot(_ root: String, fileManager: FileManager) -> Set<String> {
        var candidates = Set<String>()
        guard let formulaDirs = try? fileManager.contentsOfDirectory(atPath: root) else {
            return candidates
        }

        for formula in formulaDirs where formula == "node" || formula.hasPrefix("node@") {
            let formulaPath = "\(root)/\(formula)"
            guard let versions = try? fileManager.contentsOfDirectory(atPath: formulaPath) else {
                continue
            }
            for version in versions {
                candidates.insert("\(formulaPath)/\(version)/bin/node")
            }
        }
        return candidates
    }

    func nodeExecutablesInVersionedRoot(_ root: String, fileManager: FileManager) -> Set<String> {
        let expandedRoot = (root as NSString).expandingTildeInPath
        var candidates: Set<String> = ["\(expandedRoot)/bin/node"]
        guard let entries = try? fileManager.contentsOfDirectory(atPath: expandedRoot) else {
            return candidates
        }
        for entry in entries where !entry.hasPrefix(".") {
            candidates.insert("\(expandedRoot)/\(entry)/bin/node")
        }
        return candidates
    }

    func installationFromNodeExecutable(
        _ executablePath: String,
        defaultVersion: String?,
        fileManager: FileManager
    ) -> NodeInstallation? {
        let standardizedExecutablePath = URL(fileURLWithPath: executablePath)
            .resolvingSymlinksInPath()
            .standardizedFileURL
            .path
        guard fileManager.isExecutableFile(atPath: standardizedExecutablePath) else {
            return nil
        }
        guard let version = versionFromNodeBinary(standardizedExecutablePath) else {
            return nil
        }
        let installPath = URL(fileURLWithPath: standardizedExecutablePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .standardizedFileURL
            .path
        return NodeInstallation(
            version: version,
            installPath: installPath,
            executablePath: standardizedExecutablePath,
            isDefault: version == defaultVersion
        )
    }

    func sortInstallation(_ lhs: NodeInstallation, _ rhs: NodeInstallation) -> Bool {
        if lhs.version == rhs.version {
            return lhs.installPath < rhs.installPath
        }
        return Self.isVersionGreater(lhs.version, rhs.version)
    }

    public static func normalizeVersion(_ raw: String?) -> String? {
        guard let raw else {
            return nil
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        let regex = try? NSRegularExpression(pattern: #"\bv?(\d+\.\d+\.\d+)\b"#, options: [])
        let nsRange = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
        guard
            let match = regex?.firstMatch(in: trimmed, options: [], range: nsRange),
            match.numberOfRanges >= 2,
            let range = Range(match.range(at: 1), in: trimmed)
        else {
            return nil
        }
        return String(trimmed[range])
    }

    public static func isVersionGreater(_ lhs: String, _ rhs: String) -> Bool {
        let left = lhs.split(separator: ".").compactMap { Int($0) }
        let right = rhs.split(separator: ".").compactMap { Int($0) }

        for index in 0..<max(left.count, right.count) {
            let l = index < left.count ? left[index] : 0
            let r = index < right.count ? right[index] : 0
            if l != r {
                return l > r
            }
        }
        return false
    }

    public static func singleQuoted(_ value: String) -> String {
        ShellSyntax.singleQuoted(value)
    }
}
