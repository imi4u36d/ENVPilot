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
