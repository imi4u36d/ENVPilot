import Foundation
import ENVPilotCore

struct CLIError: Error, CustomStringConvertible {
    let description: String
}

struct ENVPilotCLI {
    private let configStore: ConfigStore
    private let shellIntegration: ShellIntegrationService
    private let javaDetector: JavaRuntimeDetector
    private let runtimeService: NodeEnvironmentService

    init(
        configStore: ConfigStore = ConfigStore(),
        shellIntegration: ShellIntegrationService = ShellIntegrationService(),
        javaDetector: JavaRuntimeDetector = JavaRuntimeDetector(),
        runtimeService: NodeEnvironmentService = NodeEnvironmentService()
    ) {
        self.configStore = configStore
        self.shellIntegration = shellIntegration
        self.javaDetector = javaDetector
        self.runtimeService = runtimeService
    }

    func run(arguments: [String]) -> Int32 {
        guard let command = arguments.first else {
            printUsage()
            return 1
        }

        let commandArguments = Array(arguments.dropFirst())

        do {
            switch command {
            case "status":
                try runStatus(arguments: commandArguments)
            case "set-version":
                try runSetVersion(arguments: commandArguments)
            case "install-sdkman":
                try runInstallSDKMAN()
            case "sdk-install-jdk":
                try runSDKInstallJDK(arguments: commandArguments)
            case "set-profile":
                try runSetProfile(arguments: commandArguments)
            case "set-jdk":
                try runSetJDK(arguments: commandArguments)
            case "activate":
                try runActivate(arguments: commandArguments)
            case "install-snippet":
                try runInstallSnippet(arguments: commandArguments)
            case "help", "--help", "-h":
                printUsage()
            default:
                throw CLIError(description: "Unknown command: \(command)")
            }
            return 0
        } catch {
            fputs("envpilot-helper error: \(error)\n", stderr)
            return 1
        }
    }

    private func runStatus(arguments: [String]) throws {
        let settings = try configStore.load()
        let cwd = try parseCWD(from: arguments)
        let effectiveVersion = shellIntegration.resolveEffectiveVersion(settings: settings, cwd: cwd)
        let selectedProfile = shellIntegration.selectedProfile(in: settings)
        let settingsPath = try configStore.settingsURL().path
        let snapshot = try runtimeService.loadSnapshot()

        print("cwd=\(cwd?.path ?? FileManager.default.currentDirectoryPath)")
        print("selected_version=\(settings.selectedVersion ?? "")")
        print("effective_version=\(effectiveVersion ?? "")")
        print("project_version_preference=\(settings.projectVersionPreference.rawValue)")
        print("selected_profile_id=\(selectedProfile?.id.uuidString ?? "")")
        print("selected_profile_name=\(selectedProfile?.name ?? "")")
        print("selected_java_version=\(settings.selectedJavaVersion ?? "")")
        print("selected_java_home=\(settings.selectedJavaHome ?? "")")
        print("profiles_count=\(settings.profiles.count)")
        print("sdkman_installed=\(snapshot.sdkmanStatus.isInstalled)")
        print("sdkman_can_install=\(snapshot.sdkmanStatus.canInstall)")
        print("sdkman_has_managed_jdks=\(snapshot.sdkmanStatus.hasManagedJavaInstallations)")
        print("detected_node_versions=\(snapshot.installations.map { "\($0.version):\($0.installPath)" }.joined(separator: ","))")
        print("detected_jdk_versions=\(snapshot.javaInstallations.map { "\($0.version):\($0.homePath)" }.joined(separator: ","))")
        print("active_node_version=\(snapshot.activeVersion ?? "")")
        print("active_node_path=\(snapshot.activeNodePath ?? "")")
        print("active_java_version=\(snapshot.activeJavaVersion ?? "")")
        print("settings_path=\(settingsPath)")
    }

    private func runSetVersion(arguments: [String]) throws {
        let positionals = positionalArguments(from: arguments)
        guard let version = positionals.first else {
            throw CLIError(description: "set-version requires <version>")
        }

        _ = try runtimeService.selectDefaultNode(version: version)
        print("switched default node to \(version) via nvm")
    }

    private func runInstallSDKMAN() throws {
        _ = try runtimeService.installSDKMAN(progress: nil)
        print("sdkman installed or already available")
    }

    private func runSDKInstallJDK(arguments: [String]) throws {
        let positionals = positionalArguments(from: arguments)
        guard let identifier = positionals.first else {
            throw CLIError(description: "sdk-install-jdk requires <identifier>")
        }
        let snapshot = try runtimeService.installJavaWithSDKMAN(identifier: identifier, progress: nil)
        let activeJava = snapshot.activeJavaVersion ?? snapshot.settings.selectedJavaVersion ?? identifier
        print("installed jdk via sdkman: \(identifier), active java: \(activeJava)")
    }

    private func runSetProfile(arguments: [String]) throws {
        let positionals = positionalArguments(from: arguments)
        guard let profileRef = positionals.first else {
            throw CLIError(description: "set-profile requires <profile-name-or-id>")
        }

        var settings = try configStore.load()
        let selectedProfile: EnvironmentProfile

        if let profileID = UUID(uuidString: profileRef),
           let profile = settings.profiles.first(where: { $0.id == profileID }) {
            selectedProfile = profile
        } else if let profile = settings.profiles.first(where: { $0.name.caseInsensitiveCompare(profileRef) == .orderedSame }) {
            selectedProfile = profile
        } else {
            let profile = EnvironmentProfile(name: profileRef)
            settings.profiles.append(profile)
            selectedProfile = profile
            print("created new profile \(profile.name)")
        }

        settings.selectedProfileID = selectedProfile.id
        try configStore.save(settings)
        print("selected profile \(selectedProfile.name) (\(selectedProfile.id.uuidString))")
    }

    private func runSetJDK(arguments: [String]) throws {
        let positionals = positionalArguments(from: arguments)
        guard let javaRef = positionals.first else {
            throw CLIError(description: "set-jdk requires <version-or-home-path>")
        }

        var settings = try configStore.load()
        let installations = javaDetector.detectInstallations()

        let matched: JavaInstallation?
        if javaRef.contains("/") {
            matched = installations.first(where: { $0.homePath == javaRef })
        } else {
            matched = installations.first(where: { $0.version == javaRef || $0.version.hasPrefix(javaRef + ".") })
        }

        guard let selected = matched else {
            throw CLIError(description: "Cannot find installed JDK matching: \(javaRef)")
        }

        settings.selectedJavaVersion = selected.version
        settings.selectedJavaHome = selected.homePath
        try configStore.save(settings)
        print("selected jdk \(selected.version) (\(selected.homePath))")
    }

    private func runActivate(arguments: [String]) throws {
        let settings = try configStore.load()
        let cwd = try parseCWD(from: arguments)
        let script = shellIntegration.renderActivationScript(settings: settings, cwd: cwd, shell: .zsh)
        print(script)
    }

    private func runInstallSnippet(arguments: [String]) throws {
        let helperPath = try parseValueOption(name: "--helper-path", in: arguments) ?? resolvedDefaultHelperPath()
        let snippet = shellIntegration.renderInstallSnippet(helperPath: helperPath)
        print(snippet)
    }

    private func parseCWD(from arguments: [String]) throws -> URL? {
        if let value = try parseValueOption(name: "--cwd", in: arguments) {
            let path = (value as NSString).expandingTildeInPath
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    }

    private func parseValueOption(name: String, in arguments: [String]) throws -> String? {
        guard let index = arguments.firstIndex(of: name) else {
            return nil
        }
        let valueIndex = arguments.index(after: index)
        guard valueIndex < arguments.endIndex else {
            throw CLIError(description: "Option \(name) requires a value")
        }
        return arguments[valueIndex]
    }

    private func positionalArguments(from arguments: [String]) -> [String] {
        var positionals: [String] = []
        var skipNext = false

        for (idx, arg) in arguments.enumerated() {
            if skipNext {
                skipNext = false
                continue
            }

            if arg == "--cwd" || arg == "--helper-path" {
                let nextIndex = idx + 1
                if nextIndex < arguments.count {
                    skipNext = true
                }
                continue
            }

            if arg.hasPrefix("--") {
                continue
            }
            positionals.append(arg)
        }

        return positionals
    }

    private func resolvedDefaultHelperPath() -> String {
        let rawPath = CommandLine.arguments.first ?? "envpilot-helper"
        let expanded = (rawPath as NSString).expandingTildeInPath
        let absolute = URL(fileURLWithPath: expanded).standardizedFileURL.path
        return absolute
    }

    private func printUsage() {
        let usage = """
        Usage: envpilot-helper <command> [options]

        Commands:
          status [--cwd <path>]
          set-version <version>
          install-sdkman
          sdk-install-jdk <identifier>
          set-profile <profile-name-or-id>
          set-jdk <version-or-home-path>
          activate [--cwd <path>]
          install-snippet [--helper-path <path>]
        """
        print(usage)
    }
}

let cli = ENVPilotCLI()
let exitCode = cli.run(arguments: Array(CommandLine.arguments.dropFirst()))
exit(exitCode)
