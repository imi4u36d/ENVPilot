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
}
