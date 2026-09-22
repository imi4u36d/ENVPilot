import Darwin
import Foundation

public struct ShellCommandResult: Sendable {
    public let standardOutput: String
    public let standardError: String
    public let exitCode: Int32
    /// 命令是否因超时被本进程终止（`exitCode` 此时固定为 124）。
    public let timedOut: Bool

    public init(
        standardOutput: String,
        standardError: String,
        exitCode: Int32,
        timedOut: Bool = false
    ) {
        self.standardOutput = standardOutput
        self.standardError = standardError
        self.exitCode = exitCode
        self.timedOut = timedOut
    }

    public var succeeded: Bool {
        exitCode == 0
    }

    /// 超时终止沿用 `timeout(1)` 的退出码约定，方便调用方按退出码判断。
    public static let timeoutExitCode: Int32 = 124
}

/// 取消令牌。
///
/// 不只是给 `/bin/zsh` 发 SIGTERM：安装类命令（`npm install`、`brew`、`make`）都是
/// zsh 的子进程，只杀 shell 会让它们变成孤儿继续跑。这里注册的是「杀掉整棵进程树」
/// 的闭包，见 `ShellCommandRunner.processTreeKiller`.
public final class ShellCommandCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var killTree: (@Sendable (Int32) -> Void)?
    private var cancelHandlers: [@Sendable () -> Void] = []
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
        let killTree = killTree
        let handlers = cancelHandlers
        self.process = nil
        self.killTree = nil
        self.cancelHandlers = []
        lock.unlock()
        if process != nil {
            // shell 先收到 SIGTERM 有机会转发/清理，随后由 runner 兜底 SIGKILL 整棵树。
            killTree?(SIGTERM)
        }
        for handler in handlers {
            handler()
        }
    }

    /// 注册一个自定义取消动作。
    ///
    /// 有些工作停不掉进程就能停：`URLSession` 的下载要调 `invalidateAndCancel()`。
    /// 注册时若已被取消，动作立刻执行——调用方不必再自己查一遍状态。
    public func registerCancellationHandler(_ handler: @escaping @Sendable () -> Void) {
        lock.lock()
        if cancelled {
            lock.unlock()
            handler()
            return
        }
        cancelHandlers.append(handler)
        lock.unlock()
    }

    fileprivate func register(_ process: Process, killTree: @escaping @Sendable (Int32) -> Void) {
        lock.lock()
        if cancelled {
            lock.unlock()
            killTree(SIGTERM)
            return
        }
        self.process = process
        self.killTree = killTree
        lock.unlock()
    }

    fileprivate func clear(_ process: Process) {
        lock.lock()
        if self.process === process {
            self.process = nil
            self.killTree = nil
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
    /// 带墙钟超时的版本。超时后整棵进程树被终止，返回 `timedOut == true`、退出码 124，
    /// 而不是抛出错误——调用点现有的「非 0 退出 + stderr」错误路径直接就能显示出来。
    func runShell(
        _ command: String,
        environment: [String: String],
        cancellation: ShellCommandCancellation?,
        timeout: TimeInterval,
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

    /// 默认实现忽略超时，供测试替身使用；真实 runner 会覆盖它。
    func runShell(
        _ command: String,
        environment: [String: String],
        cancellation: ShellCommandCancellation?,
        timeout: TimeInterval,
        onOutput: (@Sendable (String) -> Void)?
    ) throws -> ShellCommandResult {
        try runShell(command, environment: environment, cancellation: cancellation, onOutput: onOutput)
    }
}

public struct ShellCommandRunner: ShellCommandRunning, Sendable {
    /// 常规命令的墙钟上限。安装/构建类命令显式传 `Self.longRunningTimeout`。
    public static let defaultTimeout: TimeInterval = 30 * 60
    /// 源码构建（Python `configure && make install`）这类长任务的上限。
    public static let longRunningTimeout: TimeInterval = 60 * 60
    /// SIGTERM 之后留给进程退出的时间，超时即 SIGKILL。
    private static let terminationGrace: TimeInterval = 3
    /// 用户主动取消时，SIGTERM 之后再 SIGKILL 清残留的宽限时间。
    private static let cancellationGrace: TimeInterval = 0.5
    /// 进程退出后等待管道 EOF 的时间；仅用于「孙子进程握着写端」的病态情况。
    private static let pipeDrainGrace: TimeInterval = 5

    public init() {}

    public func run(_ launchPath: String, arguments: [String], environment: [String: String] = ProcessInfo.processInfo.environment) throws -> ShellCommandResult {
        try run(
            launchPath,
            arguments: arguments,
            environment: environment,
            cancellation: nil,
            timeout: Self.defaultTimeout,
            onOutput: nil
        )
    }

    public func runShell(_ command: String, environment: [String: String] = ProcessInfo.processInfo.environment) throws -> ShellCommandResult {
        try run(
            "/bin/zsh",
            arguments: ["-lc", command],
            environment: environment,
            cancellation: nil,
            timeout: Self.defaultTimeout,
            onOutput: nil
        )
    }

    public func runShell(
        _ command: String,
        environment: [String: String],
        onOutput: (@Sendable (String) -> Void)?
    ) throws -> ShellCommandResult {
        try runShell(
            command,
            environment: environment,
            cancellation: nil,
            timeout: Self.defaultTimeout,
            onOutput: onOutput
        )
    }

    public func runShell(
        _ command: String,
        environment: [String: String],
        cancellation: ShellCommandCancellation?,
        onOutput: (@Sendable (String) -> Void)?
    ) throws -> ShellCommandResult {
        try runShell(
            command,
            environment: environment,
            cancellation: cancellation,
            timeout: Self.defaultTimeout,
            onOutput: onOutput
        )
    }

    public func runShell(
        _ command: String,
        environment: [String: String],
        cancellation: ShellCommandCancellation?,
        timeout: TimeInterval,
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
            timeout: timeout,
            onOutput: onOutput
        )
    }

    private func run(
        _ launchPath: String,
        arguments: [String],
        environment: [String: String],
        cancellation: ShellCommandCancellation?,
        timeout: TimeInterval,
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
        // 显式断开 stdin：交互式提示（sudo / npm login）读不到输入会立刻失败并回报，
        // 而不是把整个操作挂在这里等超时。
        process.standardInput = FileHandle.nullDevice

        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }

        try process.run()
        let pid = process.processIdentifier

        let stdoutReader = ConcurrentPipeReader(
            fileHandle: stdoutPipe.fileHandleForReading,
            onOutput: onOutput
        )
        let stderrReader = ConcurrentPipeReader(
            fileHandle: stderrPipe.fileHandleForReading,
            onOutput: onOutput
        )
        stdoutReader.start()
        stderrReader.start()

        // 进程树在第一次调用时捕获，之后一直复用同一张表——父进程一死，父子关系就断了。
        let killTree = Self.processTreeKiller(rootPID: pid)
        cancellation?.register(process, killTree: killTree)

        var timedOut = false
        var didExit = exited.wait(timeout: .now() + timeout) == .success
        if !didExit {
            // 超时：先 SIGTERM 整棵树，宽限期内没退就 SIGKILL。
            // 注意被信号杀掉同样算「已退出」，所以超时必须在这里显式记下来，
            // 不能靠 didExit 反推。
            timedOut = true
            killTree(SIGTERM)
            didExit = exited.wait(timeout: .now() + Self.terminationGrace) == .success
            if !didExit {
                killTree(SIGKILL)
                didExit = exited.wait(timeout: .now() + Self.terminationGrace) == .success
            }
        } else if cancellation?.isCancelled == true {
            // 用户取消：`cancel()` 已经对整棵树发过 SIGTERM，这里只做「宽限后清残留」。
            Thread.sleep(forTimeInterval: Self.cancellationGrace)
            killTree(SIGKILL)
        }

        cancellation?.clear(process)
        process.terminationHandler = nil

        let deadline = Date().addingTimeInterval(Self.pipeDrainGrace)
        let stdoutData = stdoutReader.result(until: deadline)
        let stderrData = stderrReader.result(until: deadline)

        var standardError = String(decoding: stderrData, as: UTF8.self)
        let exitCode: Int32
        if timedOut || !didExit {
            exitCode = ShellCommandResult.timeoutExitCode
        } else {
            exitCode = process.terminationStatus
        }

        if timedOut || !didExit {
            let seconds = Int(timeout.rounded())
            if !standardError.isEmpty, !standardError.hasSuffix("\n") {
                standardError += "\n"
            }
            standardError += "ENVPilot: 命令超过 \(seconds) 秒未结束，已终止（退出码 \(ShellCommandResult.timeoutExitCode)）。"
        }

        return ShellCommandResult(
            standardOutput: String(decoding: stdoutData, as: UTF8.self),
            standardError: standardError,
            exitCode: exitCode,
            timedOut: timedOut
        )
    }

    // MARK: - 进程树

    /// 返回 `SIGTERM`/`SIGKILL` 闭包。
    ///
    /// 用 `Process` 起子进程时无法把它放进独立进程组（`Process` 不暴露
    /// `posix_spawnattr_setpgroup`），所以按 pid 递归收集子孙再逐个发信号。
    /// 必须在杀父进程**之前**收集完整张表：父进程一死，子进程会被 launchd 收养，
    /// 父子关系就断了。因此这张表在闭包第一次被调用时捕获并一直复用。
    static func processTreeKiller(rootPID: pid_t) -> @Sendable (Int32) -> Void {
        let capture = ProcessTreeCapture()
        return { signal in
            let tree = capture.tree { descendantPIDs(of: rootPID) }
            signalTree(rootPID: rootPID, descendants: tree, signal: signal)
        }
    }

    /// 深度优先收集全部子孙（不含 `rootPID` 自身）。
    static func descendantPIDs(of rootPID: pid_t) -> [pid_t] {
        var collected: [pid_t] = []
        var seen: Set<pid_t> = [rootPID]
        var queue: [pid_t] = [rootPID]

        while let current = queue.popLast() {
            var buffer = [pid_t](repeating: 0, count: 256)
            let count = proc_listchildpids(
                current,
                &buffer,
                Int32(buffer.count * MemoryLayout<pid_t>.size)
            )
            guard count > 0 else {
                continue
            }
            for index in 0..<min(Int(count), buffer.count) {
                let child = buffer[index]
                guard child > 0, seen.insert(child).inserted else {
                    continue
                }
                collected.append(child)
                queue.append(child)
            }
        }
        return collected
    }

    /// 先杀子孙再杀根：反过来会先把 shell 干掉，子孙变成孤儿后仍持有管道写端。
    /// `kill` 对已消失的 pid 只返回 ESRCH，天然幂等。
    static func signalTree(rootPID: pid_t, descendants: [pid_t], signal: Int32) {
        for pid in descendants.reversed() where pid > 0 {
            kill(pid, signal)
        }
        if rootPID > 0 {
            kill(rootPID, signal)
        }
    }
}

/// 进程树快照的一次性持有者（`@Sendable` 闭包里不能改捕获的可变变量）。
private final class ProcessTreeCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var captured: [pid_t]?

    func tree(_ collect: () -> [pid_t]) -> [pid_t] {
        lock.lock()
        defer { lock.unlock() }
        if let captured {
            return captured
        }
        let collected = collect()
        captured = collected
        return collected
    }
}

/// 读管道。
///
/// 一律用 `readabilityHandler`（即使不需要回调）而不是阻塞式
/// `readDataToEndOfFile()`：没有数据可读时不会占住线程，超时路径也就不需要
/// 从别的线程去 `close()` 一个正在阻塞读的 fd（那是不安全的）。
/// `finish()` 做成幂等，避免「空 chunk + EOF」两条路径重复 `leave()` 导致崩溃。
private final class ConcurrentPipeReader: @unchecked Sendable {
    private let fileHandle: FileHandle
    private let onOutput: (@Sendable (String) -> Void)?
    private let group = DispatchGroup()
    private let lock = NSLock()
    private var data = Data()
    private var finished = false

    init(
        fileHandle: FileHandle,
        onOutput: (@Sendable (String) -> Void)?
    ) {
        self.fileHandle = fileHandle
        self.onOutput = onOutput
    }

    func start() {
        group.enter()
        let handle = fileHandle
        let onOutput = onOutput
        handle.readabilityHandler = { [weak self] readable in
            let chunk = readable.availableData
            guard !chunk.isEmpty else {
                self?.finish()
                return
            }
            self?.append(chunk)
            onOutput?(String(decoding: chunk, as: UTF8.self))
        }
    }

    /// 等待 EOF；到点仍未结束就放弃等待并返回已收到的部分输出。
    func result(until deadline: Date) -> Data {
        let remaining = deadline.timeIntervalSinceNow
        if remaining > 0, group.wait(timeout: .now() + remaining) == .timedOut {
            finish()
        }
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
        lock.lock()
        let alreadyFinished = finished
        finished = true
        lock.unlock()
        guard !alreadyFinished else {
            return
        }
        fileHandle.readabilityHandler = nil
        group.leave()
    }
}
