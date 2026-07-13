import Foundation

public protocol PythonRuntimeDetecting: Sendable {
    func detectInstallations() -> [PythonInstallation]
    func detectActiveVersion() -> String?
    func detectActivePythonHome() -> String?
}

public struct PythonRuntimeDetector: PythonRuntimeDetecting, Sendable {
    private let shellRunner: any ShellCommandRunning
    private let environment: [String: String]

    public init(
        shellRunner: any ShellCommandRunning = ShellCommandRunner(),
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.shellRunner = shellRunner
        self.environment = environment
    }

    public func detectInstallations() -> [PythonInstallation] {
        let defaultHome = detectActivePythonHome().map(canonicalPath)
        let fileManager = FileManager.default
        var installations: [PythonInstallation] = []

        guard let entries = try? fileManager.contentsOfDirectory(
            at: RuntimeComponentInstaller.managedPythonRoot(),
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        for entry in entries {
            guard let installation = installationFromPythonHome(entry.path, defaultHome: defaultHome) else {
                continue
            }
            installations.append(installation)
        }

        return installations.sorted(by: sortPythonInstallation(_:_:))
    }

    public func detectActiveVersion() -> String? {
        if let home = detectActivePythonHome(),
           let version = versionFromPythonBinary(homePath: home) {
            return version
        }
        return Self.normalizeVersion(runShellOutput("python3 --version 2>&1"))
    }

    public func detectActivePythonHome() -> String? {
        let output = runShellOutput("python_bin=$(command -v python3); [ -n \"$python_bin\" ] && (realpath \"$python_bin\" 2>/dev/null || readlink \"$python_bin\" 2>/dev/null || echo \"$python_bin\")")
        let executablePath = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !executablePath.isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: executablePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .standardizedFileURL
            .path
    }

    private func installationFromPythonHome(_ homePath: String, defaultHome: String?) -> PythonInstallation? {
        let canonicalHome = canonicalPath(homePath)
        let executablePath = "\(canonicalHome)/bin/python3"
        guard FileManager.default.isExecutableFile(atPath: executablePath) else {
            return nil
        }
        guard let version = versionFromPythonBinary(homePath: canonicalHome) else {
            return nil
        }
        return PythonInstallation(
            version: version,
            homePath: canonicalHome,
            executablePath: executablePath,
            isDefault: defaultHome == canonicalHome
        )
    }

    private func versionFromPythonBinary(homePath: String) -> String? {
        let pythonBin = "\(homePath)/bin/python3"
        guard FileManager.default.isExecutableFile(atPath: pythonBin) else {
            return nil
        }
        return Self.normalizeVersion(runShellOutput("\(ShellSyntax.singleQuoted(pythonBin)) --version 2>&1"))
    }

    private func runShellOutput(_ command: String) -> String {
        guard let result = try? shellRunner.runShell(command, environment: environment) else {
            return ""
        }
        if !result.standardOutput.isEmpty {
            return result.standardOutput
        }
        return result.standardError
    }

    private func canonicalPath(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
    }

    private func sortPythonInstallation(_ lhs: PythonInstallation, _ rhs: PythonInstallation) -> Bool {
        if lhs.version == rhs.version {
            return lhs.homePath < rhs.homePath
        }
        return Self.isPythonVersionGreater(lhs.version, rhs.version)
    }

    public static func normalizeVersion(_ raw: String?) -> String? {
        guard let raw else {
            return nil
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        let regex = try? NSRegularExpression(pattern: #"\bPython\s+(\d+\.\d+\.\d+)\b|\b(\d+\.\d+\.\d+)\b"#)
        let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
        guard let match = regex?.firstMatch(in: trimmed, range: range) else {
            return nil
        }
        for index in 1..<match.numberOfRanges {
            if let valueRange = Range(match.range(at: index), in: trimmed) {
                return String(trimmed[valueRange])
            }
        }
        return nil
    }

    public static func isPythonVersionGreater(_ lhs: String, _ rhs: String) -> Bool {
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

}
