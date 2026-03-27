import Foundation

public enum ENVPilotShellKind {
    case zsh
}

public struct ShellIntegrationService {
    private let projectVersionResolver: ProjectNodeVersionResolver
    private let profileBuilder: ProfileEnvironmentBuilder

    public init(
        projectVersionResolver: ProjectNodeVersionResolver = ProjectNodeVersionResolver(),
        profileBuilder: ProfileEnvironmentBuilder = ProfileEnvironmentBuilder()
    ) {
        self.projectVersionResolver = projectVersionResolver
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

    public func selectedProfile(in settings: AppSettings) -> EnvironmentProfile? {
        if let selectedID = settings.selectedProfileID,
           let selectedProfile = settings.profiles.first(where: { $0.id == selectedID }) {
            return selectedProfile
        }

        return settings.profiles.first
    }

    public func renderActivationScript(
        settings: AppSettings,
        cwd: URL?,
        shell: ENVPilotShellKind = .zsh
    ) -> String {
        var lines: [String] = []
        let effectiveVersion = resolveEffectiveVersion(settings: settings, cwd: cwd)
        let profile = selectedProfile(in: settings)
        let selectedJavaHome = settings.selectedJavaHome?.trimmingCharacters(in: .whitespacesAndNewlines)
        let selectedJavaVersion = settings.selectedJavaVersion?.trimmingCharacters(in: .whitespacesAndNewlines)

        if let effectiveVersion {
            lines.append("export ENVPILOT_EFFECTIVE_NODE_VERSION=\(shellSingleQuoted(effectiveVersion))")
            lines.append(contentsOf: nvmActivationLines(version: effectiveVersion, shell: shell))
        }
        if let profile {
            lines.append("export ENVPILOT_ACTIVE_PROFILE=\(shellSingleQuoted(profile.name))")
        }
        if let selectedJavaVersion, !selectedJavaVersion.isEmpty {
            lines.append("export ENVPILOT_EFFECTIVE_JAVA_VERSION=\(shellSingleQuoted(selectedJavaVersion))")
        }
        if let selectedJavaHome, !selectedJavaHome.isEmpty {
            lines.append("export JAVA_HOME=\(shellSingleQuoted(selectedJavaHome))")
            lines.append("export PATH=\"$JAVA_HOME/bin:$PATH\"")
        }

        let exports = profileBuilder.renderExportScript(from: profile)
        if !exports.isEmpty {
            lines.append(exports)
        }

        return lines.joined(separator: "\n")
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
          if [ -x \(quotedPath) ]; then
            eval "$(\(quotedPath) activate --cwd "$PWD")"
          elif command -v envpilot-helper >/dev/null 2>&1; then
            eval "$(envpilot-helper activate --cwd "$PWD")"
          fi
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

    private func nvmActivationLines(version: String, shell: ENVPilotShellKind) -> [String] {
        var lines: [String] = [
            "export NVM_DIR=\"${NVM_DIR:-$HOME/.nvm}\"",
            "mkdir -p \"$NVM_DIR\"",
            "if [ -s \"$NVM_DIR/nvm.sh\" ]; then",
            "  . \"$NVM_DIR/nvm.sh\"",
            "elif [ -s \"/opt/homebrew/opt/nvm/nvm.sh\" ]; then",
            "  . \"/opt/homebrew/opt/nvm/nvm.sh\"",
            "elif [ -s \"/usr/local/opt/nvm/nvm.sh\" ]; then",
            "  . \"/usr/local/opt/nvm/nvm.sh\"",
            "fi",
        ]
        switch shell {
        case .zsh:
            lines.append("nvm use --silent \(shellSingleQuoted(version)) >/dev/null 2>&1 || nvm use \(shellSingleQuoted(version)) >/dev/null 2>&1 || true")
        }
        return lines
    }

    private func shellSingleQuoted(_ text: String) -> String {
        "'\(text.replacingOccurrences(of: "'", with: "'\"'\"'"))'"
    }
}
