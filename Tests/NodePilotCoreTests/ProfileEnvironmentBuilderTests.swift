import XCTest
@testable import ENVPilotCore

final class ProfileEnvironmentBuilderTests: XCTestCase {
    func testRenderExportScriptIncludesBuiltInAndCustomVariables() {
        let builder = ProfileEnvironmentBuilder()
        let profile = EnvironmentProfile(
            name: "Work",
            npmRegistry: "https://registry.npmjs.org",
            pnpmRegistry: "https://r.pnpmjs.org",
            yarnRegistry: "https://registry.yarnpkg.com",
            nodeOptions: "--max-old-space-size=4096",
            variables: [
                CustomEnvironmentVariable(key: "TEAM", value: "platform"),
                CustomEnvironmentVariable(key: "AUTH_TOKEN", value: "abc'def"),
                CustomEnvironmentVariable(key: "INVALID KEY", value: "ignored"),
            ]
        )

        let script = builder.renderExportScript(from: profile)

        XCTAssertTrue(script.contains("export NPM_CONFIG_REGISTRY='https://registry.npmjs.org'"))
        XCTAssertTrue(script.contains("export PNPM_CONFIG_REGISTRY='https://r.pnpmjs.org'"))
        XCTAssertTrue(script.contains("export YARN_NPM_REGISTRY_SERVER='https://registry.yarnpkg.com'"))
        XCTAssertTrue(script.contains("export NODE_OPTIONS='--max-old-space-size=4096'"))
        XCTAssertTrue(script.contains("export TEAM='platform'"))
        XCTAssertTrue(script.contains("export AUTH_TOKEN='abc'\"'\"'def'"))
        XCTAssertFalse(script.contains("INVALID KEY"))
    }

    func testRenderExportScriptReturnsEmptyForNilProfile() {
        let builder = ProfileEnvironmentBuilder()
        XCTAssertEqual(builder.renderExportScript(from: nil), "")
    }

    func testCustomVariableCanOverrideBuiltInKey() {
        let builder = ProfileEnvironmentBuilder()
        let profile = EnvironmentProfile(
            name: "Override",
            npmRegistry: "https://default.registry",
            variables: [
                CustomEnvironmentVariable(key: "NPM_CONFIG_REGISTRY", value: "https://override.registry"),
            ]
        )

        let script = builder.renderExportScript(from: profile)
        XCTAssertTrue(script.contains("export NPM_CONFIG_REGISTRY='https://override.registry'"))
        XCTAssertFalse(script.contains("export NPM_CONFIG_REGISTRY='https://default.registry'"))
    }
}
