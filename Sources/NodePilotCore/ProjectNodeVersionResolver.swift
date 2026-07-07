import Foundation

public struct ProjectNodeVersionResolver {
    private let fileManager: FileManager
    private let envPilotParser: ProjectEnvPilotFileParser

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.envPilotParser = ProjectEnvPilotFileParser(fileManager: fileManager)
    }

    public func resolveVersion(startingAt directory: URL) -> String? {
        var currentURL = directory.standardizedFileURL

        while true {
            if let version = version(in: currentURL) {
                return version
            }

            let parentURL = currentURL.deletingLastPathComponent()
            if parentURL.path == currentURL.path {
                return nil
            }
            currentURL = parentURL
        }
    }

    private func version(in directory: URL) -> String? {
        envPilotParser.value(for: "NODE_VERSION", in: directory)
    }
}

public struct ProjectJavaVersionResolver {
    private let fileManager: FileManager
    private let envPilotParser: ProjectEnvPilotFileParser

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.envPilotParser = ProjectEnvPilotFileParser(fileManager: fileManager)
    }

    public func resolveVersion(startingAt directory: URL) -> String? {
        var currentURL = directory.standardizedFileURL

        while true {
            if let version = version(in: currentURL) {
                return version
            }

            let parentURL = currentURL.deletingLastPathComponent()
            if parentURL.path == currentURL.path {
                return nil
            }
            currentURL = parentURL
        }
    }

    private func version(in directory: URL) -> String? {
        envPilotParser.value(for: "JAVA_VERSION", in: directory)
    }
}

private struct ProjectEnvPilotFileParser {
    private let fileManager: FileManager

    init(fileManager: FileManager) {
        self.fileManager = fileManager
    }

    func value(for key: String, in directory: URL) -> String? {
        let fileURL = directory.appendingPathComponent(".envpilot")
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return nil
        }

        guard let contents = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return nil
        }

        for line in contents.split(whereSeparator: \.isNewline) {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedLine.isEmpty, !trimmedLine.hasPrefix("#") else {
                continue
            }

            let parts = trimmedLine.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else {
                continue
            }

            let parsedKey = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            guard parsedKey == key else {
                continue
            }

            let value = stripOptionalQuotes(String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines))
            return value.isEmpty ? nil : value
        }

        return nil
    }

    private func stripOptionalQuotes(_ value: String) -> String {
        guard value.count >= 2 else {
            return value
        }

        if value.hasPrefix("\""), value.hasSuffix("\"") {
            return String(value.dropFirst().dropLast())
        }
        if value.hasPrefix("'"), value.hasSuffix("'") {
            return String(value.dropFirst().dropLast())
        }

        return value
    }
}
