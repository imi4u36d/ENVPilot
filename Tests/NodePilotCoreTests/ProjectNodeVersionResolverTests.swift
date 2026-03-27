import XCTest
@testable import ENVPilotCore

final class ProjectNodeVersionResolverTests: XCTestCase {
    func testResolveVersionReturnsNilWhenProjectFilesAreMissing() throws {
        let resolver = ProjectNodeVersionResolver()
        let url = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)

        XCTAssertNil(resolver.resolveVersion(startingAt: url))
    }
}
