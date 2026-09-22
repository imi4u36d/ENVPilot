import XCTest
@testable import ENVPilotCore

final class ShellCommandRunnerTests: XCTestCase {
    func testRunCapturesBothOutputStreamsAndExitCode() throws {
        let result = try ShellCommandRunner().run(
            "/bin/zsh",
            arguments: ["-c", "printf stdout; printf stderr >&2; exit 7"],
            environment: [:]
        )

        XCTAssertEqual(result.standardOutput, "stdout")
        XCTAssertEqual(result.standardError, "stderr")
        XCTAssertEqual(result.exitCode, 7)
        XCTAssertFalse(result.succeeded)
    }

    func testRunDrainsLargeOutputStreamsWithoutBlocking() throws {
        let result = try ShellCommandRunner().run(
            "/bin/zsh",
            arguments: [
                "-c",
                "chunk=$(printf 'x%.0s' {1..1024}); for _ in {1..256}; do printf %s \"$chunk\"; printf %s \"$chunk\" >&2; done",
            ],
            environment: [:]
        )

        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(result.standardOutput.utf8.count, 256 * 1_024)
        XCTAssertEqual(result.standardError.utf8.count, 256 * 1_024)
    }

    func testCancellationTerminatesRunningCommand() async throws {
        let cancellation = ShellCommandCancellation()
        let start = ContinuousClock.now
        let task = Task.detached {
            try ShellCommandRunner().runShell(
                "exec sleep 5",
                environment: [:],
                cancellation: cancellation,
                onOutput: nil
            )
        }

        try await Task.sleep(for: .milliseconds(100))
        cancellation.cancel()
        let result = try await task.value

        XCTAssertTrue(cancellation.isCancelled)
        XCTAssertFalse(result.succeeded)
        XCTAssertLessThan(start.duration(to: .now), .seconds(2))
    }

    func testStreamingOutputIsDeliveredBeforeCommandCompletes() throws {
        let output = LockedOutput()
        let result = try ShellCommandRunner().runShell(
            "printf 'downloading\\n'; sleep 0.1; printf 'installing\\n'",
            environment: [:],
            cancellation: nil,
            onOutput: { output.append($0) }
        )

        XCTAssertTrue(result.succeeded)
        XCTAssertTrue(output.value.contains("downloading"))
        XCTAssertTrue(output.value.contains("installing"))
    }

    // MARK: - 超时

    func testTimeoutTerminatesCommandAndReportsTimeoutExitCode() throws {
        let start = ContinuousClock.now
        let result = try ShellCommandRunner().runShell(
            "sleep 30",
            environment: [:],
            cancellation: nil,
            timeout: 0.4,
            onOutput: nil
        )

        XCTAssertTrue(result.timedOut)
        XCTAssertEqual(result.exitCode, ShellCommandResult.timeoutExitCode)
        XCTAssertFalse(result.succeeded)
        XCTAssertTrue(result.standardError.contains("已终止"), result.standardError)
        XCTAssertLessThan(start.duration(to: .now), .seconds(5))
    }

    func testCommandThatFinishesInsideTimeoutIsNotMarkedTimedOut() throws {
        let result = try ShellCommandRunner().runShell(
            "printf done",
            environment: [:],
            cancellation: nil,
            timeout: 10,
            onOutput: nil
        )

        XCTAssertFalse(result.timedOut)
        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(result.standardOutput, "done")
    }

    func testTimeoutKillsDescendantProcesses() async throws {
        let pidFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("envpilot-timeout-child-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: pidFile) }

        let result = try ShellCommandRunner().runShell(
            "sleep 30 & echo $! > \(ShellSyntax.singleQuoted(pidFile.path)); wait",
            environment: [:],
            cancellation: nil,
            timeout: 0.6,
            onOutput: nil
        )

        XCTAssertTrue(result.timedOut)
        let childPID = try await readPID(from: pidFile)
        let childGone = await waitUntilGone(childPID)
        XCTAssertTrue(childGone, "超时后子进程 \(childPID) 仍然存活")
    }

    // MARK: - 取消整棵进程树

    func testCancellationKillsDescendantProcesses() async throws {
        let pidFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("envpilot-cancel-child-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: pidFile) }

        let cancellation = ShellCommandCancellation()
        let task = Task.detached {
            try ShellCommandRunner().runShell(
                "sleep 30 & echo $! > \(ShellSyntax.singleQuoted(pidFile.path)); wait",
                environment: [:],
                cancellation: cancellation,
                onOutput: nil
            )
        }

        let childPID = try await readPID(from: pidFile)
        cancellation.cancel()
        _ = try await task.value

        let childGone = await waitUntilGone(childPID)
        XCTAssertTrue(childGone, "取消后子进程 \(childPID) 仍然存活")
    }

    func testStandardInputIsClosedSoCommandsCannotBlockOnAPrompt() throws {
        let start = ContinuousClock.now
        let result = try ShellCommandRunner().runShell(
            "cat; printf 'after'",
            environment: [:],
            cancellation: nil,
            timeout: 10,
            onOutput: nil
        )

        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(result.standardOutput, "after")
        XCTAssertLessThan(start.duration(to: .now), .seconds(5))
    }

    // MARK: - 辅助

    private func readPID(from url: URL) async throws -> pid_t {
        for _ in 0..<100 {
            if let text = try? String(contentsOf: url, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines),
               let pid = pid_t(text)
            {
                return pid
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw XCTSkip("子进程 pid 未在 5 秒内写入 \(url.path)")
    }

    private func waitUntilGone(_ pid: pid_t) async -> Bool {
        for _ in 0..<60 {
            if kill(pid, 0) != 0 {
                return true
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return kill(pid, 0) != 0
    }
}

private final class LockedOutput: @unchecked Sendable {
    private let lock = NSLock()
    private var output = ""

    func append(_ chunk: String) {
        lock.lock()
        output += chunk
        lock.unlock()
    }

    var value: String {
        lock.lock()
        defer { lock.unlock() }
        return output
    }
}

/// 取消令牌的「自定义取消动作」：`URLSession` 这类停不掉进程的工作靠它真正中止。
final class ShellCommandCancellationTests: XCTestCase {
    func testCancellationHandlerRunsOnCancel() {
        let cancellation = ShellCommandCancellation()
        let ran = LockedFlag()
        cancellation.registerCancellationHandler { ran.set() }

        XCTAssertFalse(ran.value)
        cancellation.cancel()
        XCTAssertTrue(ran.value)
    }

    func testHandlerRegisteredAfterCancelRunsImmediately() {
        let cancellation = ShellCommandCancellation()
        cancellation.cancel()

        let ran = LockedFlag()
        cancellation.registerCancellationHandler { ran.set() }

        XCTAssertTrue(ran.value, "注册时已经取消，动作应当立刻执行")
    }

    func testCancelIsIdempotent() {
        let cancellation = ShellCommandCancellation()
        let counter = LockedCounter()
        cancellation.registerCancellationHandler { counter.increment() }

        cancellation.cancel()
        cancellation.cancel()

        XCTAssertEqual(counter.value, 1, "重复取消不应重复触发")
    }
}

private final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false

    func set() {
        lock.lock()
        flag = true
        lock.unlock()
    }

    var value: Bool {
        lock.lock()
        defer { lock.unlock() }
        return flag
    }
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func increment() {
        lock.lock()
        count += 1
        lock.unlock()
    }

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }
}
