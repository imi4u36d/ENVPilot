import Foundation

public struct ProjectNodeVersionResolver {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
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
        for filename in [".nvmrc", ".node-version"] {
            let fileURL = directory.appendingPathComponent(filename)
            guard fileManager.fileExists(atPath: fileURL.path) else {
                continue
            }

            guard
                let contents = try? String(contentsOf: fileURL, encoding: .utf8),
                let version = contents
                    .split(whereSeparator: \.isNewline)
                    .map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
                    .first(where: { !$0.isEmpty && !$0.hasPrefix("#") }),
                !version.isEmpty
            else {
                continue
            }

            return version
        }

        return nil
    }
}
