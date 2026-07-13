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
        let stdoutReader = ConcurrentPipeReader(
            fileHandle: stdoutPipe.fileHandleForReading,
            label: "envpilot.shell-command.stdout"
        )
        let stderrReader = ConcurrentPipeReader(
            fileHandle: stderrPipe.fileHandleForReading,
            label: "envpilot.shell-command.stderr"
        )
        stdoutReader.start()
        stderrReader.start()
        process.waitUntilExit()

        return ShellCommandResult(
            standardOutput: String(decoding: stdoutReader.result(), as: UTF8.self),
            standardError: String(decoding: stderrReader.result(), as: UTF8.self),
            exitCode: process.terminationStatus
        )
    }

    public func runShell(_ command: String, environment: [String: String] = ProcessInfo.processInfo.environment) throws -> ShellCommandResult {
        try run("/bin/zsh", arguments: ["-lc", command], environment: environment)
    }
}

private final class ConcurrentPipeReader: @unchecked Sendable {
    private let fileHandle: FileHandle
    private let queue: DispatchQueue
    private let group = DispatchGroup()
    private var data = Data()

    init(fileHandle: FileHandle, label: String) {
        self.fileHandle = fileHandle
        self.queue = DispatchQueue(label: label, qos: .userInitiated)
    }

    func start() {
        group.enter()
        queue.async { [self] in
            data = fileHandle.readDataToEndOfFile()
            group.leave()
        }
    }

    func result() -> Data {
        group.wait()
        return data
    }
}
