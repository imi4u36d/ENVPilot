import Foundation

public protocol JavaRuntimeDetecting: Sendable {
    func detectInstallations() -> [JavaInstallation]
    func detectActiveVersion() -> String?
    func detectActiveJavaHome() -> String?
}

public struct JavaRuntimeDetector: JavaRuntimeDetecting, Sendable {
    private let shellRunner: any ShellCommandRunning

    public init(shellRunner: any ShellCommandRunning = ShellCommandRunner()) {
        self.shellRunner = shellRunner
    }

    public func detectInstallations() -> [JavaInstallation] {
        let javaHomeOutput = runShellOutput("/usr/libexec/java_home -V 2>&1")
        let fromJavaHome = Self.parseInstallations(from: javaHomeOutput).map {
            JavaInstallation(version: $0.version, homePath: canonicalHomePath($0.homePath))
        }
        let defaultHome = detectDefaultJavaHome().map(canonicalHomePath)
        let parsedByPath = Dictionary(uniqueKeysWithValues: fromJavaHome.map { ($0.homePath, $0.version) })

        var allPaths = Set(fromJavaHome.map(\.homePath))
        allPaths.formUnion(discoverExtraJavaHomes().map(canonicalHomePath))

        let installations = allPaths.sorted().compactMap { homePath -> JavaInstallation? in
            let version = parsedByPath[homePath] ?? versionFromJavaBinary(homePath: homePath)
            guard let version, !version.isEmpty else {
                return nil
            }
            return JavaInstallation(
                version: version,
                homePath: homePath,
                isDefault: defaultHome == homePath
            )
        }

        return installations.sorted(by: sortJavaInstallation(_:_:))
    }

    public func detectActiveVersion() -> String? {
        let output = runShellOutput("java -version 2>&1")
        return Self.parseJavaVersion(fromJavaVersionOutput: output)
    }

    public func detectActiveJavaHome() -> String? {
        let envValue = ProcessInfo.processInfo.environment["JAVA_HOME"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let envValue, !envValue.isEmpty {
            return canonicalHomePath(envValue)
        }
        return detectDefaultJavaHome().map(canonicalHomePath)
    }

    private func detectDefaultJavaHome() -> String? {
        let output = runShellOutput("/usr/libexec/java_home 2>/dev/null")
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func canonicalHomePath(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
    }

    private func discoverExtraJavaHomes() -> Set<String> {
        var homes = Set<String>()
        let fileManager = FileManager.default

        for root in [
            "/Library/Java/JavaVirtualMachines",
            "/System/Library/Java/JavaVirtualMachines",
        ] {
            homes.formUnion(jdkHomesInJVMRoot(root, fileManager: fileManager))
        }

        for optRoot in ["/opt/homebrew/opt", "/usr/local/opt"] {
            homes.formUnion(jdkHomesInOpenJDKOptRoot(optRoot, fileManager: fileManager))
        }

        for cellarRoot in ["/opt/homebrew/Cellar", "/usr/local/Cellar"] {
            homes.formUnion(jdkHomesInOpenJDKCellarRoot(cellarRoot, fileManager: fileManager))
        }

        return homes
    }

    private func jdkHomesInJVMRoot(_ root: String, fileManager: FileManager) -> Set<String> {
        var homes = Set<String>()
        guard let entries = try? fileManager.contentsOfDirectory(atPath: root) else {
            return homes
        }
        for entry in entries where entry.hasSuffix(".jdk") {
            let home = "\(root)/\(entry)/Contents/Home"
            if fileManager.fileExists(atPath: home) {
                homes.insert(home)
            }
        }
        return homes
    }

    private func jdkHomesInOpenJDKOptRoot(_ root: String, fileManager: FileManager) -> Set<String> {
        var homes = Set<String>()
        guard let entries = try? fileManager.contentsOfDirectory(atPath: root) else {
            return homes
        }
        for entry in entries where entry.hasPrefix("openjdk") {
            let home = "\(root)/\(entry)/libexec/openjdk.jdk/Contents/Home"
            if fileManager.fileExists(atPath: home) {
                homes.insert(home)
            }
        }
        return homes
    }

    private func jdkHomesInOpenJDKCellarRoot(_ root: String, fileManager: FileManager) -> Set<String> {
        var homes = Set<String>()
        guard let formulaDirs = try? fileManager.contentsOfDirectory(atPath: root) else {
            return homes
        }

        for formula in formulaDirs where formula.hasPrefix("openjdk") {
            let formulaPath = "\(root)/\(formula)"
            guard let versions = try? fileManager.contentsOfDirectory(atPath: formulaPath) else {
                continue
            }
            for version in versions {
                let home = "\(formulaPath)/\(version)/libexec/openjdk.jdk/Contents/Home"
                if fileManager.fileExists(atPath: home) {
                    homes.insert(home)
                }
            }
        }
        return homes
    }

    private func versionFromJavaBinary(homePath: String) -> String? {
        let fileManager = FileManager.default
        let javaBin = homePath + "/bin/java"
        guard fileManager.isExecutableFile(atPath: javaBin) else {
            return nil
        }
        let output = runShellOutput("\(Self.singleQuoted(javaBin)) -version 2>&1")
        return Self.parseJavaVersion(fromJavaVersionOutput: output)
    }

    private func runShellOutput(_ command: String) -> String {
        guard let result = try? shellRunner.runShell(command, environment: ProcessInfo.processInfo.environment) else {
            return ""
        }
        if !result.standardOutput.isEmpty {
            return result.standardOutput
        }
        return result.standardError
    }

    private func sortJavaInstallation(_ lhs: JavaInstallation, _ rhs: JavaInstallation) -> Bool {
        if lhs.version == rhs.version {
            return lhs.homePath < rhs.homePath
        }
        return Self.isJavaVersionGreater(lhs.version, rhs.version)
    }

    static func parseInstallations(from javaHomeVersionOutput: String) -> [JavaInstallation] {
        var seenHomes = Set<String>()
        var installations: [JavaInstallation] = []

        for rawLine in javaHomeVersionOutput.split(whereSeparator: \.isNewline) {
            let line = String(rawLine).trimmingCharacters(in: .whitespaces)
            guard line.contains("/Contents/Home") else {
                continue
            }

            guard let homePath = line.components(separatedBy: " ").last?.trimmingCharacters(in: .whitespaces), !homePath.isEmpty else {
                continue
            }

            let version = parseVersionToken(in: line)
            guard let version, !version.isEmpty else {
                continue
            }

            guard seenHomes.insert(homePath).inserted else {
                continue
            }
            installations.append(JavaInstallation(version: version, homePath: homePath))
        }

        return installations.sorted(by: { lhs, rhs in
            if lhs.version == rhs.version {
                return lhs.homePath < rhs.homePath
            }
            return isJavaVersionGreater(lhs.version, rhs.version)
        })
    }

    static func parseJavaVersion(fromJavaVersionOutput output: String) -> String? {
        let pattern = #""(\d+(?:\.\d+){0,3}(?:_[0-9]+)?)""#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }
        let range = NSRange(location: 0, length: (output as NSString).length)
        guard
            let match = regex.firstMatch(in: output, range: range),
            match.numberOfRanges > 1
        else {
            return nil
        }
        let ns = output as NSString
        let raw = ns.substring(with: match.range(at: 1))
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func parseVersionToken(in line: String) -> String? {
        let pattern = #"\b(\d+(?:\.\d+){0,3}(?:_[0-9]+)?)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }
        let range = NSRange(location: 0, length: (line as NSString).length)
        guard
            let match = regex.firstMatch(in: line, range: range),
            match.numberOfRanges > 1
        else {
            return nil
        }
        return (line as NSString).substring(with: match.range(at: 1))
    }

    static func isJavaVersionGreater(_ lhs: String, _ rhs: String) -> Bool {
        let left = lhs.replacingOccurrences(of: "_", with: ".").split(separator: ".").compactMap { Int($0) }
        let right = rhs.replacingOccurrences(of: "_", with: ".").split(separator: ".").compactMap { Int($0) }

        for idx in 0..<max(left.count, right.count) {
            let lv = idx < left.count ? left[idx] : 0
            let rv = idx < right.count ? right[idx] : 0
            if lv != rv {
                return lv > rv
            }
        }
        return lhs > rhs
    }

    static func singleQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\"'\"'"))'"
    }
}
