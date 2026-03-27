import Foundation

public protocol RuntimeComponentInstalling: Sendable {
    func canInstall(_ component: InstallableComponent) -> Bool
    func install(_ component: InstallableComponent) throws
}

public struct RuntimeComponentInstaller: RuntimeComponentInstalling, Sendable {
    private let shellRunner: any ShellCommandRunning

    public init(shellRunner: any ShellCommandRunning = ShellCommandRunner()) {
        self.shellRunner = shellRunner
    }

    public func canInstall(_ component: InstallableComponent) -> Bool {
        switch component {
        case .nvm:
            return hasCommand("brew")
        case .jdk21:
            return hasCommand("brew")
        }
    }

    public func install(_ component: InstallableComponent) throws {
        guard canInstall(component) else {
            throw RuntimeComponentInstallerError.installNotSupported(component)
        }

        let command: String
        switch component {
        case .nvm:
            command = "mkdir -p \"$HOME/.nvm\"; brew list nvm >/dev/null 2>&1 || HOMEBREW_NO_AUTO_UPDATE=1 brew install nvm"
        case .jdk21:
            command = "brew install openjdk@21"
        }

        let result = try shellRunner.runShell(command, environment: ProcessInfo.processInfo.environment)
        guard result.succeeded else {
            throw RuntimeComponentInstallerError.installFailed(
                component: component,
                message: preferErrorOutput(result)
            )
        }
    }

    private func hasCommand(_ command: String) -> Bool {
        guard let result = try? shellRunner.runShell("command -v \(command) >/dev/null 2>&1", environment: ProcessInfo.processInfo.environment) else {
            return false
        }
        return result.succeeded
    }

    private func preferErrorOutput(_ result: ShellCommandResult) -> String {
        let stderr = result.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
        if !stderr.isEmpty {
            return stderr
        }
        let stdout = result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        return stdout.isEmpty ? "Unknown shell error" : stdout
    }
}

public enum RuntimeComponentInstallerError: Error, LocalizedError {
    case installNotSupported(InstallableComponent)
    case installFailed(component: InstallableComponent, message: String)

    public var errorDescription: String? {
        switch self {
        case .installNotSupported(let component):
            return "Install is not supported for \(component.displayName) in this environment."
        case .installFailed(let component, let message):
            return "Failed to install \(component.displayName): \(message)"
        }
    }
}
