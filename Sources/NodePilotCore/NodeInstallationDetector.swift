import Foundation

public protocol NodeInstallationDetecting: Sendable {
    func isNVMInstalled() -> Bool
    func detectInstallations() -> [NodeInstallation]
    func detectActiveVersion() -> String?
    func detectActiveNodePath() -> String?
}

public struct NodeInstallationDetector: NodeInstallationDetecting, Sendable {
    private let shellRunner: any ShellCommandRunning

    public init(shellRunner: any ShellCommandRunning = ShellCommandRunner()) {
        self.shellRunner = shellRunner
    }

    public func isNVMInstalled() -> Bool {
        nvmScriptPath() != nil
    }

    public func detectInstallations() -> [NodeInstallation] {
        guard let nvmDirectory = resolvedNVMDirectory() else {
            return []
        }
        let fileManager = FileManager.default

        let defaultVersion = detectDefaultVersion()
        let versionsRoot = nvmDirectory.appendingPathComponent("versions/node", isDirectory: true)
        guard let entries = try? fileManager.contentsOfDirectory(
            at: versionsRoot,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        let installations = entries.compactMap { versionDirectory -> NodeInstallation? in
            let executablePath = versionDirectory.appendingPathComponent("bin/node").path
            guard fileManager.isExecutableFile(atPath: executablePath) else {
                return nil
            }
            guard let version = versionFromNodeBinary(executablePath) else {
                return nil
            }
            return NodeInstallation(
                version: version,
                installPath: versionDirectory.path,
                executablePath: executablePath,
                isDefault: version == defaultVersion
            )
        }

        return installations.sorted(by: sortInstallation(_:_:))
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
        guard isNVMInstalled() else {
            return nil
        }
        return Self.normalizeVersion(runShellOutput(Self.nvmBootstrap("nvm alias default")))
    }

    func resolvedNVMDirectory() -> URL? {
        let fileManager = FileManager.default
        let basePath = (ProcessInfo.processInfo.environment["NVM_DIR"] ?? "~/.nvm") as NSString
        let expanded = basePath.expandingTildeInPath
        let url = URL(fileURLWithPath: expanded, isDirectory: true)
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }

    func nvmScriptPath() -> String? {
        let fileManager = FileManager.default
        for candidate in candidateNVMScriptPaths() where fileManager.isReadableFile(atPath: candidate) {
            return candidate
        }
        return nil
    }

    func candidateNVMScriptPaths() -> [String] {
        let nvmDirectory = ((ProcessInfo.processInfo.environment["NVM_DIR"] ?? "~/.nvm") as NSString)
            .expandingTildeInPath

        return [
            "\(nvmDirectory)/nvm.sh",
            "/opt/homebrew/opt/nvm/nvm.sh",
            "/usr/local/opt/nvm/nvm.sh",
        ]
    }

    func runShellOutput(_ command: String) -> String {
        let wrappedCommand = """
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

    func sortInstallation(_ lhs: NodeInstallation, _ rhs: NodeInstallation) -> Bool {
        if lhs.version == rhs.version {
            return lhs.installPath < rhs.installPath
        }
        return Self.isVersionGreater(lhs.version, rhs.version)
    }

    public static func nvmBootstrap(_ command: String) -> String {
        """
        if [ -f "$HOME/.zprofile" ]; then
          . "$HOME/.zprofile" >/dev/null 2>&1 || true;
        fi;
        if [ -f "$HOME/.zshrc" ]; then
          . "$HOME/.zshrc" >/dev/null 2>&1 || true;
        fi;
        export NVM_DIR="${NVM_DIR:-$HOME/.nvm}";
        mkdir -p "$NVM_DIR";
        if [ -s "$NVM_DIR/nvm.sh" ]; then
          . "$NVM_DIR/nvm.sh";
        elif [ -s "/opt/homebrew/opt/nvm/nvm.sh" ]; then
          . "/opt/homebrew/opt/nvm/nvm.sh";
        elif [ -s "/usr/local/opt/nvm/nvm.sh" ]; then
          . "/usr/local/opt/nvm/nvm.sh";
        fi;
        \(command)
        """
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
        "'\(value.replacingOccurrences(of: "'", with: "'\"'\"'"))'"
    }
}
