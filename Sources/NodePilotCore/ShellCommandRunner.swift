import Foundation

public struct ShellCommandResult: Sendable {
    public let standardOutput: String
    public let standardError: String
    public let exitCode: Int32

    public init(standardOutput: String, standardError: String, exitCode: Int32) {
        self.standardOutput = standardOutput
        self.standardError = standardError
        self.exitCode = exitCode
    }

    public var succeeded: Bool {
        exitCode == 0
    }
}

public protocol ShellCommandRunning: Sendable {
    func run(_ launchPath: String, arguments: [String], environment: [String: String]) throws -> ShellCommandResult
    func runShell(_ command: String, environment: [String: String]) throws -> ShellCommandResult
}

public struct ShellCommandRunner: ShellCommandRunning, Sendable {
    public init() {}

    public func run(_ launchPath: String, arguments: [String], environment: [String: String] = ProcessInfo.processInfo.environment) throws -> ShellCommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        process.environment = environment

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        return ShellCommandResult(
            standardOutput: String(decoding: stdoutData, as: UTF8.self),
            standardError: String(decoding: stderrData, as: UTF8.self),
            exitCode: process.terminationStatus
        )
    }

    public func runShell(_ command: String, environment: [String: String] = ProcessInfo.processInfo.environment) throws -> ShellCommandResult {
        try run("/bin/zsh", arguments: ["-lc", command], environment: environment)
    }
}
