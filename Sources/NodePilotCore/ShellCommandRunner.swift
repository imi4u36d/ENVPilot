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

public final class ShellCommandCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false

    public init() {}

    public var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    public func cancel() {
        lock.lock()
        guard !cancelled else {
            lock.unlock()
            return
        }
        cancelled = true
        let process = process
        self.process = nil
        lock.unlock()
        process?.terminate()
    }

    fileprivate func register(_ process: Process) {
        lock.lock()
        if cancelled {
            lock.unlock()
            process.terminate()
            return
        }
        self.process = process
        lock.unlock()
    }

    fileprivate func clear(_ process: Process) {
        lock.lock()
        if self.process === process {
            self.process = nil
        }
        lock.unlock()
    }
}

public protocol ShellCommandRunning: Sendable {
    func run(_ launchPath: String, arguments: [String], environment: [String: String]) throws -> ShellCommandResult
    func runShell(_ command: String, environment: [String: String]) throws -> ShellCommandResult
    func runShell(
        _ command: String,
        environment: [String: String],
        onOutput: (@Sendable (String) -> Void)?
    ) throws -> ShellCommandResult
    func runShell(
        _ command: String,
        environment: [String: String],
        cancellation: ShellCommandCancellation?,
        onOutput: (@Sendable (String) -> Void)?
    ) throws -> ShellCommandResult
}

public extension ShellCommandRunning {
    func runShell(
        _ command: String,
        environment: [String: String],
        onOutput: (@Sendable (String) -> Void)?
    ) throws -> ShellCommandResult {
        try runShell(command, environment: environment)
    }

    func runShell(
        _ command: String,
        environment: [String: String],
        cancellation: ShellCommandCancellation?,
        onOutput: (@Sendable (String) -> Void)?
    ) throws -> ShellCommandResult {
        if cancellation?.isCancelled == true {
            throw CancellationError()
        }
        return try runShell(command, environment: environment, onOutput: onOutput)
    }
}

public struct ShellCommandRunner: ShellCommandRunning, Sendable {
    public init() {}

    public func run(_ launchPath: String, arguments: [String], environment: [String: String] = ProcessInfo.processInfo.environment) throws -> ShellCommandResult {
        try run(launchPath, arguments: arguments, environment: environment, onOutput: nil)
    }

    public func runShell(_ command: String, environment: [String: String] = ProcessInfo.processInfo.environment) throws -> ShellCommandResult {
        try run("/bin/zsh", arguments: ["-lc", command], environment: environment)
    }

    public func runShell(
        _ command: String,
        environment: [String: String],
        onOutput: (@Sendable (String) -> Void)?
    ) throws -> ShellCommandResult {
        try runShell(command, environment: environment, cancellation: nil, onOutput: onOutput)
    }

    public func runShell(
        _ command: String,
        environment: [String: String],
        cancellation: ShellCommandCancellation?,
        onOutput: (@Sendable (String) -> Void)?
    ) throws -> ShellCommandResult {
        if cancellation?.isCancelled == true {
            throw CancellationError()
        }
        return try run(
            "/bin/zsh",
            arguments: ["-lc", command],
            environment: environment,
            cancellation: cancellation,
            onOutput: onOutput
        )
    }

    private func run(
        _ launchPath: String,
        arguments: [String],
        environment: [String: String],
        cancellation: ShellCommandCancellation? = nil,
        onOutput: (@Sendable (String) -> Void)?
    ) throws -> ShellCommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        process.environment = environment

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        cancellation?.register(process)
        let stdoutReader = ConcurrentPipeReader(
            fileHandle: stdoutPipe.fileHandleForReading,
            label: "envpilot.shell-command.stdout",
            onOutput: onOutput
        )
        let stderrReader = ConcurrentPipeReader(
            fileHandle: stderrPipe.fileHandleForReading,
            label: "envpilot.shell-command.stderr",
            onOutput: onOutput
        )
        stdoutReader.start()
        stderrReader.start()
        process.waitUntilExit()
        cancellation?.clear(process)

        return ShellCommandResult(
            standardOutput: String(decoding: stdoutReader.result(), as: UTF8.self),
            standardError: String(decoding: stderrReader.result(), as: UTF8.self),
            exitCode: process.terminationStatus
        )
    }
}

private final class ConcurrentPipeReader: @unchecked Sendable {
    private let fileHandle: FileHandle
    private let queue: DispatchQueue
    private let group = DispatchGroup()
    private let onOutput: (@Sendable (String) -> Void)?
    private let lock = NSLock()
    private var data = Data()

    init(
        fileHandle: FileHandle,
        label: String,
        onOutput: (@Sendable (String) -> Void)?
    ) {
        self.fileHandle = fileHandle
        self.queue = DispatchQueue(label: label, qos: .userInitiated)
        self.onOutput = onOutput
    }

    func start() {
        group.enter()
        if let onOutput {
            fileHandle.readabilityHandler = { [weak self] handle in
                let chunk = handle.availableData
                guard !chunk.isEmpty else {
                    handle.readabilityHandler = nil
                    self?.finish()
                    return
                }
                self?.append(chunk)
                onOutput(String(decoding: chunk, as: UTF8.self))
            }
        } else {
            queue.async { [self] in
                append(fileHandle.readDataToEndOfFile())
                finish()
            }
        }
    }

    func result() -> Data {
        group.wait()
        lock.lock()
        defer { lock.unlock() }
        return data
    }

    private func append(_ chunk: Data) {
        lock.lock()
        data.append(chunk)
        lock.unlock()
    }

    private func finish() {
        fileHandle.readabilityHandler = nil
        group.leave()
    }
}
