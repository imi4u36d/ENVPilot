import Foundation

public protocol RuntimeComponentInstalling: Sendable {
    func isHomebrewInstalled() -> Bool
    func installHomebrew() throws
    func canInstallNVM() -> Bool
    func installNVM() throws
    func isSDKMANInstalled() -> Bool
    func canInstallSDKMAN() -> Bool
    func installSDKMAN() throws
    func listAvailableJavaCandidatesWithSDKMAN() throws -> [SDKMANJavaCandidate]
    func installJavaWithSDKMAN(identifier: String) throws
    func uninstallJavaWithSDKMAN(identifier: String) throws
    func setSDKMANDefaultJava(identifier: String) throws
}

public struct RuntimeComponentInstaller: RuntimeComponentInstalling, Sendable {
    private let shellRunner: any ShellCommandRunning
    private let environment: [String: String]

    public init(
        shellRunner: any ShellCommandRunning = ShellCommandRunner(),
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.shellRunner = shellRunner
        self.environment = environment
    }

    public func isHomebrewInstalled() -> Bool {
        brewExecutablePath() != nil
    }

    public func installHomebrew() throws {
        let result = try shellRunner.runShell(
            Self.homebrewInstallCommand,
            environment: environment
        )
        guard result.succeeded else {
            throw RuntimeComponentInstallerError.homebrewInstallFailed(message: preferErrorOutput(result))
        }
    }

    public func canInstallNVM() -> Bool {
        brewExecutablePath() != nil
    }

    public func installNVM() throws {
        guard let brewPath = brewExecutablePath() else {
            throw RuntimeComponentInstallerError.homebrewUnavailable
        }

        let command = "mkdir -p \"$HOME/.nvm\"; \(Self.shellQuoted(brewPath)) list nvm >/dev/null 2>&1 || HOMEBREW_NO_AUTO_UPDATE=1 \(Self.shellQuoted(brewPath)) install nvm"
        let result = try shellRunner.runShell(command, environment: environment)
        guard result.succeeded else {
            throw RuntimeComponentInstallerError.nvmInstallFailed(message: preferErrorOutput(result))
        }
    }

    public func isSDKMANInstalled() -> Bool {
        let initScript = sdkmanInitScriptPath()
        return FileManager.default.isReadableFile(atPath: initScript)
    }

    public func canInstallSDKMAN() -> Bool {
        hasCommand("curl") && (modernBashExecutablePath() != nil || brewExecutablePath() != nil)
    }

    public func installSDKMAN() throws {
        if isSDKMANInstalled() {
            return
        }
        guard canInstallSDKMAN() else {
            throw RuntimeComponentInstallerError.sdkmanUnavailable
        }
        let bashPath = try ensureModernBashInstalled()
        let repairedBackupPath = try prepareBrokenSDKMANDirectoryForInstallIfNeeded()
        let result = try shellRunner.runShell(
            Self.sdkmanInstallCommand(bashPath: bashPath),
            environment: environment
        )
        guard result.succeeded else {
            throw RuntimeComponentInstallerError.sdkmanInstallFailed(message: preferErrorOutput(result))
        }
        guard isSDKMANInstalled() else {
            throw RuntimeComponentInstallerError.sdkmanInstallIncomplete(
                initScriptPath: sdkmanInitScriptPath(),
                repairedBackupPath: repairedBackupPath
            )
        }
    }

    public func listAvailableJavaCandidatesWithSDKMAN() throws -> [SDKMANJavaCandidate] {
        guard isSDKMANInstalled() else {
            throw RuntimeComponentInstallerError.sdkmanUnavailable
        }
        let command = Self.sdkmanBootstrap("sdk list java")
        let result = try shellRunner.runShell(command, environment: environment)
        guard result.succeeded else {
            throw RuntimeComponentInstallerError.sdkmanListJavaFailed(message: preferErrorOutput(result))
        }
        let output = [result.standardOutput, result.standardError]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        return Self.parseSDKMANJavaCandidates(from: output)
    }

    public func installJavaWithSDKMAN(identifier: String) throws {
        let normalizedIdentifier = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedIdentifier.isEmpty else {
            throw RuntimeComponentInstallerError.invalidSDKMANJavaIdentifier(identifier)
        }
        guard isSDKMANInstalled() else {
            throw RuntimeComponentInstallerError.sdkmanUnavailable
        }
        let command = Self.sdkmanBootstrap("sdk install java \(Self.shellQuoted(normalizedIdentifier)) -y")
        let result = try shellRunner.runShell(command, environment: environment)
        guard result.succeeded else {
            throw RuntimeComponentInstallerError.sdkmanJavaInstallFailed(
                identifier: normalizedIdentifier,
                message: preferErrorOutput(result)
            )
        }
    }

    public func uninstallJavaWithSDKMAN(identifier: String) throws {
        let normalizedIdentifier = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedIdentifier.isEmpty else {
            throw RuntimeComponentInstallerError.invalidSDKMANJavaIdentifier(identifier)
        }
        guard isSDKMANInstalled() else {
            throw RuntimeComponentInstallerError.sdkmanUnavailable
        }
        let command = Self.sdkmanBootstrap("sdk uninstall java \(Self.shellQuoted(normalizedIdentifier))")
        let result = try shellRunner.runShell(command, environment: environment)
        guard result.succeeded else {
            throw RuntimeComponentInstallerError.sdkmanJavaUninstallFailed(
                identifier: normalizedIdentifier,
                message: preferErrorOutput(result)
            )
        }
    }

    public func setSDKMANDefaultJava(identifier: String) throws {
        let normalizedIdentifier = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedIdentifier.isEmpty else {
            throw RuntimeComponentInstallerError.invalidSDKMANJavaIdentifier(identifier)
        }
        guard isSDKMANInstalled() else {
            throw RuntimeComponentInstallerError.sdkmanUnavailable
        }
        let command = Self.sdkmanBootstrap("sdk default java \(Self.shellQuoted(normalizedIdentifier))")
        let result = try shellRunner.runShell(command, environment: environment)
        guard result.succeeded else {
            throw RuntimeComponentInstallerError.sdkmanSetDefaultFailed(
                identifier: normalizedIdentifier,
                message: preferErrorOutput(result)
            )
        }
    }

    func brewExecutablePath() -> String? {
        let candidates = [
            runShellOutput("command -v brew"),
            "/opt/homebrew/bin/brew",
            "/usr/local/bin/brew",
        ]
        let fileManager = FileManager.default
        for candidate in candidates {
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                continue
            }
            if fileManager.isExecutableFile(atPath: trimmed) {
                return trimmed
            }
        }
        return nil
    }

    func runShellOutput(_ command: String) -> String {
        guard let result = try? shellRunner.runShell(command, environment: environment) else {
            return ""
        }
        if !result.standardOutput.isEmpty {
            return result.standardOutput
        }
        return result.standardError
    }

    func hasCommand(_ command: String) -> Bool {
        let output = runShellOutput("command -v \(command) 2>/dev/null")
        return !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func modernBashExecutablePath() -> String? {
        let candidates = [
            runShellOutput("command -v bash 2>/dev/null"),
            "/opt/homebrew/bin/bash",
            "/usr/local/bin/bash",
        ]

        for candidate in candidates {
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                continue
            }
            guard FileManager.default.isExecutableFile(atPath: trimmed) else {
                continue
            }
            if let majorVersion = bashMajorVersion(atPath: trimmed), majorVersion >= 4 {
                return trimmed
            }
        }
        return nil
    }

    func ensureModernBashInstalled() throws -> String {
        if let bashPath = modernBashExecutablePath() {
            return bashPath
        }

        guard let brewPath = brewExecutablePath() else {
            throw RuntimeComponentInstallerError.sdkmanRequiresModernBash
        }

        let command = "HOMEBREW_NO_AUTO_UPDATE=1 \(Self.shellQuoted(brewPath)) install bash"
        let result = try shellRunner.runShell(command, environment: environment)
        guard result.succeeded else {
            throw RuntimeComponentInstallerError.sdkmanModernBashInstallFailed(message: preferErrorOutput(result))
        }

        if let bashPath = modernBashExecutablePath() {
            return bashPath
        }
        throw RuntimeComponentInstallerError.sdkmanRequiresModernBash
    }

    func bashMajorVersion(atPath path: String) -> Int? {
        let output = runShellOutput("\(Self.shellQuoted(path)) --version")
        let firstLine = output.split(whereSeparator: \.isNewline).first.map(String.init) ?? output
        let pattern = #"version\s+(\d+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }
        let range = NSRange(location: 0, length: (firstLine as NSString).length)
        guard let match = regex.firstMatch(in: firstLine, range: range), match.numberOfRanges > 1 else {
            return nil
        }
        return Int((firstLine as NSString).substring(with: match.range(at: 1)))
    }

    func sdkmanInitScriptPath() -> String {
        let sdkmanDir = environment["SDKMAN_DIR"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let sdkmanDir, !sdkmanDir.isEmpty {
            return ((sdkmanDir as NSString).expandingTildeInPath as NSString)
                .appendingPathComponent("bin/sdkman-init.sh")
        }
        return (NSHomeDirectory() as NSString).appendingPathComponent(".sdkman/bin/sdkman-init.sh")
    }

    func sdkmanDirectoryPath() -> String {
        let initScriptPath = sdkmanInitScriptPath()
        return ((initScriptPath as NSString).deletingLastPathComponent as NSString).deletingLastPathComponent
    }

    func prepareBrokenSDKMANDirectoryForInstallIfNeeded() throws -> String? {
        let fileManager = FileManager.default
        let sdkmanDirectoryPath = sdkmanDirectoryPath()
        guard fileManager.fileExists(atPath: sdkmanDirectoryPath), !isSDKMANInstalled() else {
            return nil
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let timestamp = formatter.string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let backupPath = "\(sdkmanDirectoryPath).broken-\(timestamp)"
        try fileManager.moveItem(atPath: sdkmanDirectoryPath, toPath: backupPath)
        return backupPath
    }

    private func preferErrorOutput(_ result: ShellCommandResult) -> String {
        let stderr = result.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
        if !stderr.isEmpty {
            return stderr
        }
        let stdout = result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        return stdout.isEmpty ? "Unknown shell error" : stdout
    }

    static func shellQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\"'\"'"))'"
    }

    static let homebrewInstallCommand = """
    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    """

    static func sdkmanInstallCommand(bashPath: String) -> String {
        "SDKMAN_NON_INTERACTIVE=true curl -fsSL https://get.sdkman.io | \(shellQuoted(bashPath))"
    }

    static func sdkmanBootstrap(_ command: String) -> String {
        """
        export SDKMAN_DIR="${SDKMAN_DIR:-$HOME/.sdkman}"
        if [ -s "$SDKMAN_DIR/bin/sdkman-init.sh" ]; then
          . "$SDKMAN_DIR/bin/sdkman-init.sh"
        else
          echo "SDKMAN init script not found: $SDKMAN_DIR/bin/sdkman-init.sh" >&2
          exit 1
        fi
        \(command)
        """
    }

    static func parseSDKMANJavaCandidates(from output: String) -> [SDKMANJavaCandidate] {
        var candidates: [SDKMANJavaCandidate] = []
        var currentVendor = ""

        for rawLine in output.split(whereSeparator: \.isNewline) {
            let line = String(rawLine)
            guard line.contains("|") else {
                continue
            }
            if line.contains("Vendor") && line.contains("Identifier") {
                continue
            }

            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.hasPrefix("---") || trimmed.hasPrefix("===") {
                continue
            }

            let columns = line
                .split(separator: "|", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            guard columns.count >= 6 else {
                continue
            }

            let vendorColumn = columns[0]
            if !vendorColumn.isEmpty {
                currentVendor = vendorColumn
            }

            let version = columns[2]
            let distribution = columns[3]
            let identifier = columns[5]
            guard !currentVendor.isEmpty, !version.isEmpty, !distribution.isEmpty, !identifier.isEmpty else {
                continue
            }

            candidates.append(
                SDKMANJavaCandidate(
                    vendor: currentVendor,
                    version: version,
                    distribution: distribution,
                    identifier: identifier
                )
            )
        }

        return candidates
    }
}

public enum RuntimeComponentInstallerError: Error, LocalizedError {
    case homebrewUnavailable
    case homebrewInstallFailed(message: String)
    case nvmInstallFailed(message: String)
    case sdkmanUnavailable
    case sdkmanRequiresModernBash
    case sdkmanModernBashInstallFailed(message: String)
    case sdkmanInstallFailed(message: String)
    case sdkmanInstallIncomplete(initScriptPath: String, repairedBackupPath: String?)
    case sdkmanListJavaFailed(message: String)
    case invalidSDKMANJavaIdentifier(String)
    case sdkmanJavaInstallFailed(identifier: String, message: String)
    case sdkmanJavaUninstallFailed(identifier: String, message: String)
    case sdkmanSetDefaultFailed(identifier: String, message: String)

    public var errorDescription: String? {
        switch self {
        case .homebrewUnavailable:
            return "Homebrew is not available."
        case .homebrewInstallFailed(let message):
            return "Failed to install Homebrew: \(message)"
        case .nvmInstallFailed(let message):
            return "Failed to install NVM: \(message)"
        case .sdkmanUnavailable:
            return "SDKMAN is not available."
        case .sdkmanRequiresModernBash:
            return "SDKMAN requires Bash 4 or higher, and no usable modern Bash installation is available."
        case .sdkmanModernBashInstallFailed(let message):
            return "Failed to install modern Bash for SDKMAN: \(message)"
        case .sdkmanInstallFailed(let message):
            return "Failed to install SDKMAN: \(message)"
        case .sdkmanInstallIncomplete(let initScriptPath, let repairedBackupPath):
            if let repairedBackupPath, !repairedBackupPath.isEmpty {
                return "SDKMAN installation did not produce a usable init script at \(initScriptPath). A broken SDKMAN directory was moved to \(repairedBackupPath)."
            }
            return "SDKMAN installation did not produce a usable init script at \(initScriptPath)."
        case .sdkmanListJavaFailed(let message):
            return "Failed to query Java versions via SDKMAN: \(message)"
        case .invalidSDKMANJavaIdentifier(let identifier):
            return "Invalid SDKMAN Java identifier: \(identifier)"
        case .sdkmanJavaInstallFailed(let identifier, let message):
            return "Failed to install Java via SDKMAN (\(identifier)): \(message)"
        case .sdkmanJavaUninstallFailed(let identifier, let message):
            return "Failed to uninstall Java via SDKMAN (\(identifier)): \(message)"
        case .sdkmanSetDefaultFailed(let identifier, let message):
            return "Failed to set SDKMAN default Java (\(identifier)): \(message)"
        }
    }
}
