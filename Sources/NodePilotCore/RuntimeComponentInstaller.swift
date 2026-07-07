import Foundation
import CryptoKit

public protocol RuntimeComponentInstalling: Sendable {
    func listAvailableNodeVersions(ltsOnly: Bool) throws -> [NodeDownloadCandidate]
    func installNode(version: String, progress: (@Sendable (String) -> Void)?) throws -> NodeInstallation
    func uninstallManagedNode(installation: NodeInstallation) throws
    func listAvailableJavaVersions(ltsOnly: Bool) throws -> [JavaDownloadCandidate]
    func installJava(featureVersion: Int, progress: (@Sendable (String) -> Void)?) throws -> JavaInstallation
    func uninstallManagedJava(homePath: String) throws
    func listAvailablePythonVersions(stableOnly: Bool) throws -> [PythonDownloadCandidate]
    func installPython(version: String, progress: (@Sendable (String) -> Void)?) throws -> PythonInstallation
    func uninstallManagedPython(homePath: String) throws
}

public struct RuntimeComponentInstaller: RuntimeComponentInstalling, Sendable {
    private let shellRunner: any ShellCommandRunning
    private let environment: [String: String]

    public init(
        shellRunner: any ShellCommandRunning = ShellCommandRunner(),
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.shellRunner = shellRunner
        self.environment = environment
    }

    public func listAvailableNodeVersions(ltsOnly: Bool = false) throws -> [NodeDownloadCandidate] {
        try latestNodeReleasePerMajor(
            from: nodeDistReleases().filter { release in
                release.files.contains(Self.nodeIndexFileToken) && (!ltsOnly || release.ltsName != nil)
            }
        ).map { release in
            NodeDownloadCandidate(version: release.normalizedVersion, lts: release.ltsName)
        }
    }

    public func installNode(version: String, progress: (@Sendable (String) -> Void)?) throws -> NodeInstallation {
        let resolvedVersion = try resolveNodeVersion(version)
        let archiveName = "node-v\(resolvedVersion)-\(Self.nodeArchiveFileToken).tar.xz"
        let baseURL = "https://nodejs.org/dist/v\(resolvedVersion)"
        let archiveURL = try Self.url("\(baseURL)/\(archiveName)")
        let checksumURL = try Self.url("\(baseURL)/SHASUMS256.txt")
        let workDirectory = try makeWorkDirectory(prefix: "node-\(resolvedVersion)")
        defer { try? FileManager.default.removeItem(at: workDirectory) }

        let archiveURLOnDisk = workDirectory.appendingPathComponent(archiveName)
        progress?("正在下载 Node \(resolvedVersion) 0%")
        try downloadFile(
            from: archiveURL,
            to: archiveURLOnDisk,
            label: "正在下载 Node \(resolvedVersion)",
            progress: progress
        )

        progress?("正在安装 Node \(resolvedVersion)：校验 70%")
        let checksumText = try fetchString(from: checksumURL)
        let expectedChecksum = try checksum(named: archiveName, in: checksumText)
        try verifySHA256(fileURL: archiveURLOnDisk, expectedHex: expectedChecksum)

        progress?("正在安装 Node \(resolvedVersion)：解压 85%")
        let extractDirectory = workDirectory.appendingPathComponent("extract", isDirectory: true)
        try FileManager.default.createDirectory(at: extractDirectory, withIntermediateDirectories: true)
        try extractArchive(archiveURLOnDisk, to: extractDirectory)

        let extractedRoot = extractDirectory.appendingPathComponent("node-v\(resolvedVersion)-\(Self.nodeArchiveFileToken)", isDirectory: true)
        guard FileManager.default.isExecutableFile(atPath: extractedRoot.appendingPathComponent("bin/node").path) else {
            throw RuntimeComponentInstallerError.runtimeArchiveInvalid(message: "Node archive did not contain bin/node.")
        }

        let target = Self.managedNodeRoot().appendingPathComponent(resolvedVersion, isDirectory: true)
        progress?("正在安装 Node \(resolvedVersion)：写入 95%")
        try replaceManagedDirectory(source: extractedRoot, target: target)
        progress?("Node \(resolvedVersion) 安装完成 100%")
        return NodeInstallation(
            version: resolvedVersion,
            installPath: target.path,
            executablePath: target.appendingPathComponent("bin/node").path
        )
    }

    public func uninstallManagedNode(installation: NodeInstallation) throws {
        let installURL = URL(fileURLWithPath: installation.installPath).standardizedFileURL
        guard Self.isManagedNodePath(installURL.path) else {
            throw RuntimeComponentInstallerError.unmanagedRuntimeRemovalUnsupported(path: installation.installPath)
        }
        guard FileManager.default.fileExists(atPath: installURL.path) else {
            throw RuntimeComponentInstallerError.runtimeNotInstalled(path: installation.installPath)
        }
        try FileManager.default.removeItem(at: installURL)
    }

    public func listAvailableJavaVersions(ltsOnly: Bool = false) throws -> [JavaDownloadCandidate] {
        let releases = try fetchJSON(Self.adoptiumAvailableReleasesURL, as: AdoptiumAvailableReleases.self)
        let featureVersions = ltsOnly
            ? releases.availableLTSReleases.sorted(by: >)
            : Array(Set(releases.availableLTSReleases + [releases.mostRecentFeatureRelease]))
            .sorted(by: >)
        return try featureVersions.compactMap { featureVersion in
            try latestTemurinCandidate(featureVersion: featureVersion)
        }
    }

    public func installJava(featureVersion: Int, progress: (@Sendable (String) -> Void)?) throws -> JavaInstallation {
        guard featureVersion > 0 else {
            throw RuntimeComponentInstallerError.invalidJavaFeatureVersion(String(featureVersion))
        }
        let candidate = try latestTemurinCandidate(featureVersion: featureVersion)
        guard let candidate else {
            throw RuntimeComponentInstallerError.javaCandidateNotFound(String(featureVersion))
        }

        let archiveURL = try Self.url(candidate.downloadURL)
        let workDirectory = try makeWorkDirectory(prefix: "jdk-\(featureVersion)")
        defer { try? FileManager.default.removeItem(at: workDirectory) }

        let archiveURLOnDisk = workDirectory.appendingPathComponent(candidate.packageName)
        progress?("正在下载 Temurin JDK \(candidate.version) 0%")
        try downloadFile(
            from: archiveURL,
            to: archiveURLOnDisk,
            label: "正在下载 Temurin JDK \(candidate.version)",
            progress: progress
        )

        if let checksum = candidate.checksum, !checksum.isEmpty {
            progress?("正在安装 Temurin JDK \(candidate.version)：校验 70%")
            try verifySHA256(fileURL: archiveURLOnDisk, expectedHex: checksum)
        }

        progress?("正在安装 Temurin JDK \(candidate.version)：解压 85%")
        let extractDirectory = workDirectory.appendingPathComponent("extract", isDirectory: true)
        try FileManager.default.createDirectory(at: extractDirectory, withIntermediateDirectories: true)
        try extractArchive(archiveURLOnDisk, to: extractDirectory)

        guard let extractedHome = findJavaHome(in: extractDirectory) else {
            throw RuntimeComponentInstallerError.runtimeArchiveInvalid(message: "JDK archive did not contain a Java home.")
        }

        let sanitizedVersion = Self.sanitizePathComponent(candidate.version)
        let targetBundle = Self.managedJavaRoot().appendingPathComponent("temurin-\(sanitizedVersion).jdk", isDirectory: true)
        let targetHome = targetBundle.appendingPathComponent("Contents/Home", isDirectory: true)
        progress?("正在安装 Temurin JDK \(candidate.version)：写入 95%")
        try replaceManagedDirectory(source: extractedHome, target: targetHome)
        let version = versionFromJavaHome(targetHome.path) ?? candidate.version
        progress?("Temurin JDK \(candidate.version) 安装完成 100%")
        return JavaInstallation(version: version, homePath: targetHome.path)
    }

    public func uninstallManagedJava(homePath: String) throws {
        let homeURL = URL(fileURLWithPath: homePath).standardizedFileURL
        guard Self.isManagedJavaHomePath(homeURL.path) else {
            throw RuntimeComponentInstallerError.unmanagedRuntimeRemovalUnsupported(path: homePath)
        }
        let bundleURL = homeURL.deletingLastPathComponent().deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: bundleURL.path) else {
            throw RuntimeComponentInstallerError.runtimeNotInstalled(path: homePath)
        }
        try FileManager.default.removeItem(at: bundleURL)
    }

    public func listAvailablePythonVersions(stableOnly: Bool = true) throws -> [PythonDownloadCandidate] {
        let releases = try pythonFtpReleases().filter { release in
            release.isSupportedOnModernMac && (!stableOnly || release.isStable)
        }
        let latestReleases = latestPythonReleasePerFeature(from: releases)
        return try latestReleases.compactMap { release in
            try pythonSourceCandidate(version: release.version)
        }
    }

    public func installPython(version: String, progress: (@Sendable (String) -> Void)?) throws -> PythonInstallation {
        let resolvedVersion = try resolvePythonVersion(version)
        let candidate = try pythonSourceCandidate(version: resolvedVersion)
        guard let candidate else {
            throw RuntimeComponentInstallerError.pythonCandidateNotFound(version)
        }

        let archiveURL = try Self.url(candidate.downloadURL)
        let workDirectory = try makeWorkDirectory(prefix: "python-\(resolvedVersion)")
        defer { try? FileManager.default.removeItem(at: workDirectory) }

        let archiveURLOnDisk = workDirectory.appendingPathComponent(candidate.packageName)
        progress?("正在下载 Python \(resolvedVersion) 0%")
        try downloadFile(
            from: archiveURL,
            to: archiveURLOnDisk,
            label: "正在下载 Python \(resolvedVersion)",
            progress: progress
        )

        progress?("正在安装 Python \(resolvedVersion)：解压 55%")
        let extractDirectory = workDirectory.appendingPathComponent("extract", isDirectory: true)
        try FileManager.default.createDirectory(at: extractDirectory, withIntermediateDirectories: true)
        try extractArchive(archiveURLOnDisk, to: extractDirectory)

        let sourceDirectory = extractDirectory.appendingPathComponent("Python-\(resolvedVersion)", isDirectory: true)
        guard FileManager.default.fileExists(atPath: sourceDirectory.appendingPathComponent("configure").path) else {
            throw RuntimeComponentInstallerError.runtimeArchiveInvalid(message: "Python source archive did not contain configure.")
        }

        let target = Self.managedPythonRoot().appendingPathComponent(resolvedVersion, isDirectory: true)
        if FileManager.default.fileExists(atPath: target.path) {
            try FileManager.default.removeItem(at: target)
        }
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)

        progress?("正在安装 Python \(resolvedVersion)：配置 65%")
        try runPythonBuildCommand(
            "cd \(Self.shellSingleQuoted(sourceDirectory.path)) && ./configure --prefix=\(Self.shellSingleQuoted(target.path)) --enable-shared",
            stage: "配置 Python \(resolvedVersion)"
        )

        progress?("正在安装 Python \(resolvedVersion)：编译 75%")
        try runPythonBuildCommand(
            "cd \(Self.shellSingleQuoted(sourceDirectory.path)) && /usr/bin/make -j\(Self.processorCount)",
            stage: "编译 Python \(resolvedVersion)"
        )

        progress?("正在安装 Python \(resolvedVersion)：写入 95%")
        try runPythonBuildCommand(
            "cd \(Self.shellSingleQuoted(sourceDirectory.path)) && /usr/bin/make install",
            stage: "安装 Python \(resolvedVersion)"
        )

        guard FileManager.default.isExecutableFile(atPath: target.appendingPathComponent("bin/python3").path) else {
            throw RuntimeComponentInstallerError.runtimeArchiveInvalid(message: "Python install did not contain bin/python3.")
        }

        let installedVersion = versionFromPythonHome(target.path) ?? resolvedVersion
        progress?("Python \(installedVersion) 安装完成 100%")
        return PythonInstallation(
            version: installedVersion,
            homePath: target.path,
            executablePath: target.appendingPathComponent("bin/python3").path
        )
    }

    public func uninstallManagedPython(homePath: String) throws {
        let homeURL = URL(fileURLWithPath: homePath).standardizedFileURL
        guard Self.isManagedPythonHomePath(homeURL.path) else {
            throw RuntimeComponentInstallerError.unmanagedRuntimeRemovalUnsupported(path: homePath)
        }
        guard FileManager.default.fileExists(atPath: homeURL.path) else {
            throw RuntimeComponentInstallerError.runtimeNotInstalled(path: homePath)
        }
        try FileManager.default.removeItem(at: homeURL)
    }

    func resolveNodeVersion(_ requestedVersion: String) throws -> String {
        let normalized = normalizeInstallSpec(requestedVersion)
        guard !normalized.isEmpty else {
            throw RuntimeComponentInstallerError.invalidNodeVersion(requestedVersion)
        }
        if NodeInstallationDetector.normalizeVersion(normalized) != nil {
            return normalized
        }

        let releases = try nodeDistReleases()
        if normalized == "latest" || normalized == "node" {
            guard let latest = releases.first(where: { $0.files.contains(Self.nodeIndexFileToken) }) else {
                throw RuntimeComponentInstallerError.nodeVersionNotFound(requestedVersion)
            }
            return latest.normalizedVersion
        }
        guard let major = Int(normalized) else {
            throw RuntimeComponentInstallerError.invalidNodeVersion(requestedVersion)
        }
        guard let match = releases.first(where: {
            $0.normalizedVersion.split(separator: ".").first.flatMap { Int($0) } == major
                && $0.files.contains(Self.nodeIndexFileToken)
        }) else {
            throw RuntimeComponentInstallerError.nodeVersionNotFound(requestedVersion)
        }
        return match.normalizedVersion
    }

    fileprivate func nodeDistReleases() throws -> [NodeDistRelease] {
        try fetchJSON(Self.nodeDistIndexURL, as: [NodeDistRelease].self)
    }

    fileprivate func latestNodeReleasePerMajor(from releases: [NodeDistRelease]) -> [NodeDistRelease] {
        var seenMajors = Set<Int>()
        var latestReleases: [NodeDistRelease] = []

        for release in releases {
            guard let major = release.majorVersion, seenMajors.insert(major).inserted else {
                continue
            }
            latestReleases.append(release)
        }

        return latestReleases
    }

    func latestTemurinCandidate(featureVersion: Int) throws -> JavaDownloadCandidate? {
        let url = try Self.url(
            "https://api.adoptium.net/v3/assets/latest/\(featureVersion)/hotspot"
                + "?architecture=\(Self.adoptiumArchitecture)"
                + "&heap_size=normal"
                + "&image_type=jdk"
                + "&jvm_impl=hotspot"
                + "&os=mac"
                + "&project=jdk"
                + "&vendor=eclipse"
        )
        let assets = try fetchJSON(url, as: [AdoptiumAsset].self)
        guard let asset = assets.first, let package = asset.binary.package else {
            return nil
        }
        return JavaDownloadCandidate(
            featureVersion: featureVersion,
            version: asset.version.openjdkVersion ?? asset.releaseName,
            vendor: "Temurin",
            packageName: package.name,
            downloadURL: package.link,
            checksum: package.checksum
        )
    }

    func resolvePythonVersion(_ requestedVersion: String) throws -> String {
        let normalized = normalizeInstallSpec(requestedVersion)
        guard !normalized.isEmpty else {
            throw RuntimeComponentInstallerError.invalidPythonVersion(requestedVersion)
        }
        if PythonRuntimeDetector.normalizeVersion(normalized) != nil {
            return normalized
        }

        let releases = try pythonFtpReleases().filter { $0.isStable && $0.isSupportedOnModernMac }
        if normalized == "latest" || normalized == "python" || normalized == "python3" {
            guard let latest = releases.first else {
                throw RuntimeComponentInstallerError.pythonVersionNotFound(requestedVersion)
            }
            return latest.version
        }

        let requestedParts = normalized.split(separator: ".").compactMap { Int($0) }
        guard !requestedParts.isEmpty else {
            throw RuntimeComponentInstallerError.invalidPythonVersion(requestedVersion)
        }
        guard let match = releases.first(where: { release in
            let parts = release.version.split(separator: ".").compactMap { Int($0) }
            return requestedParts.enumerated().allSatisfy { index, value in
                index < parts.count && parts[index] == value
            }
        }) else {
            throw RuntimeComponentInstallerError.pythonVersionNotFound(requestedVersion)
        }
        return match.version
    }

    fileprivate func pythonFtpReleases() throws -> [PythonFtpRelease] {
        let html = try fetchString(from: Self.pythonFtpIndexURL)
        let pattern = #"href="(\d+\.\d+(?:\.\d+)?(?:[a-z]+\d*)?)/""#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        let matches = regex.matches(in: html, range: range)
        var seen = Set<String>()
        let releases = matches.compactMap { match -> PythonFtpRelease? in
            guard let versionRange = Range(match.range(at: 1), in: html) else {
                return nil
            }
            let version = String(html[versionRange])
            guard seen.insert(version).inserted else {
                return nil
            }
            return PythonFtpRelease(version: version)
        }
        return releases.sorted { PythonRuntimeDetector.isPythonVersionGreater($0.version, $1.version) }
    }

    fileprivate func latestPythonReleasePerFeature(from releases: [PythonFtpRelease]) -> [PythonFtpRelease] {
        var seenFeatures = Set<String>()
        var latestReleases: [PythonFtpRelease] = []

        for release in releases {
            guard let feature = release.featureVersion, seenFeatures.insert(feature).inserted else {
                continue
            }
            latestReleases.append(release)
        }
        return latestReleases
    }

    func pythonSourceCandidate(version: String) throws -> PythonDownloadCandidate? {
        let baseURL = "https://www.python.org/ftp/python/\(version)"
        let archiveName = "Python-\(version).tar.xz"
        let html = try fetchString(from: Self.url("\(baseURL)/"))
        guard html.contains(archiveName) else {
            return nil
        }
        return PythonDownloadCandidate(
            version: version,
            packageName: archiveName,
            downloadURL: "\(baseURL)/\(archiveName)"
        )
    }

    func runPythonBuildCommand(_ command: String, stage: String) throws {
        let result = try shellRunner.runShell(command, environment: environment)
        guard result.succeeded else {
            throw RuntimeComponentInstallerError.runtimeArchiveInvalid(message: "\(stage) failed: \(preferErrorOutput(result))")
        }
    }

    func normalizeInstallSpec(_ version: String) -> String {
        let compact = version.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
        if compact.hasPrefix("v"), compact.count > 1 {
            return String(compact.dropFirst())
        }
        return compact
    }

    func makeWorkDirectory(prefix: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("envpilot-runtime-\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    func fetchJSON<T: Decodable>(_ url: URL, as type: T.Type) throws -> T {
        let data = try fetchData(from: url)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw RuntimeComponentInstallerError.runtimeDownloadFailed(
                url: url.absoluteString,
                message: error.localizedDescription
            )
        }
    }

    func fetchString(from url: URL) throws -> String {
        let data = try fetchData(from: url)
        guard let string = String(data: data, encoding: .utf8) else {
            throw RuntimeComponentInstallerError.runtimeDownloadFailed(
                url: url.absoluteString,
                message: "Downloaded data is not valid UTF-8."
            )
        }
        return string
    }

    func fetchData(from url: URL) throws -> Data {
        let semaphore = DispatchSemaphore(value: 0)
        let state = RuntimeDownloadState<Data>()
        URLSession.shared.dataTask(with: url) { data, response, error in
            state.complete(Self.validateDownloadedData(data: data, response: response, error: error, url: url))
            semaphore.signal()
        }.resume()
        semaphore.wait()
        return try state.result().get()
    }

    func downloadFile(
        from url: URL,
        to destination: URL,
        label: String,
        progress: (@Sendable (String) -> Void)?
    ) throws {
        let semaphore = DispatchSemaphore(value: 0)
        let state = RuntimeDownloadState<Void>()
        let delegate = RuntimeFileDownloadDelegate(
            url: url,
            destination: destination,
            label: label,
            progress: progress,
            state: state
        ) {
            semaphore.signal()
        }
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: queue)
        session.downloadTask(with: url).resume()
        semaphore.wait()
        session.finishTasksAndInvalidate()
        return try state.result().get()
    }

    static func validateDownloadedData(
        data: Data?,
        response: URLResponse?,
        error: Error?,
        url: URL
    ) -> Result<Data, Error> {
        if let error {
            return .failure(RuntimeComponentInstallerError.runtimeDownloadFailed(url: url.absoluteString, message: error.localizedDescription))
        }
        if let httpResponse = response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            return .failure(RuntimeComponentInstallerError.runtimeDownloadFailed(url: url.absoluteString, message: "HTTP \(httpResponse.statusCode)"))
        }
        guard let data else {
            return .failure(RuntimeComponentInstallerError.runtimeDownloadFailed(url: url.absoluteString, message: "No data returned."))
        }
        return .success(data)
    }

    func checksum(named fileName: String, in checksums: String) throws -> String {
        for line in checksums.split(whereSeparator: \.isNewline).map(String.init) {
            let columns = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            if columns.count >= 2, columns[1] == fileName {
                return columns[0]
            }
        }
        throw RuntimeComponentInstallerError.runtimeArchiveInvalid(message: "Checksum not found for \(fileName).")
    }

    func verifySHA256(fileURL: URL, expectedHex: String) throws {
        let data = try Data(contentsOf: fileURL)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard digest.lowercased() == expectedHex.lowercased() else {
            throw RuntimeComponentInstallerError.runtimeChecksumMismatch(file: fileURL.lastPathComponent)
        }
    }

    func extractArchive(_ archiveURL: URL, to destination: URL) throws {
        let result = try shellRunner.run(
            "/usr/bin/tar",
            arguments: ["-xf", archiveURL.path, "-C", destination.path],
            environment: environment
        )
        guard result.succeeded else {
            throw RuntimeComponentInstallerError.runtimeArchiveInvalid(message: preferErrorOutput(result))
        }
    }

    func replaceManagedDirectory(source: URL, target: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: target.path) {
            try fileManager.removeItem(at: target)
        }
        try fileManager.moveItem(at: source, to: target)
    }

    func findJavaHome(in root: URL) -> URL? {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        for case let url as URL in enumerator {
            let javaBinary = url.appendingPathComponent("bin/java").path
            if FileManager.default.isExecutableFile(atPath: javaBinary) {
                return url
            }
        }
        return nil
    }

    func versionFromJavaHome(_ homePath: String) -> String? {
        let javaBinary = (homePath as NSString).appendingPathComponent("bin/java")
        let result = try? shellRunner.run(
            javaBinary,
            arguments: ["-version"],
            environment: environment
        )
        guard let result else {
            return nil
        }
        return JavaRuntimeDetector.parseJavaVersion(
            fromJavaVersionOutput: [result.standardOutput, result.standardError].joined(separator: "\n")
        )
    }

    func versionFromPythonHome(_ homePath: String) -> String? {
        let pythonBinary = (homePath as NSString).appendingPathComponent("bin/python3")
        let result = try? shellRunner.run(
            pythonBinary,
            arguments: ["--version"],
            environment: environment
        )
        guard let result else {
            return nil
        }
        return PythonRuntimeDetector.normalizeVersion(
            [result.standardOutput, result.standardError].joined(separator: "\n")
        )
    }

    private func preferErrorOutput(_ result: ShellCommandResult) -> String {
        let stderr = result.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
        if !stderr.isEmpty {
            return stderr
        }
        let stdout = result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        return stdout.isEmpty ? "Unknown shell error" : stdout
    }

    static let nodeDistIndexURL = URL(string: "https://nodejs.org/dist/index.json")!
    static let adoptiumAvailableReleasesURL = URL(string: "https://api.adoptium.net/v3/info/available_releases")!
    static let pythonFtpIndexURL = URL(string: "https://www.python.org/ftp/python/")!

    static var nodeArchiveFileToken: String {
        #if arch(arm64)
        "darwin-arm64"
        #else
        "darwin-x64"
        #endif
    }

    static var nodeIndexFileToken: String {
        #if arch(arm64)
        "osx-arm64-tar"
        #else
        "osx-x64-tar"
        #endif
    }

    static var adoptiumArchitecture: String {
        #if arch(arm64)
        "aarch64"
        #else
        "x64"
        #endif
    }

    static func managedNodeRoot() -> URL {
        URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent(".envpilot/runtimes/node", isDirectory: true)
    }

    static func managedJavaRoot() -> URL {
        URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent(".envpilot/runtimes/java", isDirectory: true)
    }

    static func managedPythonRoot() -> URL {
        URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent(".envpilot/runtimes/python", isDirectory: true)
    }

    static func isManagedNodePath(_ path: String) -> Bool {
        URL(fileURLWithPath: path).standardizedFileURL.path.hasPrefix(managedNodeRoot().path + "/")
    }

    static func isManagedJavaHomePath(_ path: String) -> Bool {
        URL(fileURLWithPath: path).standardizedFileURL.path.hasPrefix(managedJavaRoot().path + "/")
    }

    static func isManagedPythonHomePath(_ path: String) -> Bool {
        URL(fileURLWithPath: path).standardizedFileURL.path.hasPrefix(managedPythonRoot().path + "/")
    }

    static func sanitizePathComponent(_ value: String) -> String {
        value.map { character in
            character.isLetter || character.isNumber || character == "." || character == "-" || character == "_" ? character : "-"
        }.reduce(into: "") { $0.append($1) }
    }

    static func byteCountText(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.includesCount = true
        return formatter.string(fromByteCount: max(0, bytes))
    }

    static func url(_ value: String) throws -> URL {
        guard let url = URL(string: value) else {
            throw RuntimeComponentInstallerError.invalidDownloadURL(value)
        }
        return url
    }

    static func shellSingleQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\"'\"'"))'"
    }

    static var processorCount: Int {
        max(1, ProcessInfo.processInfo.processorCount)
    }
}

private final class RuntimeDownloadState<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var storedResult: Result<T, Error>?

    func complete(_ result: Result<T, Error>) {
        lock.lock()
        if storedResult == nil {
            storedResult = result
        }
        lock.unlock()
    }

    func result() -> Result<T, Error> {
        lock.lock()
        defer { lock.unlock() }
        return storedResult ?? .failure(RuntimeComponentInstallerError.runtimeDownloadFailed(url: "", message: "Download did not complete."))
    }
}

private final class RuntimeFileDownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let url: URL
    private let destination: URL
    private let label: String
    private let progress: (@Sendable (String) -> Void)?
    private let state: RuntimeDownloadState<Void>
    private let signalCompletion: @Sendable () -> Void
    private let startedAt = Date()
    private var lastProgressUpdate = Date(timeIntervalSince1970: 0)
    private var didMoveDownloadedFile = false

    init(
        url: URL,
        destination: URL,
        label: String,
        progress: (@Sendable (String) -> Void)?,
        state: RuntimeDownloadState<Void>,
        signalCompletion: @escaping @Sendable () -> Void
    ) {
        self.url = url
        self.destination = destination
        self.label = label
        self.progress = progress
        self.state = state
        self.signalCompletion = signalCompletion
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let now = Date()
        guard now.timeIntervalSince(lastProgressUpdate) >= 0.25 || totalBytesWritten == totalBytesExpectedToWrite else {
            return
        }
        lastProgressUpdate = now

        progress?(
            "\(label) \(Self.percentText(written: totalBytesWritten, expected: totalBytesExpectedToWrite)) · \(Self.speedText(bytes: totalBytesWritten, elapsed: now.timeIntervalSince(startedAt)))"
        )
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: location, to: destination)
            didMoveDownloadedFile = true
        } catch {
            state.complete(.failure(RuntimeComponentInstallerError.runtimeDownloadFailed(
                url: url.absoluteString,
                message: error.localizedDescription
            )))
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        defer { signalCompletion() }

        if let error {
            state.complete(.failure(RuntimeComponentInstallerError.runtimeDownloadFailed(
                url: url.absoluteString,
                message: error.localizedDescription
            )))
            return
        }

        if let httpResponse = task.response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            state.complete(.failure(RuntimeComponentInstallerError.runtimeDownloadFailed(
                url: url.absoluteString,
                message: "HTTP \(httpResponse.statusCode)"
            )))
            return
        }

        guard didMoveDownloadedFile else {
            state.complete(.failure(RuntimeComponentInstallerError.runtimeDownloadFailed(
                url: url.absoluteString,
                message: "No file returned."
            )))
            return
        }

        progress?("\(label) 100% · \(Self.speedText(bytes: task.countOfBytesReceived, elapsed: Date().timeIntervalSince(startedAt)))")
        state.complete(.success(()))
    }

    private static func percentText(written: Int64, expected: Int64) -> String {
        guard expected > 0 else {
            return RuntimeComponentInstaller.byteCountText(written)
        }
        let percent = min(100, max(0, Double(written) / Double(expected) * 100))
        return String(format: "%.1f%%", percent)
    }

    private static func speedText(bytes: Int64, elapsed: TimeInterval) -> String {
        guard elapsed > 0 else {
            return "0 B/s"
        }
        return "\(RuntimeComponentInstaller.byteCountText(Int64(Double(bytes) / elapsed)))/s"
    }
}

private struct NodeDistRelease: Decodable {
    let version: String
    let lts: LTSValue
    let files: [String]

    var normalizedVersion: String {
        version.hasPrefix("v") ? String(version.dropFirst()) : version
    }

    var ltsName: String? {
        switch lts {
        case .bool:
            nil
        case .name(let value):
            value
        }
    }

    var majorVersion: Int? {
        normalizedVersion.split(separator: ".").first.flatMap { Int($0) }
    }

    enum CodingKeys: String, CodingKey {
        case version
        case lts
        case files
    }
}

private enum LTSValue: Decodable {
    case bool(Bool)
    case name(String)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else {
            self = .name(try container.decode(String.self))
        }
    }
}

private struct AdoptiumAvailableReleases: Decodable {
    let availableLTSReleases: [Int]
    let mostRecentFeatureRelease: Int

    enum CodingKeys: String, CodingKey {
        case availableLTSReleases = "available_lts_releases"
        case mostRecentFeatureRelease = "most_recent_feature_release"
    }
}

private struct AdoptiumAsset: Decodable {
    let binary: AdoptiumBinary
    let releaseName: String
    let version: AdoptiumVersion

    enum CodingKeys: String, CodingKey {
        case binary
        case releaseName = "release_name"
        case version
    }
}

private struct AdoptiumBinary: Decodable {
    let package: AdoptiumPackage?
}

private struct AdoptiumPackage: Decodable {
    let checksum: String?
    let link: String
    let name: String
}

private struct AdoptiumVersion: Decodable {
    let openjdkVersion: String?

    enum CodingKeys: String, CodingKey {
        case openjdkVersion = "openjdk_version"
    }
}

private struct PythonFtpRelease {
    let version: String

    var isStable: Bool {
        PythonRuntimeDetector.normalizeVersion(version) == version
    }

    var isSupportedOnModernMac: Bool {
        let parts = version.split(separator: ".").compactMap { Int($0) }
        guard parts.count >= 2 else {
            return false
        }
        return parts[0] == 3 && parts[1] >= 8
    }

    var featureVersion: String? {
        let parts = version.split(separator: ".")
        guard parts.count >= 2 else {
            return nil
        }
        return "\(parts[0]).\(parts[1])"
    }
}

public enum RuntimeComponentInstallerError: Error, LocalizedError {
    case invalidDownloadURL(String)
    case runtimeDownloadFailed(url: String, message: String)
    case runtimeArchiveInvalid(message: String)
    case runtimeChecksumMismatch(file: String)
    case runtimeNotInstalled(path: String)
    case unmanagedRuntimeRemovalUnsupported(path: String)
    case invalidNodeVersion(String)
    case nodeVersionNotFound(String)
    case invalidJavaFeatureVersion(String)
    case javaCandidateNotFound(String)
    case invalidPythonVersion(String)
    case pythonVersionNotFound(String)
    case pythonCandidateNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .invalidDownloadURL(let value):
            return "Invalid runtime download URL: \(value)"
        case .runtimeDownloadFailed(let url, let message):
            return "Runtime download failed from \(url): \(message)"
        case .runtimeArchiveInvalid(let message):
            return "Runtime archive is invalid: \(message)"
        case .runtimeChecksumMismatch(let file):
            return "Runtime archive checksum mismatch: \(file)"
        case .runtimeNotInstalled(let path):
            return "Runtime is not installed at \(path)"
        case .unmanagedRuntimeRemovalUnsupported(let path):
            return "ENVPilot can only uninstall runtimes it installed under ~/.envpilot/runtimes: \(path)"
        case .invalidNodeVersion(let version):
            return "Invalid Node version: \(version)"
        case .nodeVersionNotFound(let version):
            return "Node version is not available for this Mac: \(version)"
        case .invalidJavaFeatureVersion(let version):
            return "Invalid JDK feature version: \(version)"
        case .javaCandidateNotFound(let version):
            return "Temurin JDK is not available for this Mac: \(version)"
        case .invalidPythonVersion(let version):
            return "Invalid Python version: \(version)"
        case .pythonVersionNotFound(let version):
            return "Python version is not available from python.org: \(version)"
        case .pythonCandidateNotFound(let version):
            return "Python source package is not available from python.org: \(version)"
        }
    }
}
