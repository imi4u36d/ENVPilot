import Foundation

public enum ENVPilotShellKind {
    case zsh
}

public struct ShellIntegrationService {
    private let projectVersionResolver: ProjectNodeVersionResolver
    private let projectJavaVersionResolver: ProjectJavaVersionResolver
    private let projectPythonVersionResolver: ProjectPythonVersionResolver
    private let profileBuilder: ProfileEnvironmentBuilder

    public init(
        projectVersionResolver: ProjectNodeVersionResolver = ProjectNodeVersionResolver(),
        projectJavaVersionResolver: ProjectJavaVersionResolver = ProjectJavaVersionResolver(),
        projectPythonVersionResolver: ProjectPythonVersionResolver = ProjectPythonVersionResolver(),
        profileBuilder: ProfileEnvironmentBuilder = ProfileEnvironmentBuilder()
    ) {
        self.projectVersionResolver = projectVersionResolver
        self.projectJavaVersionResolver = projectJavaVersionResolver
        self.projectPythonVersionResolver = projectPythonVersionResolver
        self.profileBuilder = profileBuilder
    }

    public func resolveEffectiveVersion(settings: AppSettings, cwd: URL?) -> String? {
        if settings.projectVersionPreference == .followProjectFiles, let cwd {
            if let version = projectVersionResolver.resolveVersion(startingAt: cwd), !version.isEmpty {
                return version
            }
        }

        return settings.selectedVersion
    }

    public func resolveEffectiveJavaVersion(settings: AppSettings, cwd: URL?) -> String? {
        if settings.projectVersionPreference == .followProjectFiles, let cwd {
            if let version = projectJavaVersionResolver.resolveVersion(startingAt: cwd), !version.isEmpty {
                return version
            }
        }

        return settings.selectedJavaVersion
    }

    public func resolveEffectivePythonVersion(settings: AppSettings, cwd: URL?) -> String? {
        if settings.projectVersionPreference == .followProjectFiles, let cwd {
            if let version = projectPythonVersionResolver.resolveVersion(startingAt: cwd), !version.isEmpty {
                return version
            }
        }

        return settings.selectedPythonVersion
    }

    public func selectedProfile(in settings: AppSettings) -> EnvironmentProfile? {
        if let selectedID = settings.selectedProfileID,
           let selectedProfile = settings.profiles.first(where: { $0.id == selectedID }) {
            return selectedProfile
        }

        return settings.profiles.first
    }

    public func renderActivationScript(
        settings: AppSettings,
        nodeInstallations: [NodeInstallation] = [],
        javaInstallations: [JavaInstallation] = [],
        pythonInstallations: [PythonInstallation] = [],
        cwd: URL?,
        shell: ENVPilotShellKind = .zsh
    ) -> String {
        var lines: [String] = []
        let resolvedNodeInstallations = nodeInstallations.isEmpty ? settings.cachedNodeInstallations ?? [] : nodeInstallations
        let resolvedJavaInstallations = javaInstallations.isEmpty ? settings.cachedJavaInstallations ?? [] : javaInstallations
        let resolvedPythonInstallations = pythonInstallations.isEmpty ? settings.cachedPythonInstallations ?? [] : pythonInstallations
        let effectiveVersion = resolveEffectiveVersion(settings: settings, cwd: cwd)
        let effectiveNodeInstallation = resolveEffectiveNodeInstallation(
            settings: settings,
            effectiveVersion: effectiveVersion,
            installations: resolvedNodeInstallations
        )
        let effectiveJavaVersion = resolveEffectiveJavaVersion(settings: settings, cwd: cwd)
        let effectiveJavaInstallation = resolveEffectiveJavaInstallation(
            settings: settings,
            effectiveVersion: effectiveJavaVersion,
            installations: resolvedJavaInstallations
        )
        let effectivePythonVersion = resolveEffectivePythonVersion(settings: settings, cwd: cwd)
        let effectivePythonInstallation = resolveEffectivePythonInstallation(
            settings: settings,
            effectiveVersion: effectivePythonVersion,
            installations: resolvedPythonInstallations
        )
        let profile = selectedProfile(in: settings)

        if let effectiveVersion {
            lines.append("export ENVPILOT_EFFECTIVE_NODE_VERSION=\(shellSingleQuoted(effectiveVersion))")
        }
        if let effectiveNodeInstallation {
            lines.append("export ENVPILOT_NODE_HOME=\(shellSingleQuoted(effectiveNodeInstallation.installPath))")
            lines.append("export PATH=\"$ENVPILOT_NODE_HOME/bin:$PATH\"")
        } else if let effectiveVersion, !effectiveVersion.isEmpty {
            lines.append("unset ENVPILOT_NODE_HOME")
            lines.append("echo \(shellSingleQuoted("ENVPilot: 未找到 Node \(effectiveVersion)，请在 ENVPilot 中刷新运行时缓存。")) >&2")
        }
        if let profile {
            lines.append("export ENVPILOT_ACTIVE_PROFILE=\(shellSingleQuoted(profile.name))")
        }
        if let effectiveJavaVersion, !effectiveJavaVersion.isEmpty {
            lines.append("export ENVPILOT_EFFECTIVE_JAVA_VERSION=\(shellSingleQuoted(effectiveJavaVersion))")
        }
        if let effectiveJavaInstallation {
            lines.append("export JAVA_HOME=\(shellSingleQuoted(effectiveJavaInstallation.homePath))")
            lines.append("export PATH=\"$JAVA_HOME/bin:$PATH\"")
        } else if let effectiveJavaVersion, !effectiveJavaVersion.isEmpty {
            lines.append("unset JAVA_HOME")
            lines.append("echo \(shellSingleQuoted("ENVPilot: 未找到 JDK \(effectiveJavaVersion)，请在 ENVPilot 中刷新运行时缓存。")) >&2")
        }
        if let effectivePythonVersion, !effectivePythonVersion.isEmpty {
            lines.append("export ENVPILOT_EFFECTIVE_PYTHON_VERSION=\(shellSingleQuoted(effectivePythonVersion))")
        }
        if let effectivePythonInstallation {
            lines.append("export ENVPILOT_PYTHON_HOME=\(shellSingleQuoted(effectivePythonInstallation.homePath))")
            lines.append("export PATH=\"$ENVPILOT_PYTHON_HOME/bin:$PATH\"")
        } else if let effectivePythonVersion, !effectivePythonVersion.isEmpty {
            lines.append("unset ENVPILOT_PYTHON_HOME")
            lines.append("echo \(shellSingleQuoted("ENVPilot: 未找到 Python \(effectivePythonVersion)，请在 ENVPilot 中刷新运行时缓存。")) >&2")
        }

        let exports = profileBuilder.renderExportScript(from: profile)
        if !exports.isEmpty {
            lines.append(exports)
        }

        return lines.joined(separator: "\n")
    }

    public func resolveEffectiveNodeInstallation(
        settings: AppSettings,
        effectiveVersion: String?,
        installations: [NodeInstallation]
    ) -> NodeInstallation? {
        let selectedPath = settings.selectedNodePath?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedSelectedPath = selectedPath.map(standardizedPath)
        let normalizedVersion = NodeInstallationDetector.normalizeVersion(effectiveVersion)
        let normalizedSelectedVersion = NodeInstallationDetector.normalizeVersion(settings.selectedVersion)

        if let normalizedVersion {
            let shouldRestrictToSelectedPath = normalizedVersion == normalizedSelectedVersion
            if let match = installations.first(where: { installation in
                installation.version == normalizedVersion
                    && (!shouldRestrictToSelectedPath || (normalizedSelectedPath.map { standardizedPath(installation.installPath) == $0 } ?? true))
            }) {
                return match
            }
            if installations.isEmpty,
               let selectedPath,
               !selectedPath.isEmpty,
               settings.selectedVersion == normalizedVersion,
               RuntimeComponentInstaller.isManagedNodePath(selectedPath) {
                return NodeInstallation(
                    version: normalizedVersion,
                    installPath: selectedPath,
                    executablePath: "\(selectedPath)/bin/node"
                )
            }
            return nil
        }

        if let normalizedSelectedPath, !normalizedSelectedPath.isEmpty {
            return installations.first {
                standardizedPath($0.installPath) == normalizedSelectedPath
            }
        }

        return nil
    }

    public func resolveEffectiveJavaInstallation(
        settings: AppSettings,
        effectiveVersion: String?,
        installations: [JavaInstallation]
    ) -> JavaInstallation? {
        let selectedHome = settings.selectedJavaHome?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedSelectedHome = selectedHome.map(standardizedPath)
        let requestedVersion = effectiveVersion?.trimmingCharacters(in: .whitespacesAndNewlines)

        if let requestedVersion, !requestedVersion.isEmpty {
            let shouldRestrictToSelectedHome = settings.selectedJavaVersion.map {
                javaVersion($0, matches: requestedVersion)
            } == true
            if let exactMatch = installations.first(where: { installation in
                installation.version == requestedVersion
                    && (!shouldRestrictToSelectedHome || (normalizedSelectedHome.map { standardizedPath(installation.homePath) == $0 } ?? true))
            }) {
                return exactMatch
            }

            if let majorMatch = installations.first(where: { installation in
                javaVersion(installation.version, matches: requestedVersion)
                    && (!shouldRestrictToSelectedHome || (normalizedSelectedHome.map { standardizedPath(installation.homePath) == $0 } ?? true))
            }) {
                return majorMatch
            }

            if installations.isEmpty,
               let selectedHome,
               !selectedHome.isEmpty,
               settings.selectedJavaVersion.map({ javaVersion($0, matches: requestedVersion) }) == true,
               RuntimeComponentInstaller.isManagedJavaHomePath(selectedHome) {
                return JavaInstallation(version: requestedVersion, homePath: selectedHome)
            }

            return nil
        }

        if let normalizedSelectedHome, !normalizedSelectedHome.isEmpty {
            return installations.first {
                standardizedPath($0.homePath) == normalizedSelectedHome
            }
        }

        return nil
    }

    public func resolveEffectivePythonInstallation(
        settings: AppSettings,
        effectiveVersion: String?,
        installations: [PythonInstallation]
    ) -> PythonInstallation? {
        let selectedHome = settings.selectedPythonHome?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedSelectedHome = selectedHome.map(standardizedPath)
        let requestedVersion = PythonRuntimeDetector.normalizeVersion(effectiveVersion) ?? effectiveVersion?.trimmingCharacters(in: .whitespacesAndNewlines)

        if let requestedVersion, !requestedVersion.isEmpty {
            let shouldRestrictToSelectedHome = settings.selectedPythonVersion.map {
                pythonVersion($0, matches: requestedVersion)
            } == true
            if let exactMatch = installations.first(where: { installation in
                installation.version == requestedVersion
                    && (!shouldRestrictToSelectedHome || (normalizedSelectedHome.map { standardizedPath(installation.homePath) == $0 } ?? true))
            }) {
                return exactMatch
            }

            if let featureMatch = installations.first(where: { installation in
                pythonVersion(installation.version, matches: requestedVersion)
                    && (!shouldRestrictToSelectedHome || (normalizedSelectedHome.map { standardizedPath(installation.homePath) == $0 } ?? true))
            }) {
                return featureMatch
            }

            if installations.isEmpty,
               let selectedHome,
               !selectedHome.isEmpty,
               settings.selectedPythonVersion.map({ pythonVersion($0, matches: requestedVersion) }) == true,
               RuntimeComponentInstaller.isManagedPythonHomePath(selectedHome) {
                return PythonInstallation(
                    version: requestedVersion,
                    homePath: selectedHome,
                    executablePath: "\(selectedHome)/bin/python3"
                )
            }

            return nil
        }

        if let normalizedSelectedHome, !normalizedSelectedHome.isEmpty {
            return installations.first {
                standardizedPath($0.homePath) == normalizedSelectedHome
            }
        }

        return nil
    }

    public func renderInstallSnippet(helperPath: String?) -> String {
        let explicitHelperPath: String
        if let helperPath, !helperPath.isEmpty {
            explicitHelperPath = helperPath
        } else {
            explicitHelperPath = "envpilot-helper"
        }

        let quotedPath = shellSingleQuoted(explicitHelperPath)
        return """
        # >>> ENVPilot >>>
        envpilot_auto_activate() {
          if [ -n "${ENVPILOT_ACTIVATING:-}" ]; then
            return 0
          fi
          export ENVPILOT_ACTIVATING=1
          local envpilot_state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/envpilot"
          local envpilot_env_file="$envpilot_state_dir/activation.zsh"
          local envpilot_tmp_file="$envpilot_env_file.tmp.$$"
          mkdir -p "$envpilot_state_dir"
          if [ -x \(quotedPath) ]; then
            \(quotedPath) activate --cwd "$PWD" > "$envpilot_tmp_file" && mv "$envpilot_tmp_file" "$envpilot_env_file" && . "$envpilot_env_file"
          elif command -v envpilot-helper >/dev/null 2>&1; then
            envpilot-helper activate --cwd "$PWD" > "$envpilot_tmp_file" && mv "$envpilot_tmp_file" "$envpilot_env_file" && . "$envpilot_env_file"
          fi
          rm -f "$envpilot_tmp_file"
          unset ENVPILOT_ACTIVATING
        }
        if [ -n "${ZSH_VERSION:-}" ]; then
          autoload -Uz add-zsh-hook 2>/dev/null || true
          if typeset -f add-zsh-hook >/dev/null 2>&1; then
            add-zsh-hook chpwd envpilot_auto_activate
          fi
        fi
        envpilot_auto_activate
        # <<< ENVPilot <<<
        """
    }

    private func shellSingleQuoted(_ text: String) -> String {
        "'\(text.replacingOccurrences(of: "'", with: "'\"'\"'"))'"
    }

    private func standardizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
    }

    private func javaVersion(_ installedVersion: String, matches requestedVersion: String) -> Bool {
        let installed = installedVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        let requested = requestedVersion.trimmingCharacters(in: .whitespacesAndNewlines)

        if installed == requested {
            return true
        }

        let requestedMajor = requested.split(separator: ".").first.map(String.init)
        guard let requestedMajor, !requestedMajor.isEmpty else {
            return false
        }

        return installed == requestedMajor || installed.hasPrefix("\(requestedMajor).")
    }

    private func pythonVersion(_ installedVersion: String, matches requestedVersion: String) -> Bool {
        let installed = installedVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        let requested = requestedVersion.trimmingCharacters(in: .whitespacesAndNewlines)

        if installed == requested {
            return true
        }

        let requestedParts = requested.split(separator: ".")
        guard requestedParts.count >= 2 else {
            return false
        }
        let requestedFeature = "\(requestedParts[0]).\(requestedParts[1])"
        return installed == requestedFeature || installed.hasPrefix("\(requestedFeature).")
    }
}
