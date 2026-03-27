import Foundation

public protocol RuntimeComponentInstalling: Sendable {
    func isHomebrewInstalled() -> Bool
    func installHomebrew() throws
    func canInstallNVM() -> Bool
    func installNVM() throws
}

public struct RuntimeComponentInstaller: RuntimeComponentInstalling, Sendable {
    private let shellRunner: any ShellCommandRunning

    public init(shellRunner: any ShellCommandRunning = ShellCommandRunner()) {
        self.shellRunner = shellRunner
    }

    public func isHomebrewInstalled() -> Bool {
        brewExecutablePath() != nil
    }

    public func installHomebrew() throws {
        let result = try shellRunner.runShell(
            Self.homebrewInstallCommand,
            environment: ProcessInfo.processInfo.environment
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
        let result = try shellRunner.runShell(command, environment: ProcessInfo.processInfo.environment)
        guard result.succeeded else {
            throw RuntimeComponentInstallerError.nvmInstallFailed(message: preferErrorOutput(result))
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
        guard let result = try? shellRunner.runShell(command, environment: ProcessInfo.processInfo.environment) else {
            return ""
        }
        if !result.standardOutput.isEmpty {
            return result.standardOutput
        }
        return result.standardError
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
}

public enum RuntimeComponentInstallerError: Error, LocalizedError {
    case homebrewUnavailable
    case homebrewInstallFailed(message: String)
    case nvmInstallFailed(message: String)

    public var errorDescription: String? {
        switch self {
        case .homebrewUnavailable:
            return "Homebrew is not available."
        case .homebrewInstallFailed(let message):
            return "Failed to install Homebrew: \(message)"
        case .nvmInstallFailed(let message):
            return "Failed to install NVM: \(message)"
        }
    }
}
