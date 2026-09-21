import Foundation
import ENVPilotCore

enum CLIExitCode: Int32 {
    case success = 0
    case runtimeFailure = 1
    case usageError = 2
    case doctorFailed = 3
}

struct CLIError: Error, CustomStringConvertible {
    let description: String
    let exitCode: CLIExitCode

    init(description: String, exitCode: CLIExitCode = .runtimeFailure) {
        self.description = description
        self.exitCode = exitCode
    }
}

private enum CLIOutputFormat {
    case text
    case json
}

private enum EffectiveVersionSource: String, Codable {
    case globalSelection
    case none
}

private struct VersionLocation: Codable {
    let version: String
    let path: String
}

private struct CLIStatusOutput: Codable {
    let cwd: String
    let selected_version: String
    let selected_node_path: String
    let effective_version: String
    let effective_version_source: String
    let selected_java_version: String
    let selected_java_home: String
    let selected_python_version: String
    let selected_python_home: String
    let detected_node_versions: [VersionLocation]
    let detected_jdk_versions: [VersionLocation]
    let detected_python_versions: [VersionLocation]
    let active_node_version: String
    let active_node_path: String
    let active_java_version: String
    let active_java_home: String
    let active_python_version: String
    let active_python_home: String
    let settings_exists: Bool
    let config_path: String
    let settings_path: String
}

private struct CLIDoctorCheck: Codable {
    let id: String
    let ok: Bool
    let required: Bool
    let message: String
    let fix_hint: String
}

private struct CLIDoctorSummary: Codable {
    let total: Int
    let required_failed: Int
    let optional_failed: Int
}

private struct CLIDoctorOutput: Codable {
    let all_checks_passed: Bool
    let summary: CLIDoctorSummary
    let checks: [CLIDoctorCheck]
}

/// `activate` 输出里的一个 `export`。
private struct CLIVariableOutput: Codable {
    let key: String
    let value: String
}

private struct CLIActivateOutput: Codable {
    let cwd: String
    let script: String
    let exports: [CLIVariableOutput]
}

private struct CLIInstallSnippetOutput: Codable {
    let helper_path: String
    let snippet: String
}

struct ENVPilotCLI {
    private let configStore: ConfigStore
    private let shellIntegration: ShellIntegrationService
    private let runtimeService: NodeEnvironmentService

    init(
        configStore: ConfigStore = ConfigStore(),
        shellIntegration: ShellIntegrationService = ShellIntegrationService(),
        runtimeService: NodeEnvironmentService = NodeEnvironmentService()
    ) {
        self.configStore = configStore
        self.shellIntegration = shellIntegration
        self.runtimeService = runtimeService
    }

    func run(arguments: [String]) -> Int32 {
        guard let command = arguments.first else {
            printUsage()
            return CLIExitCode.usageError.rawValue
        }

        let commandArguments = Array(arguments.dropFirst())

        do {
            switch command {
            case "status":
                try runStatus(arguments: commandArguments)
            case "doctor":
                try runDoctor(arguments: commandArguments)
            case "set-version":
                try runSetVersion(arguments: commandArguments)
            case "available":
                try runAvailable(arguments: commandArguments)
            case "install-node":
                try runInstallNode(arguments: commandArguments)
            case "install-jdk":
                try runInstallJDK(arguments: commandArguments)
            case "install-python":
                try runInstallPython(arguments: commandArguments)
            case "set-jdk":
                try runSetJDK(arguments: commandArguments)
            case "set-python":
                try runSetPython(arguments: commandArguments)
            case "config":
                try runConfig(arguments: commandArguments)
            case "list":
                try runList(arguments: commandArguments)
            case "activate":
                try runActivate(arguments: commandArguments)
            case "install-snippet":
                try runInstallSnippet(arguments: commandArguments)
            case "help", "--help", "-h":
                printUsage()
            default:
                throw CLIError(
                    description: "Unknown command: \(command)",
                    exitCode: .usageError
                )
            }
            return CLIExitCode.success.rawValue
        } catch {
            fputs("envpilot-helper error: \(error)\n", stderr)
            if let cliError = error as? CLIError {
                return cliError.exitCode.rawValue
            }
            return CLIExitCode.runtimeFailure.rawValue
        }
    }

    private func runStatus(arguments: [String]) throws {
        try validateOptions(
            in: arguments,
            // --cwd 继续接受（已安装用户的 ~/.zshrc 片段带着它跑），但不再参与选版本。
            allowedOptions: ["--cwd", "--format", "--fields"]
        )
        let settings = try configStore.load()
        let cwd = try parseCWD(from: arguments)
        let cwdPath = cwd?.path ?? FileManager.default.currentDirectoryPath
        let effectiveVersion = shellIntegration.resolveEffectiveVersion(settings: settings)
        let effectiveVersionSource = resolveEffectiveVersionSource(settings: settings)
        let settingsPath = try configStore.settingsURL().path
        let settingsExists = FileManager.default.fileExists(atPath: settingsPath)
        let snapshot = try runtimeService.loadSnapshot()
        let format = try parseOutputFormat(from: arguments)
        let selectedFields = try parseFieldsOption(from: arguments)

        let output = CLIStatusOutput(
            cwd: cwdPath,
            selected_version: settings.selectedVersion ?? "",
            selected_node_path: settings.selectedNodePath ?? "",
            effective_version: effectiveVersion ?? "",
            effective_version_source: effectiveVersionSource.rawValue,
            selected_java_version: settings.selectedJavaVersion ?? "",
            selected_java_home: settings.selectedJavaHome ?? "",
            selected_python_version: settings.selectedPythonVersion ?? "",
            selected_python_home: settings.selectedPythonHome ?? "",
            detected_node_versions: snapshot.installations.map { .init(version: $0.version, path: $0.installPath) },
            detected_jdk_versions: snapshot.javaInstallations.map { .init(version: $0.version, path: $0.homePath) },
            detected_python_versions: snapshot.pythonInstallations.map { .init(version: $0.version, path: $0.homePath) },
            active_node_version: snapshot.activeVersion ?? "",
            active_node_path: snapshot.activeNodePath ?? "",
            active_java_version: snapshot.activeJavaVersion ?? "",
            active_java_home: snapshot.activeJavaHome ?? "",
            active_python_version: snapshot.activePythonVersion ?? "",
            active_python_home: snapshot.activePythonHome ?? "",
            settings_exists: settingsExists,
            config_path: settingsPath,
            settings_path: settingsPath
        )

        if !selectedFields.isEmpty {
            try printFilteredStatus(output: output, format: format, selectedFields: selectedFields)
            return
        }

        switch format {
        case .text:
            print("cwd=\(output.cwd)")
            print("selected_version=\(output.selected_version)")
            print("selected_node_path=\(output.selected_node_path)")
            print("effective_version=\(output.effective_version)")
            print("effective_version_source=\(output.effective_version_source)")
            print("selected_java_version=\(output.selected_java_version)")
            print("selected_java_home=\(output.selected_java_home)")
            print("selected_python_version=\(output.selected_python_version)")
            print("selected_python_home=\(output.selected_python_home)")
            print("detected_node_versions=\(output.detected_node_versions.map { "\($0.version):\($0.path)" }.joined(separator: ","))")
            print("detected_jdk_versions=\(output.detected_jdk_versions.map { "\($0.version):\($0.path)" }.joined(separator: ","))")
            print("detected_python_versions=\(output.detected_python_versions.map { "\($0.version):\($0.path)" }.joined(separator: ","))")
            print("active_node_version=\(output.active_node_version)")
            print("active_node_path=\(output.active_node_path)")
            print("active_java_version=\(output.active_java_version)")
            print("active_java_home=\(output.active_java_home)")
            print("active_python_version=\(output.active_python_version)")
            print("active_python_home=\(output.active_python_home)")
            print("settings_exists=\(output.settings_exists)")
            print("config_path=\(output.config_path)")
            print("settings_path=\(output.settings_path)")
        case .json:
            try printJSON(output)
        }
    }

    private func runDoctor(arguments: [String]) throws {
        try validateOptions(
            in: arguments,
            allowedOptions: ["--format", "--check"]
        )

        let format = try parseOutputFormat(from: arguments)
        var checks = buildDoctorChecks()
        if let checkID = try parseValueOption(name: "--check", in: arguments) {
            guard checks.contains(where: { $0.id == checkID }) else {
                throw CLIError(
                    description: "Unknown doctor check id: \(checkID)",
                    exitCode: .usageError
                )
            }
            checks = checks.filter { $0.id == checkID }
        }

        let allChecksPassed = checks.filter(\.required).allSatisfy(\.ok)
        let summary = CLIDoctorSummary(
            total: checks.count,
            required_failed: checks.filter { $0.required && !$0.ok }.count,
            optional_failed: checks.filter { !$0.required && !$0.ok }.count
        )

        switch format {
        case .text:
            for check in checks {
                let statusText = check.ok ? "OK" : "FAIL"
                let requiredText = check.required ? "required" : "optional"
                print("[\(statusText)] \(check.id) (\(requiredText)) - \(check.message) | hint: \(check.fix_hint)")
            }
            print("doctor_total_checks=\(summary.total)")
            print("doctor_required_failed=\(summary.required_failed)")
            print("doctor_optional_failed=\(summary.optional_failed)")
            print("doctor_passed=\(allChecksPassed)")
        case .json:
            try printJSON(
                CLIDoctorOutput(
                    all_checks_passed: allChecksPassed,
                    summary: summary,
                    checks: checks
                )
            )
        }

        if !allChecksPassed {
            throw CLIError(
                description: "doctor found failing required checks",
                exitCode: .doctorFailed
            )
        }
    }

    private func runSetVersion(arguments: [String]) throws {
        try validateOptions(
            in: arguments,
            allowedOptions: ["--dry-run"]
        )
        let positionals = positionalArguments(from: arguments)
        guard let version = positionals.first else {
            throw CLIError(
                description: "set-version requires <version>",
                exitCode: .usageError
            )
        }

        if parseFlagOption(name: "--dry-run", in: arguments) {
            print("dry-run: would switch default node to \(version)")
            return
        }

        _ = try runtimeService.selectDefaultNode(version: version)
        print("switched default node to \(version) via ENVPilot")
    }

    private func runAvailable(arguments: [String]) throws {
        try validateOptions(in: arguments, allowedOptions: ["--format", "--lts"])
        let format = try parseOutputFormat(from: arguments)
        let ltsOnly = parseFlagOption(name: "--lts", in: arguments)
        let positionals = positionalArguments(from: arguments, flagOptions: ["--lts"])
        guard positionals.count == 1 else {
            throw CLIError(
                description: "available requires <n|node|j|java|jdk|py|python>",
                exitCode: .usageError
            )
        }

        switch positionals[0].lowercased() {
        case "n", "node":
            let candidates = try runtimeService.listAvailableNodeVersions(ltsOnly: ltsOnly)
            switch format {
            case .text:
                for candidate in candidates {
                    print("\(candidate.version)\t\(candidate.lts ?? "Current")")
                }
            case .json:
                try printJSON(candidates)
            }
        case "j", "java", "jdk":
            let candidates = try runtimeService.listAvailableJavaVersions(ltsOnly: ltsOnly)
            switch format {
            case .text:
                for candidate in candidates {
                    print("\(candidate.featureVersion)\t\(candidate.version)\t\(candidate.vendor)")
                }
            case .json:
                try printJSON(candidates)
            }
        case "py", "python", "python3":
            let candidates = try runtimeService.listAvailablePythonVersions(stableOnly: true)
            switch format {
            case .text:
                for candidate in candidates {
                    print("\(candidate.version)\t\(candidate.packageName)")
                }
            case .json:
                try printJSON(candidates)
            }
        default:
            throw CLIError(
                description: "Unsupported runtime: \(positionals[0]). Allowed: n|node|j|java|jdk|py|python",
                exitCode: .usageError
            )
        }
    }

    private func runInstallNode(arguments: [String]) throws {
        try validateOptions(in: arguments, allowedOptions: ["--dry-run"])
        let positionals = positionalArguments(from: arguments)
        guard let version = positionals.first else {
            throw CLIError(description: "install-node requires <version>", exitCode: .usageError)
        }
        if parseFlagOption(name: "--dry-run", in: arguments) {
            print("dry-run: would install Node \(version) through ENVPilot")
            return
        }
        let snapshot = try runtimeService.installNode(version: version, progress: cliProgressPrinter())
        print("installed node \(snapshot.settings.selectedVersion ?? version)")
    }

    private func runInstallJDK(arguments: [String]) throws {
        try validateOptions(in: arguments, allowedOptions: ["--dry-run"])
        let positionals = positionalArguments(from: arguments)
        guard let rawFeatureVersion = positionals.first, let featureVersion = Int(rawFeatureVersion) else {
            throw CLIError(description: "install-jdk requires <feature-version>, for example 21", exitCode: .usageError)
        }
        if parseFlagOption(name: "--dry-run", in: arguments) {
            print("dry-run: would install JDK \(featureVersion) through ENVPilot")
            return
        }
        let snapshot = try runtimeService.installJava(featureVersion: featureVersion, progress: cliProgressPrinter())
        print("installed jdk \(snapshot.settings.selectedJavaVersion ?? rawFeatureVersion)")
    }

    private func runInstallPython(arguments: [String]) throws {
        try validateOptions(in: arguments, allowedOptions: ["--dry-run"])
        let positionals = positionalArguments(from: arguments)
        guard let version = positionals.first else {
            throw CLIError(description: "install-python requires <version>", exitCode: .usageError)
        }
        if parseFlagOption(name: "--dry-run", in: arguments) {
            print("dry-run: would install Python \(version) through ENVPilot")
            return
        }
        let snapshot = try runtimeService.installPython(version: version, progress: cliProgressPrinter())
        print("installed python \(snapshot.settings.selectedPythonVersion ?? version)")
    }

    private func runSetJDK(arguments: [String]) throws {
        try validateOptions(
            in: arguments,
            allowedOptions: ["--dry-run"]
        )
        let positionals = positionalArguments(from: arguments)
        guard let javaRef = positionals.first else {
            throw CLIError(
                description: "set-jdk requires <version-or-home-path>",
                exitCode: .usageError
            )
        }

        let dryRun = parseFlagOption(name: "--dry-run", in: arguments)
        var settings = try configStore.load()
        let installations = try runtimeService.loadSnapshot().javaInstallations

        let matched: JavaInstallation?
        if javaRef.contains("/") {
            matched = installations.first(where: { $0.homePath == javaRef })
        } else {
            matched = installations.first(where: { $0.version == javaRef || $0.version.hasPrefix(javaRef + ".") })
        }

        guard let selected = matched else {
            throw CLIError(description: "Cannot find installed JDK matching: \(javaRef)")
        }

        if dryRun {
            print("dry-run: would select jdk \(selected.version) (\(selected.homePath))")
            return
        }

        settings.selectedJavaVersion = selected.version
        settings.selectedJavaHome = selected.homePath
        try configStore.save(settings)
        print("selected jdk \(selected.version) (\(selected.homePath))")
    }

    private func runSetPython(arguments: [String]) throws {
        try validateOptions(
            in: arguments,
            allowedOptions: ["--dry-run"]
        )
        let positionals = positionalArguments(from: arguments)
        guard let pythonRef = positionals.first else {
            throw CLIError(
                description: "set-python requires <version-or-home-path>",
                exitCode: .usageError
            )
        }

        let dryRun = parseFlagOption(name: "--dry-run", in: arguments)
        var settings = try configStore.load()
        let installations = try runtimeService.loadSnapshot().pythonInstallations

        let matched: PythonInstallation?
        if pythonRef.contains("/") {
            matched = installations.first(where: { $0.homePath == pythonRef })
        } else {
            matched = installations.first(where: { $0.version == pythonRef || $0.version.hasPrefix(pythonRef + ".") })
        }

        guard let selected = matched else {
            throw CLIError(description: "Cannot find installed Python matching: \(pythonRef)")
        }

        if dryRun {
            print("dry-run: would select python \(selected.version) (\(selected.homePath))")
            return
        }

        settings.selectedPythonVersion = selected.version
        settings.selectedPythonHome = selected.homePath
        try configStore.save(settings)
        print("selected python \(selected.version) (\(selected.homePath))")
    }

    private func runConfig(arguments: [String]) throws {
        guard let subcommand = arguments.first else {
            throw CLIError(
                description: "config requires a subcommand: get|set",
                exitCode: .usageError
            )
        }

        let positionals = positionalArguments(from: Array(arguments.dropFirst()))

        switch subcommand {
        case "get":
            guard positionals.count == 1 else {
                throw CLIError(
                    description: "config get requires <key>",
                    exitCode: .usageError
                )
            }
            try runConfigGet(key: positionals[0])
        case "set":
            guard positionals.count == 2 else {
                throw CLIError(
                    description: "config set requires <key> <value>",
                    exitCode: .usageError
                )
            }
            try runConfigSet(key: positionals[0], value: positionals[1])
        default:
            throw CLIError(
                description: "Unknown config subcommand: \(subcommand)",
                exitCode: .usageError
            )
        }
    }

    private func runConfigGet(key: String) throws {
        let settings = try configStore.load()

        switch key {
        case "selected-version":
            print(settings.selectedVersion ?? "")
        case "selected-node-path":
            print(settings.selectedNodePath ?? "")
        case "selected-java-version":
            print(settings.selectedJavaVersion ?? "")
        case "selected-java-home":
            print(settings.selectedJavaHome ?? "")
        case "selected-python-version":
            print(settings.selectedPythonVersion ?? "")
        case "selected-python-home":
            print(settings.selectedPythonHome ?? "")
        default:
            throw CLIError(
                description: "Unsupported config key: \(key)",
                exitCode: .usageError
            )
        }
    }

    private func runConfigSet(key: String, value: String) throws {
        switch key {
        case "selected-version":
            var settings = try configStore.load()
            if value == "none" {
                settings.selectedVersion = nil
                settings.selectedNodePath = nil
            } else {
                let normalizedVersion = NodeInstallationDetector.normalizeVersion(value) ?? value
                let snapshot = try runtimeService.loadSnapshot()
                guard let installation = snapshot.installations.first(where: { $0.version == normalizedVersion }) else {
                    throw CLIError(
                        description: "Node version is not detected locally: \(value)",
                        exitCode: .runtimeFailure
                    )
                }
                settings.selectedVersion = installation.version
                settings.selectedNodePath = installation.installPath
            }
            try configStore.save(settings)
            print("updated selected-version")
        case "selected-java":
            var settings = try configStore.load()
            if value == "none" {
                settings.selectedJavaVersion = nil
                settings.selectedJavaHome = nil
            } else {
                let installation = try resolveJavaInstallationOrThrow(reference: value)
                settings.selectedJavaVersion = installation.version
                settings.selectedJavaHome = installation.homePath
            }
            try configStore.save(settings)
            print("updated selected-java")
        case "selected-python":
            var settings = try configStore.load()
            if value == "none" {
                settings.selectedPythonVersion = nil
                settings.selectedPythonHome = nil
            } else {
                let installation = try resolvePythonInstallationOrThrow(reference: value)
                settings.selectedPythonVersion = installation.version
                settings.selectedPythonHome = installation.homePath
            }
            try configStore.save(settings)
            print("updated selected-python")
        default:
            throw CLIError(
                description: "Unsupported config key: \(key)",
                exitCode: .usageError
            )
        }
    }

    private func runList(arguments: [String]) throws {
        try validateOptions(in: arguments, allowedOptions: ["--format"])
        let format = try parseOutputFormat(from: arguments)
        let positionals = positionalArguments(from: arguments)
        guard positionals.count <= 1 else {
            throw CLIError(
                description: "list requires no arguments or <n|node|j|java|jdk|py|python>",
                exitCode: .usageError
            )
        }

        let runtime = positionals.first?.lowercased()
        let snapshot = try runtimeService.loadSnapshot()

        switch runtime {
        case nil:
            try printRuntimeList(
                nodeInstallations: snapshot.installations,
                javaInstallations: snapshot.javaInstallations,
                pythonInstallations: snapshot.pythonInstallations,
                format: format
            )
        case "n", "node":
            try printNodeList(snapshot.installations, format: format)
        case "j", "java", "jdk":
            try printJavaList(snapshot.javaInstallations, format: format)
        case "py", "python", "python3":
            try printPythonList(snapshot.pythonInstallations, format: format)
        default:
            throw CLIError(
                description: "Unsupported runtime: \(positionals[0]). Allowed: n|node|j|java|jdk|py|python",
                exitCode: .usageError
            )
        }
    }

    private func runActivate(arguments: [String]) throws {
        try validateOptions(
            in: arguments,
            allowedOptions: ["--cwd", "--format"]
        )
        let format = try parseOutputFormat(from: arguments)
        let settings = try configStore.load()
        let cwd = try parseCWD(from: arguments)
        let cwdPath = cwd?.path ?? FileManager.default.currentDirectoryPath
        let script = shellIntegration.renderActivationScript(
            settings: settings,
            shell: .zsh
        )
        switch format {
        case .text:
            print(script)
        case .json:
            try printJSON(
                CLIActivateOutput(
                    cwd: cwdPath,
                    script: script,
                    exports: parseExports(from: script)
                )
            )
        }
    }

    private func runInstallSnippet(arguments: [String]) throws {
        try validateOptions(
            in: arguments,
            allowedOptions: ["--helper-path", "--format"]
        )
        let format = try parseOutputFormat(from: arguments)
        let helperPath = try parseValueOption(name: "--helper-path", in: arguments) ?? resolvedDefaultHelperPath()
        let snippet = shellIntegration.renderInstallSnippet(helperPath: helperPath)
        switch format {
        case .text:
            print(snippet)
        case .json:
            try printJSON(
                CLIInstallSnippetOutput(
                    helper_path: helperPath,
                    snippet: snippet
                )
            )
        }
    }

    private func parseCWD(from arguments: [String]) throws -> URL? {
        if let value = try parseValueOption(name: "--cwd", in: arguments) {
            let path = (value as NSString).expandingTildeInPath
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    }

    private func parseValueOption(name: String, in arguments: [String]) throws -> String? {
        for (index, arg) in arguments.enumerated() {
            if arg == name {
                let valueIndex = arguments.index(after: index)
                guard valueIndex < arguments.endIndex else {
                    throw CLIError(
                        description: "Option \(name) requires a value",
                        exitCode: .usageError
                    )
                }
                return arguments[valueIndex]
            }

            let prefix = "\(name)="
            if arg.hasPrefix(prefix) {
                let value = String(arg.dropFirst(prefix.count))
                if value.isEmpty {
                    throw CLIError(
                        description: "Option \(name) requires a value",
                        exitCode: .usageError
                    )
                }
                return value
            }
        }
        return nil
    }

    private func parseOutputFormat(from arguments: [String]) throws -> CLIOutputFormat {
        guard let rawValue = try parseValueOption(name: "--format", in: arguments) else {
            return .text
        }
        switch rawValue {
        case "text":
            return .text
        case "json":
            return .json
        default:
            throw CLIError(
                description: "Unsupported format: \(rawValue). Allowed: text|json",
                exitCode: .usageError
            )
        }
    }

    private func parseFieldsOption(from arguments: [String]) throws -> [String] {
        guard let raw = try parseValueOption(name: "--fields", in: arguments) else {
            return []
        }
        let fields = raw
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if fields.isEmpty {
            throw CLIError(
                description: "--fields requires at least one field name",
                exitCode: .usageError
            )
        }
        return fields
    }

    private func parseFlagOption(name: String, in arguments: [String]) -> Bool {
        arguments.contains { argument in
            let option = normalizeOptionName(argument)
            return option == name
        }
    }

    private func positionalArguments(
        from arguments: [String],
        optionsWithValue: Set<String>? = nil,
        flagOptions: Set<String>? = nil
    ) -> [String] {
        var positionals: [String] = []
        let resolvedOptionsWithValue = optionsWithValue ?? [
            "--cwd",
            "--helper-path",
            "--format",
            "--fields",
            "--check",
        ]
        let resolvedFlagOptions = flagOptions ?? [
            "--dry-run",
        ]
        var skipNext = false

        for arg in arguments {
            if skipNext {
                skipNext = false
                continue
            }

            if resolvedOptionsWithValue.contains(arg) {
                skipNext = true
                continue
            }

            if arg.hasPrefix("--") {
                let normalized = normalizeOptionName(arg)
                if resolvedOptionsWithValue.contains(normalized) || resolvedFlagOptions.contains(normalized) {
                    continue
                }
            }

            positionals.append(arg)
        }

        return positionals
    }

    /// 版本来源只剩两种：全局选中的版本，或者什么都没选。
    private func resolveEffectiveVersionSource(settings: AppSettings) -> EffectiveVersionSource {
        if let selectedVersion = settings.selectedVersion, !selectedVersion.isEmpty {
            return .globalSelection
        }

        return .none
    }

    private func buildDoctorChecks() -> [CLIDoctorCheck] {
        var checks: [CLIDoctorCheck] = []
        let snapshot = try? runtimeService.loadSnapshot()
        checks.append(
            .init(
                id: "node_detected",
                ok: !(snapshot?.installations.isEmpty ?? true),
                required: true,
                message: "已检测到 ENVPilot 管理的 Node",
                fix_hint: "可执行 available node 查看候选，再用 install-node 安装"
            )
        )
        do {
            _ = try configStore.settingsURL()
            checks.append(
                .init(
                    id: "settings_path_resolved",
                    ok: true,
                    required: true,
                    message: "配置路径可解析",
                    fix_hint: "若失败，检查用户目录/Application Support 权限"
                )
            )
        } catch {
            checks.append(
                .init(
                    id: "settings_path_resolved",
                    ok: false,
                    required: true,
                    message: "配置路径解析失败: \(error)",
                    fix_hint: "检查 HOME 路径与 Application Support 目录权限"
                )
            )
        }

        do {
            let settings = try configStore.load()
            checks.append(
                .init(
                    id: "settings_readable",
                    ok: true,
                    required: true,
                    message: "配置可读取",
                    fix_hint: "若失败，检查 settings.json 文件权限或内容格式"
                )
            )
            do {
                try configStore.save(settings)
                checks.append(
                    .init(
                        id: "settings_writable",
                        ok: true,
                        required: true,
                        message: "配置可写入",
                        fix_hint: "若失败，检查 ENVPilot 配置目录写权限"
                    )
                )
            } catch {
                checks.append(
                    .init(
                        id: "settings_writable",
                        ok: false,
                        required: true,
                        message: "配置写入失败: \(error)",
                        fix_hint: "授予 Application Support/ENVPilot 写权限后重试"
                    )
                )
            }
        } catch {
            checks.append(
                .init(
                    id: "settings_readable",
                    ok: false,
                    required: true,
                    message: "配置读取失败: \(error)",
                    fix_hint: "修复 settings.json 的权限或 JSON 格式"
                )
            )
        }

        let snippet = shellIntegration.renderInstallSnippet(helperPath: "envpilot-helper")
        checks.append(
            .init(
                id: "shell_snippet_renderable",
                ok: !snippet.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                required: false,
                message: "zsh 自动激活 snippet 可生成",
                fix_hint: "检查 helper 安装路径，必要时重新安装 helper 与 snippet"
            )
        )

        return checks
    }

    private func resolveJavaInstallationOrThrow(reference: String) throws -> JavaInstallation {
        let installations = try runtimeService.loadSnapshot().javaInstallations
        let resolved: JavaInstallation?
        if reference.contains("/") {
            resolved = installations.first(where: { $0.homePath == reference })
        } else {
            resolved = installations.first(where: { $0.version == reference || $0.version.hasPrefix(reference + ".") })
        }
        guard let resolved else {
            throw CLIError(
                description: "Cannot find installed JDK matching: \(reference)",
                exitCode: .usageError
            )
        }
        return resolved
    }

    private func resolvePythonInstallationOrThrow(reference: String) throws -> PythonInstallation {
        let installations = try runtimeService.loadSnapshot().pythonInstallations
        let resolved: PythonInstallation?
        if reference.contains("/") {
            resolved = installations.first(where: { $0.homePath == reference })
        } else {
            resolved = installations.first(where: { $0.version == reference || $0.version.hasPrefix(reference + ".") })
        }
        guard let resolved else {
            throw CLIError(
                description: "Cannot find installed Python matching: \(reference)",
                exitCode: .usageError
            )
        }
        return resolved
    }

    private func resolveCachedNodeVersionOrThrow(_ reference: String, settings: AppSettings) throws -> String {
        let installations = settings.cachedNodeInstallations ?? []
        guard !installations.isEmpty else {
            throw CLIError(
                description: "No cached Node runtimes. Open ENVPilot and refresh runtimes, or run envpilot-helper status first.",
                exitCode: .runtimeFailure
            )
        }

        if let version = cachedNodeVersionMatching(reference, settings: settings) {
            return version
        }

        throw CLIError(
            description: "Cannot find cached Node matching: \(reference). Refresh runtimes in ENVPilot first.",
            exitCode: .runtimeFailure
        )
    }

    private func cachedNodeVersionMatching(_ reference: String, settings: AppSettings) -> String? {
        let installations = settings.cachedNodeInstallations ?? []
        let normalizedReference = NodeInstallationDetector.normalizeVersion(reference) ?? reference
        if let exactMatch = installations.first(where: { $0.version == normalizedReference }) {
            return exactMatch.version
        }
        if let majorMatch = installations.first(where: { $0.version.hasPrefix("\(normalizedReference).") }) {
            return majorMatch.version
        }
        return nil
    }

    private func resolveCachedJavaVersionOrThrow(_ reference: String, settings: AppSettings) throws -> String {
        let installations = settings.cachedJavaInstallations ?? []
        guard !installations.isEmpty else {
            throw CLIError(
                description: "No cached JDK runtimes. Open ENVPilot and refresh runtimes, or run envpilot-helper status first.",
                exitCode: .runtimeFailure
            )
        }

        if let version = cachedJavaVersionMatching(reference, settings: settings) {
            return version
        }

        throw CLIError(
            description: "Cannot find cached JDK matching: \(reference). Refresh runtimes in ENVPilot first.",
            exitCode: .runtimeFailure
        )
    }

    private func cachedJavaVersionMatching(_ reference: String, settings: AppSettings) -> String? {
        let installations = settings.cachedJavaInstallations ?? []
        if installations.contains(where: { $0.version == reference }) {
            return reference
        }
        if installations.contains(where: { $0.version == reference || $0.version.hasPrefix("\(reference).") }) {
            return reference
        }
        return nil
    }

    private func resolveCachedPythonVersionOrThrow(_ reference: String, settings: AppSettings) throws -> String {
        let installations = settings.cachedPythonInstallations ?? []
        guard !installations.isEmpty else {
            throw CLIError(
                description: "No cached Python runtimes. Open ENVPilot and refresh runtimes, or run envpilot-helper status first.",
                exitCode: .runtimeFailure
            )
        }

        if let version = cachedPythonVersionMatching(reference, settings: settings) {
            return version
        }

        throw CLIError(
            description: "Cannot find cached Python matching: \(reference). Refresh runtimes in ENVPilot first.",
            exitCode: .runtimeFailure
        )
    }

    private func cachedPythonVersionMatching(_ reference: String, settings: AppSettings) -> String? {
        let installations = settings.cachedPythonInstallations ?? []
        let normalizedReference = PythonRuntimeDetector.normalizeVersion(reference) ?? reference
        if let exactMatch = installations.first(where: { $0.version == normalizedReference }) {
            return exactMatch.version
        }
        if let featureMatch = installations.first(where: { $0.version.hasPrefix("\(normalizedReference).") }) {
            return featureMatch.version
        }
        return nil
    }

    private func printRuntimeList(
        nodeInstallations: [NodeInstallation],
        javaInstallations: [JavaInstallation],
        pythonInstallations: [PythonInstallation],
        format: CLIOutputFormat
    ) throws {
        switch format {
        case .text:
            print("node:")
            printVersionLocations(nodeInstallations.map { VersionLocation(version: $0.version, path: $0.installPath) })
            print("java:")
            printVersionLocations(javaInstallations.map { VersionLocation(version: $0.version, path: $0.homePath) })
            print("python:")
            printVersionLocations(pythonInstallations.map { VersionLocation(version: $0.version, path: $0.homePath) })
        case .json:
            try printJSON([
                "node": nodeInstallations.map { VersionLocation(version: $0.version, path: $0.installPath) },
                "java": javaInstallations.map { VersionLocation(version: $0.version, path: $0.homePath) },
                "python": pythonInstallations.map { VersionLocation(version: $0.version, path: $0.homePath) },
            ])
        }
    }

    private func printNodeList(_ installations: [NodeInstallation], format: CLIOutputFormat) throws {
        let locations = installations.map { VersionLocation(version: $0.version, path: $0.installPath) }
        switch format {
        case .text:
            printVersionLocations(locations)
        case .json:
            try printJSON(locations)
        }
    }

    private func printJavaList(_ installations: [JavaInstallation], format: CLIOutputFormat) throws {
        let locations = installations.map { VersionLocation(version: $0.version, path: $0.homePath) }
        switch format {
        case .text:
            printVersionLocations(locations)
        case .json:
            try printJSON(locations)
        }
    }

    private func printPythonList(_ installations: [PythonInstallation], format: CLIOutputFormat) throws {
        let locations = installations.map { VersionLocation(version: $0.version, path: $0.homePath) }
        switch format {
        case .text:
            printVersionLocations(locations)
        case .json:
            try printJSON(locations)
        }
    }

    private func printVersionLocations(_ locations: [VersionLocation]) {
        if locations.isEmpty {
            print("  no cached runtimes; refresh in ENVPilot or run ep status")
            return
        }

        for location in locations {
            print("  \(location.version)\t\(location.path)")
        }
    }

    private func cliProgressPrinter() -> @Sendable (String) -> Void {
        { message in
            print(message)
            fflush(stdout)
        }
    }

    private func normalizeVariableKey(_ key: String) throws -> String {
        let normalized = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            throw CLIError(description: "variable key cannot be empty", exitCode: .usageError)
        }
        if normalized.contains(where: { $0.isWhitespace }) {
            throw CLIError(description: "variable key cannot contain whitespace", exitCode: .usageError)
        }
        return normalized
    }

    private func parseExports(from script: String) -> [CLIVariableOutput] {
        script
            .split(whereSeparator: \.isNewline)
            .compactMap { rawLine -> CLIVariableOutput? in
                let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                guard line.hasPrefix("export ") else {
                    return nil
                }
                let declaration = line.dropFirst("export ".count)
                guard let equalIndex = declaration.firstIndex(of: "=") else {
                    return nil
                }
                let key = declaration[..<equalIndex].trimmingCharacters(in: .whitespaces)
                let value = declaration[declaration.index(after: equalIndex)...]
                return .init(key: String(key), value: String(value))
            }
    }

    private func printFilteredStatus(
        output: CLIStatusOutput,
        format: CLIOutputFormat,
        selectedFields: [String]
    ) throws {
        let object = try encodeToJSONObject(output)
        for field in selectedFields where object[field] == nil {
            throw CLIError(
                description: "Unknown status field: \(field)",
                exitCode: .usageError
            )
        }

        let filteredObject = selectedFields.reduce(into: [String: Any]()) { partial, field in
            partial[field] = object[field]
        }

        switch format {
        case .json:
            try printJSONObject(filteredObject)
        case .text:
            for field in selectedFields {
                if let value = filteredObject[field] {
                    print("\(field)=\(stringifyStatusField(value))")
                } else {
                    print("\(field)=")
                }
            }
        }
    }

    private func encodeToJSONObject<T: Encodable>(_ value: T) throws -> [String: Any] {
        let encoder = JSONEncoder()
        let data = try encoder.encode(value)
        let rawObject = try JSONSerialization.jsonObject(with: data, options: [])
        guard let object = rawObject as? [String: Any] else {
            throw CLIError(description: "Failed to encode JSON object", exitCode: .runtimeFailure)
        }
        return object
    }

    private func printJSONObject(_ object: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        guard let text = String(data: data, encoding: .utf8) else {
            throw CLIError(description: "Failed to encode JSON output", exitCode: .runtimeFailure)
        }
        print(text)
    }

    private func stringifyStatusField(_ value: Any) -> String {
        if let string = value as? String {
            return string
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        if JSONSerialization.isValidJSONObject(value),
           let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
           let json = String(data: data, encoding: .utf8) {
            return json
        }
        return "\(value)"
    }

    private func validateOptions(in arguments: [String], allowedOptions: Set<String>) throws {
        var skipNext = false
        for argument in arguments {
            if skipNext {
                skipNext = false
                continue
            }
            guard argument.hasPrefix("--") else {
                continue
            }
            let option = normalizeOptionName(argument)
            if !allowedOptions.contains(option) {
                throw CLIError(
                    description: "Unknown option: \(argument)",
                    exitCode: .usageError
                )
            }
            if !argument.contains("="), optionExpectsValue(option) {
                skipNext = true
            }
        }
    }

    private func optionExpectsValue(_ option: String) -> Bool {
        [
            "--cwd",
            "--helper-path",
            "--format",
            "--fields",
            "--check",
        ].contains(option)
    }

    private func normalizeOptionName(_ argument: String) -> String {
        if let equalIndex = argument.firstIndex(of: "=") {
            return String(argument[..<equalIndex])
        }
        return argument
    }

    private func printJSON<T: Encodable>(_ value: T) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(value)
        guard let json = String(data: data, encoding: .utf8) else {
            throw CLIError(description: "Failed to encode JSON output")
        }
        print(json)
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
          status [--cwd <path>] [--format text|json] [--fields <k1,k2>]
          doctor [--format text|json] [--check <id>]
          set-version <version> [--dry-run]
          available <n|node|j|java|jdk|py|python> [--format text|json] [--lts]
          install-node <version> [--dry-run]
          install-jdk <feature-version> [--dry-run]
          install-python <version> [--dry-run]
          set-jdk <version-or-home-path> [--dry-run]
          set-python <version-or-home-path> [--dry-run]
          list [n|node|j|java|py|python] [--format text|json]
          config get <selected-version|selected-node-path|selected-java-version|selected-java-home|selected-python-version|selected-python-home>
          config set selected-version <version|none>
          config set selected-java <version-or-home-path|none>
          config set selected-python <version-or-home-path|none>
          activate [--cwd <path>] [--format text|json]
          install-snippet [--helper-path <path>] [--format text|json]
        """
        print(usage)
    }
}

let cli = ENVPilotCLI()
let exitCode = cli.run(arguments: Array(CommandLine.arguments.dropFirst()))
exit(exitCode)
