import XCTest
@testable import ENVPilotCore

final class JavaAndShellIntegrationTests: XCTestCase {
    func testParseJavaInstallationsFromJavaHomeOutput() {
        let output = """
        Matching Java Virtual Machines (2):
            21.0.4 (arm64) "Eclipse Adoptium" - "OpenJDK 21.0.4" /Library/Java/JavaVirtualMachines/temurin-21.jdk/Contents/Home
            17.0.12 (arm64) "Eclipse Adoptium" - "OpenJDK 17.0.12" /Library/Java/JavaVirtualMachines/temurin-17.jdk/Contents/Home
        """

        let installations = JavaRuntimeDetector.parseInstallations(from: output)

        XCTAssertEqual(installations.count, 2)
        XCTAssertEqual(installations.first?.version, "21.0.4")
        XCTAssertEqual(installations.first?.homePath, "/Library/Java/JavaVirtualMachines/temurin-21.jdk/Contents/Home")
    }

    func testActivationScriptExportsJavaHomeWhenSelected() {
        let integration = ShellIntegrationService()
        let settings = AppSettings(
            selectedJavaVersion: "21.0.4",
            selectedJavaHome: "/Library/Java/JavaVirtualMachines/temurin-21.jdk/Contents/Home",
            profiles: [EnvironmentProfile(name: "Default")]
        )

        let script = integration.renderActivationScript(settings: settings, cwd: nil, shell: .zsh)

        XCTAssertTrue(script.contains("export ENVPILOT_EFFECTIVE_JAVA_VERSION='21.0.4'"))
        XCTAssertTrue(script.contains("export JAVA_HOME='/Library/Java/JavaVirtualMachines/temurin-21.jdk/Contents/Home'"))
        XCTAssertTrue(script.contains("export PATH=\"$JAVA_HOME/bin:$PATH\""))
    }

    func testActivationScriptUsesNVMForSelectedVersion() {
        let integration = ShellIntegrationService()
        let settings = AppSettings(
            selectedVersion: "14.21.3",
            profiles: [EnvironmentProfile(name: "Default")]
        )

        let script = integration.renderActivationScript(settings: settings, cwd: nil, shell: .zsh)

        XCTAssertTrue(script.contains("export NVM_DIR=\"${NVM_DIR:-$HOME/.nvm}\""))
        XCTAssertTrue(script.contains("if [ -s \"$NVM_DIR/nvm.sh\" ]; then"))
        XCTAssertTrue(script.contains("nvm use --silent '14.21.3'"))
    }
}
