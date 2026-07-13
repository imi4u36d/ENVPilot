import Foundation

public struct ProfileEnvironmentBuilder: Sendable {
    public init() {}

    public func environmentVariables(from profile: EnvironmentProfile?) -> [String: String] {
        guard let profile else {
            return [:]
        }

        var variables: [String: String] = [:]

        if !profile.npmRegistry.isEmpty {
            variables["NPM_CONFIG_REGISTRY"] = profile.npmRegistry
        }
        if !profile.pnpmRegistry.isEmpty {
            variables["PNPM_CONFIG_REGISTRY"] = profile.pnpmRegistry
        }
        if !profile.yarnRegistry.isEmpty {
            variables["YARN_NPM_REGISTRY_SERVER"] = profile.yarnRegistry
        }
        if !profile.nodeOptions.isEmpty {
            variables["NODE_OPTIONS"] = profile.nodeOptions
        }

        for custom in profile.variables {
            let key = custom.key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard isValidEnvironmentKey(key) else {
                continue
            }
            variables[key] = custom.value
        }

        return variables
    }

    public func renderExportScript(from profile: EnvironmentProfile?) -> String {
        let variables = environmentVariables(from: profile)
        guard !variables.isEmpty else {
            return ""
        }

        let lines = variables.keys.sorted().compactMap { key -> String? in
            guard let value = variables[key] else {
                return nil
            }
            return "export \(key)=\(ShellSyntax.singleQuoted(value))"
        }

        return lines.joined(separator: "\n")
    }

    private func isValidEnvironmentKey(_ key: String) -> Bool {
        guard !key.isEmpty else {
            return false
        }

        let pattern = #"^[A-Za-z_][A-Za-z0-9_]*$"#
        return key.range(of: pattern, options: .regularExpression) != nil
    }
}
