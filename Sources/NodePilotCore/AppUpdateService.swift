import Foundation

// MARK: - 版本号

/// 语义化版本号。容忍 `v` 前缀、`0.6` 这类缺段写法、以及 `-dev` 预发布后缀与
/// `+build` 构建元数据；无法解析时返回 `nil`（例如开发构建的 `dev`）。
public struct AppVersion: Comparable, Sendable, CustomStringConvertible {
    public let raw: String
    /// 数字段落。`0.6.4` → `[0, 6, 4]`。
    public let numbers: [Int]
    /// 预发布标识。`0.6.5-beta.1` → `["beta", "1"]`。
    public let prerelease: [String]

    public init?(_ text: String) {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            return nil
        }
        if value.hasPrefix("v") || value.hasPrefix("V") {
            value.removeFirst()
        }
        // 构建元数据不参与比较，直接丢掉。
        if let plus = value.firstIndex(of: "+") {
            value = String(value[value.startIndex..<plus])
        }
        // Homebrew 等工具可能输出 git describe 版本（7.0.6-6-g1d86792）。
        // 这不是 SemVer 预发布版本，应比较到 tag 版本本身。
        if let gitDescribeRange = value.range(
            of: #"-\d+-g[0-9A-Fa-f]+(?:-dirty)?$"#,
            options: .regularExpression
        ) {
            value.removeSubrange(gitDescribeRange)
        }
        var prerelease: [String] = []
        if let dash = value.firstIndex(of: "-") {
            prerelease = value[value.index(after: dash)...].split(separator: ".").map(String.init)
            value = String(value[value.startIndex..<dash])
        }
        var numbers: [Int] = []
        for part in value.split(separator: ".", omittingEmptySubsequences: false) {
            let digits = part.prefix { $0.isNumber }
            guard !digits.isEmpty else {
                return nil
            }
            numbers.append(Int(digits) ?? 0)
        }
        guard !numbers.isEmpty else {
            return nil
        }
        self.raw = text
        self.numbers = numbers
        self.prerelease = prerelease.filter { !$0.isEmpty }
    }

    public var description: String { raw }

    public var isPrerelease: Bool { !prerelease.isEmpty }

    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let count = max(lhs.numbers.count, rhs.numbers.count)
        for index in 0..<count {
            let left = index < lhs.numbers.count ? lhs.numbers[index] : 0
            let right = index < rhs.numbers.count ? rhs.numbers[index] : 0
            if left != right {
                return left < right
            }
        }
        // 数字相同：正式版 > 预发布版。
        if lhs.prerelease.isEmpty || rhs.prerelease.isEmpty {
            return !lhs.prerelease.isEmpty && rhs.prerelease.isEmpty
        }
        for index in 0..<max(lhs.prerelease.count, rhs.prerelease.count) {
            guard index < lhs.prerelease.count else {
                return true
            }
            guard index < rhs.prerelease.count else {
                return false
            }
            let left = lhs.prerelease[index]
            let right = rhs.prerelease[index]
            if left == right {
                continue
            }
            switch (Int(left), Int(right)) {
            case let (l?, r?):
                return l < r
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            default:
                return left < right
            }
        }
        return false
    }

    public static func == (lhs: AppVersion, rhs: AppVersion) -> Bool {
        !(lhs < rhs) && !(rhs < lhs)
    }
}

// MARK: - Release

/// 一次 GitHub Release，只保留更新流程需要的字段。
public struct AppRelease: Equatable, Sendable {
    public let tag: String
    /// 去掉 `v` 前缀的版本号，和 `CFBundleShortVersionString` 对齐。
    public let version: String
    public let name: String
    public let notes: String
    public let pageURL: URL?
    /// `ENVPilot.zip`（含完整 `.app`，用于自动更新）。
    public let archiveURL: URL?
    /// `ENVPilot.dmg`（无法自更新时的手动下载）。
    public let diskImageURL: URL?
    public let publishedAt: Date?
    public let isPrerelease: Bool

    public init(
        tag: String,
        version: String,
        name: String,
        notes: String,
        pageURL: URL?,
        archiveURL: URL?,
        diskImageURL: URL?,
        publishedAt: Date?,
        isPrerelease: Bool
    ) {
        self.tag = tag
        self.version = version
        self.name = name
        self.notes = notes
        self.pageURL = pageURL
        self.archiveURL = archiveURL
        self.diskImageURL = diskImageURL
        self.publishedAt = publishedAt
        self.isPrerelease = isPrerelease
    }

    public var versionValue: AppVersion? { AppVersion(version) }
}

// MARK: - 检查结果

public enum AppUpdateCheck: Equatable, Sendable {
    case upToDate(current: String, latest: String)
    case updateAvailable(AppRelease)

    public var release: AppRelease? {
        guard case .updateAvailable(let release) = self else {
            return nil
        }
        return release
    }

    public var isUpdateAvailable: Bool { release != nil }

    /// 当前版本无法解析（开发构建）时一律当作「有更新」，方便本地验证整条链路。
    public static func evaluate(current: String, release: AppRelease) -> AppUpdateCheck {
        guard let currentVersion = AppVersion(current), let latest = release.versionValue else {
            return .updateAvailable(release)
        }
        guard currentVersion < latest else {
            return .upToDate(current: current, latest: release.version)
        }
        return .updateAvailable(release)
    }
}

// MARK: - 安装方式

/// 一键更新把新版放到哪里。运行位置决定了能不能原地替换。
public enum AppUpdateInstallMode: Equatable, Sendable {
    /// 覆盖当前运行的这个 `.app`（`~/Applications`、`/Applications`、本地构建产物）。
    case replaceInPlace(URL)
    /// 当前 app 在只读位置（DMG、App Translocation 随机路径），装到「应用程序」目录。
    case installIntoApplications(URL)
    /// 不是打包应用（`swift run`），只能手动下载。
    case manualDownloadOnly(reason: String)

    public var destination: URL? {
        switch self {
        case .replaceInPlace(let url), .installIntoApplications(let url):
            return url
        case .manualDownloadOnly:
            return nil
        }
    }

    public var canSelfUpdate: Bool { destination != nil }

    public var manualReason: String? {
        guard case .manualDownloadOnly(let reason) = self else {
            return nil
        }
        return reason
    }
}

/// 已经下载并校验通过、等待替换的新版 app。
public struct StagedAppUpdate: Sendable {
    public let release: AppRelease
    /// 暂存目录里的新版 `ENVPilot.app`。
    public let appURL: URL
    public let workDirectory: URL

    public init(release: AppRelease, appURL: URL, workDirectory: URL) {
        self.release = release
        self.appURL = appURL
        self.workDirectory = workDirectory
    }
}

// MARK: - 进度

/// 下载/校验进度。`fraction` 为 `nil` 表示「进行中但比例未知」。
public struct AppUpdateProgress: Equatable, Sendable {
    public let message: String
    public let fraction: Double?

    public init(message: String, fraction: Double? = nil) {
        self.message = message
        self.fraction = fraction
    }
}

// MARK: - 错误

public enum AppUpdateError: LocalizedError {
    case network(url: String, message: String)
    case releaseNotFound(String)
    case missingArchive(String)
    case archiveInvalid(String)
    case stagedAppInvalid(String)
    case selfUpdateUnavailable(String)
    case installFailed(String)

    public var errorDescription: String? {
        switch self {
        case .network(let url, let message):
            return "无法访问 \(url)：\(message)"
        case .releaseNotFound(let message):
            return "没有找到可用的发布版本：\(message)"
        case .missingArchive(let version):
            return "\(version) 的发布里没有可用的下载文件。"
        case .archiveInvalid(let message):
            return "下载的更新包无法解压：\(message)"
        case .stagedAppInvalid(let message):
            return "更新包校验失败：\(message)"
        case .selfUpdateUnavailable(let message):
            return "当前运行位置不支持自动更新：\(message)"
        case .installFailed(let message):
            return "安装更新失败：\(message)"
        }
    }
}

// MARK: - 服务

/// 检查 GitHub 上的最新发布并完成一键更新。
///
/// 查询走 GitHub Releases API（未鉴权，60 次/小时）；API 不可用时退回
/// `releases/latest` 的 302 Location 拿 tag，再按发布流水线的固定文件名拼下载地址。
/// 下载固定取 `ENVPilot.zip`（`.app` 包），解压后用 `ditto` 替换当前运行的 app。
public struct AppUpdateService: Sendable {
    public struct Configuration: Sendable {
        public var owner: String
        public var repository: String
        /// 期望的 `CFBundleIdentifier`，用来确认下载的确实是自己。
        public var bundleIdentifier: String
        public var archiveAssetName: String
        public var diskImageAssetName: String
        /// 下载与解压的根目录。
        public var stagingRoot: URL
        /// 当前版本（`CFBundleShortVersionString`），取不到时是 `dev`。
        public var currentVersion: String
        /// 当前运行的 `.app`；不是打包应用时为 `nil`。
        public var currentBundleURL: URL?
        /// 只读位置运行时的落点，默认 `~/Applications`。
        public var applicationsDirectory: URL
        /// 无法自更新时 dmg 的落点，默认 `~/Downloads`。
        public var downloadsDirectory: URL
        /// 本地安装复制出去的 helper，自更新后一并刷新。
        public var installedHelperPath: URL?

        public init(
            owner: String = "imi4u36d",
            repository: String = "ENVPilot",
            bundleIdentifier: String = "com.envpilot.app",
            archiveAssetName: String = "ENVPilot.zip",
            diskImageAssetName: String = "ENVPilot.dmg",
            stagingRoot: URL,
            currentVersion: String,
            currentBundleURL: URL?,
            applicationsDirectory: URL,
            downloadsDirectory: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads", isDirectory: true),
            installedHelperPath: URL? = nil
        ) {
            self.owner = owner
            self.repository = repository
            self.bundleIdentifier = bundleIdentifier
            self.archiveAssetName = archiveAssetName
            self.diskImageAssetName = diskImageAssetName
            self.stagingRoot = stagingRoot
            self.currentVersion = currentVersion
            self.currentBundleURL = currentBundleURL
            self.applicationsDirectory = applicationsDirectory
            self.downloadsDirectory = downloadsDirectory
            self.installedHelperPath = installedHelperPath
        }

        /// 从当前进程的真实环境推导配置。`ENVPILOT_UPDATE_STAGING_ROOT` 可以改写暂存
        /// 目录，离线验证与测试用得上。
        public static func live(bundle: Bundle = .main) -> Configuration {
            let fileManager = FileManager.default
            let environment = ProcessInfo.processInfo.environment
            let home = fileManager.homeDirectoryForCurrentUser
            let defaultStaging = (fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first ?? fileManager.temporaryDirectory)
                .appendingPathComponent("ENVPilot/Updates", isDirectory: true)
            let stagingRoot = environment["ENVPILOT_UPDATE_STAGING_ROOT"].flatMap { value -> URL? in
                guard !value.isEmpty else { return nil }
                return URL(fileURLWithPath: (value as NSString).expandingTildeInPath, isDirectory: true)
            } ?? defaultStaging

            let bundleURL = bundle.bundleURL.standardizedFileURL

            return Configuration(
                stagingRoot: stagingRoot,
                currentVersion: bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev",
                currentBundleURL: bundleURL.pathExtension == "app" ? bundleURL : nil,
                applicationsDirectory: home.appendingPathComponent("Applications", isDirectory: true),
                installedHelperPath: home.appendingPathComponent(".local/bin/envpilot-helper")
            )
        }
    }

    private let configuration: Configuration
    private let shellRunner: any ShellCommandRunning
    private let environment: [String: String]

    public init(
        configuration: Configuration,
        shellRunner: any ShellCommandRunning = ShellCommandRunner(),
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.configuration = configuration
        self.shellRunner = shellRunner
        self.environment = environment
    }

    public var currentVersion: String { configuration.currentVersion }

    // MARK: 安装方式

    /// 决定一键更新落点。三条规则：
    /// 1. 不是 `.app` → 只能手动下载；
    /// 2. app 在 DMG / App Translocation 的随机只读路径 → 装到「应用程序」目录；
    /// 3. 其余情况原地替换，父目录不可写时退回「应用程序」目录。
    public func installMode(fileManager: FileManager = .default) -> AppUpdateInstallMode {
        guard let bundleURL = configuration.currentBundleURL, bundleURL.pathExtension == "app" else {
            return .manualDownloadOnly(reason: "当前不是打包应用，请下载 dmg 手动安装。")
        }
        let path = bundleURL.standardizedFileURL.path
        let applicationsFallback = configuration.applicationsDirectory.appendingPathComponent("ENVPilot.app")

        let isReadOnlyLocation = path.contains("/AppTranslocation/") || path.hasPrefix("/Volumes/")
        if !isReadOnlyLocation, fileManager.isWritableFile(atPath: bundleURL.deletingLastPathComponent().path) {
            return .replaceInPlace(bundleURL)
        }
        let fallbackParent = applicationsFallback.deletingLastPathComponent()
        if fileManager.isWritableFile(atPath: fallbackParent.path) || (try? fileManager.createDirectory(at: fallbackParent, withIntermediateDirectories: true)) != nil {
            return .installIntoApplications(applicationsFallback)
        }
        return .manualDownloadOnly(reason: "没有可写入的安装目录。")
    }

    // MARK: 检查

    public func checkForUpdate() throws -> AppUpdateCheck {
        let release = try latestRelease()
        return AppUpdateCheck.evaluate(current: configuration.currentVersion, release: release)
    }

    /// 查最新发布。先走 API；失败（限流、离线、公司网络拦 API）再走 302 兜底。
    public func latestRelease() throws -> AppRelease {
        do {
            return try fetchReleaseFromAPI()
        } catch {
            return try fetchReleaseFromRedirect(fallbackError: error)
        }
    }

    private var apiURL: URL {
        URL(string: "https://api.github.com/repos/\(configuration.owner)/\(configuration.repository)/releases/latest")!
    }

    private var latestPageURL: URL {
        URL(string: "https://github.com/\(configuration.owner)/\(configuration.repository)/releases/latest")!
    }

    private func fetchReleaseFromAPI() throws -> AppRelease {
        // 网络错误原样抛出（兜底路径要用它作为失败原因）；只有解码失败才归为「发布数据不可用」。
        let data = try fetchData(from: apiURL, accept: "application/vnd.github+json").data
        let payload: GitHubReleasePayload
        do {
            payload = try Self.decodeReleasePayload(data)
        } catch {
            throw AppUpdateError.releaseNotFound(error.localizedDescription)
        }
        guard !payload.draft, let tag = payload.tagName.nonEmpty else {
            throw AppUpdateError.releaseNotFound("发布数据不完整。")
        }
        let assets = payload.assets ?? []
        return AppRelease(
            tag: tag,
            version: Self.normalizedVersion(tag),
            name: payload.name?.nonEmpty ?? tag,
            notes: payload.body ?? "",
            pageURL: payload.htmlUrl,
            archiveURL: assets.first { $0.name == configuration.archiveAssetName }?.browserDownloadUrl,
            diskImageURL: assets.first { $0.name == configuration.diskImageAssetName }?.browserDownloadUrl,
            publishedAt: payload.publishedAt.flatMap(Self.parseTimestamp),
            isPrerelease: payload.prerelease ?? false
        )
    }

    /// API 不可用时的兜底：`/releases/latest` 会 302 到 `/releases/tag/<tag>`，
    /// `HTTPURLResponse.url` 就是跳转后的地址。资产地址按发布流水线的固定文件名拼。
    private func fetchReleaseFromRedirect(fallbackError: Error) throws -> AppRelease {
        guard let response = try? fetchData(from: latestPageURL, accept: "text/html"),
              let finalURL = response.finalURL,
              let release = Self.release(fromRedirectURL: finalURL, configuration: configuration) else {
            throw AppUpdateError.network(url: apiURL.absoluteString, message: fallbackError.localizedDescription)
        }
        return release
    }

    /// 从 `/releases/latest` 跳转后的地址还原一个 release。资产名是发布流水线里固定的，
    /// 因此这里直接按约定拼下载地址。
    static func release(fromRedirectURL finalURL: URL, configuration: Configuration) -> AppRelease? {
        guard let tag = finalURL.pathComponents.last,
              tag.hasPrefix("v"),
              let version = AppVersion(tag) else {
            return nil
        }
        let base = "https://github.com/\(configuration.owner)/\(configuration.repository)/releases/download/\(tag)"
        return AppRelease(
            tag: tag,
            version: normalizedVersion(tag),
            name: "ENVPilot \(version.raw)",
            notes: "",
            pageURL: finalURL,
            archiveURL: URL(string: "\(base)/\(configuration.archiveAssetName)"),
            diskImageURL: URL(string: "\(base)/\(configuration.diskImageAssetName)"),
            publishedAt: nil,
            isPrerelease: version.isPrerelease
        )
    }

    // MARK: 下载与暂存

    /// 下载 `ENVPilot.zip`，解压并校验其中的 `.app`。任何一步不通过都不会替换现有安装。
    public func downloadAndStage(
        _ release: AppRelease,
        progress: (@Sendable (AppUpdateProgress) -> Void)? = nil
    ) throws -> StagedAppUpdate {
        guard let archiveURL = release.archiveURL else {
            throw AppUpdateError.missingArchive(release.version)
        }
        let fileManager = FileManager.default
        let workDirectory = configuration.stagingRoot.appendingPathComponent("ENVPilot-\(release.version)", isDirectory: true)
        try? fileManager.removeItem(at: workDirectory)
        try fileManager.createDirectory(at: workDirectory, withIntermediateDirectories: true)

        let archiveURLOnDisk = workDirectory.appendingPathComponent(configuration.archiveAssetName)
        try downloadFile(
            from: archiveURL,
            to: archiveURLOnDisk,
            label: "正在下载 ENVPilot \(release.version)",
            progress: progress
        )

        progress?(AppUpdateProgress(message: "正在校验 ENVPilot \(release.version)…"))
        let stagingDirectory = workDirectory.appendingPathComponent("staged", isDirectory: true)
        try? fileManager.removeItem(at: stagingDirectory)
        try fileManager.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
        try extractArchive(archiveURLOnDisk, to: stagingDirectory)

        let appURL = try stagedApplication(in: stagingDirectory)
        try validate(appURL, expecting: release.version)

        return StagedAppUpdate(release: release, appURL: appURL, workDirectory: workDirectory)
    }

    /// 无法自更新时把 dmg 下到 `~/Downloads`，交给 Finder/安装器。
    public func downloadDiskImage(
        _ release: AppRelease,
        progress: (@Sendable (AppUpdateProgress) -> Void)? = nil
    ) throws -> URL {
        guard let url = release.diskImageURL else {
            throw AppUpdateError.missingArchive(release.version)
        }
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: configuration.downloadsDirectory.path) {
            try fileManager.createDirectory(at: configuration.downloadsDirectory, withIntermediateDirectories: true)
        }
        let destination = configuration.downloadsDirectory.appendingPathComponent("ENVPilot-\(release.version).dmg")
        try downloadFile(
            from: url,
            to: destination,
            label: "正在下载 ENVPilot \(release.version)",
            progress: progress
        )
        return destination
    }

    // MARK: 替换

    /// 写一个脱离 app 生命周期的脚本：等本进程退出 → 替换 `.app` → 去隔离属性 →
    /// 刷新 helper → 重新启动。调用方随后应立刻退出，不要等这个脚本。
    @discardableResult
    public func apply(_ staged: StagedAppUpdate, relaunch: Bool = true) throws -> URL {
        let mode = installMode()
        guard let destination = mode.destination, mode.canSelfUpdate else {
            throw AppUpdateError.selfUpdateUnavailable(mode.manualReason ?? "当前运行位置不支持自动更新。")
        }
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: configuration.stagingRoot, withIntermediateDirectories: true)

        let scriptURL = configuration.stagingRoot.appendingPathComponent("apply-\(UUID().uuidString).zsh")
        let logURL = configuration.stagingRoot.appendingPathComponent("update.log")
        let script = Self.applyScript(
            stagedApp: staged.appURL.path,
            destination: destination.path,
            helper: configuration.installedHelperPath?.path,
            workDirectory: staged.workDirectory.path,
            relaunch: relaunch
        )
        do {
            try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        } catch {
            throw AppUpdateError.installFailed(error.localizedDescription)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [
            scriptURL.path,
            String(ProcessInfo.processInfo.processIdentifier),
            logURL.path,
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            throw AppUpdateError.installFailed(error.localizedDescription)
        }
        return destination
    }

    /// 自更新脚本。参数依次是：父进程 PID、日志路径。
    static func applyScript(
        stagedApp: String,
        destination: String,
        helper: String?,
        workDirectory: String,
        relaunch: Bool
    ) -> String {
        let helperBlock = helper.map { path in
            """
            if [[ -f \(Self.shellQuote(path)) && -x "$DEST/Contents/Resources/bin/envpilot-helper" ]]; then
              cp -f "$DEST/Contents/Resources/bin/envpilot-helper" \(Self.shellQuote(path)) && chmod +x \(Self.shellQuote(path))
            fi
            """
        } ?? ""
        let relaunchBlock = relaunch
            ? #"/usr/bin/open "$DEST""#
            : #"echo "[update] relaunch skipped""#
        return """
        #!/bin/zsh
        # ENVPilot 自动更新脚本：由 app 在退出前生成，执行完自删。
        set -u
        PARENT_PID="$1"
        LOG="$2"
        STAGED=\(Self.shellQuote(stagedApp))
        DEST=\(Self.shellQuote(destination))
        WORK=\(Self.shellQuote(workDirectory))

        exec >> "$LOG" 2>&1
        echo "[$(date '+%F %T')] update start: pid=$PARENT_PID staged=$STAGED dest=$DEST"

        # 等 app 真正退出，否则替换的是正在运行的 bundle。
        for _ in {1..600}; do
          kill -0 "$PARENT_PID" 2>/dev/null || break
          sleep 0.2
        done
        sleep 0.4

        if [[ -e "$DEST" ]]; then
          rm -rf "$DEST" || { echo "[update] 无法删除旧版本，已放弃"; exit 1; }
        fi
        /usr/bin/ditto "$STAGED" "$DEST" || { echo "[update] 复制新版本失败"; exit 1; }
        /usr/bin/xattr -dr com.apple.quarantine "$DEST" 2>/dev/null
        \(helperBlock)
        echo "[update] 已更新到 $DEST"
        \(relaunchBlock)
        rm -rf "$WORK"
        rm -f "$0"
        """
    }

    // MARK: 下载原语

    private func fetchData(from url: URL, accept: String) throws -> (data: Data, finalURL: URL?) {
        let semaphore = DispatchSemaphore(value: 0)
        let state = UpdateRequestState()
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.setValue(accept, forHTTPHeaderField: "Accept")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { data, response, error in
            state.complete(data: data, response: response, error: error, url: url)
            semaphore.signal()
        }.resume()
        semaphore.wait()
        return (try state.result(), state.finalURL)
    }

    private var userAgent: String {
        "ENVPilot/\(configuration.currentVersion) (+https://github.com/\(configuration.owner)/\(configuration.repository))"
    }

    private func downloadFile(
        from url: URL,
        to destination: URL,
        label: String,
        progress: (@Sendable (AppUpdateProgress) -> Void)?
    ) throws {
        let semaphore = DispatchSemaphore(value: 0)
        let state = UpdateRequestState()
        let delegate = UpdateDownloadDelegate(
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
        let sessionConfiguration = URLSessionConfiguration.default
        sessionConfiguration.timeoutIntervalForRequest = 30
        sessionConfiguration.timeoutIntervalForResource = 600
        let session = URLSession(configuration: sessionConfiguration, delegate: delegate, delegateQueue: queue)
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        session.downloadTask(with: request).resume()
        semaphore.wait()
        session.finishTasksAndInvalidate()
        _ = try state.result()
    }

    /// 解压（`ditto -x -k`）。内部可见是为了让测试能直接用真实的 zip 走一遍。
    func extractArchive(_ archiveURL: URL, to destination: URL) throws {
        let result = try shellRunner.run(
            "/usr/bin/ditto",
            arguments: ["-x", "-k", archiveURL.path, destination.path],
            environment: environment
        )
        guard result.succeeded else {
            throw AppUpdateError.archiveInvalid(Self.errorText(result))
        }
    }

    /// 找出解压结果里的 `.app`。内部可见便于测试。
    func stagedApplication(in directory: URL) throws -> URL {
        let entries = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        let apps = entries.filter { $0.pathExtension == "app" }
        guard let app = apps.first(where: { $0.lastPathComponent == "ENVPilot.app" }) ?? apps.first else {
            throw AppUpdateError.archiveInvalid("压缩包里没有 .app。")
        }
        return app
    }

    /// 三重校验：bundle id 是自己、版本号就是目标版本、签名自洽（ad-hoc 也能过 strict 校验）。
    /// 内部可见便于测试。
    func validate(_ appURL: URL, expecting version: String) throws {
        let fileManager = FileManager.default
        let infoURL = appURL.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: infoURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw AppUpdateError.stagedAppInvalid("读不到 Info.plist。")
        }
        let identifier = plist["CFBundleIdentifier"] as? String
        guard identifier == configuration.bundleIdentifier else {
            throw AppUpdateError.stagedAppInvalid("bundle id 是 \(identifier ?? "未知")，期望 \(configuration.bundleIdentifier)。")
        }
        let bundleVersion = plist["CFBundleShortVersionString"] as? String
        guard bundleVersion == version else {
            throw AppUpdateError.stagedAppInvalid("版本号是 \(bundleVersion ?? "未知")，期望 \(version)。")
        }
        guard let executable = plist["CFBundleExecutable"] as? String else {
            throw AppUpdateError.stagedAppInvalid("Info.plist 里没有 CFBundleExecutable。")
        }
        let executableURL = appURL.appendingPathComponent("Contents/MacOS/\(executable)")
        guard fileManager.isExecutableFile(atPath: executableURL.path) else {
            throw AppUpdateError.stagedAppInvalid("可执行文件缺失或不可执行。")
        }
        let signature = try shellRunner.run(
            "/usr/bin/codesign",
            arguments: ["--verify", "--deep", "--strict", appURL.path],
            environment: environment
        )
        guard signature.succeeded else {
            throw AppUpdateError.stagedAppInvalid("签名校验失败：\(Self.errorText(signature))")
        }
    }

    // MARK: 小工具

    /// GitHub 的字段是 snake_case，和 `GitHubReleasePayload` 的属性名对不上，必须显式转换。
    static func decodeReleasePayload(_ data: Data) throws -> GitHubReleasePayload {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(GitHubReleasePayload.self, from: data)
    }

    static func normalizedVersion(_ tag: String) -> String {
        var value = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("v") || value.hasPrefix("V") {
            value.removeFirst()
        }
        return value
    }

    static func parseTimestamp(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func errorText(_ result: ShellCommandResult) -> String {
        let text = result.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "退出码 \(result.exitCode)" : text
    }
}

// MARK: - GitHub 返回体

struct GitHubReleasePayload: Decodable {
    struct Asset: Decodable {
        let name: String
        let browserDownloadUrl: URL
    }

    let tagName: String
    let name: String?
    let body: String?
    let htmlUrl: URL?
    let draft: Bool
    let prerelease: Bool?
    let publishedAt: String?
    let assets: [Asset]?
}

// MARK: - 网络状态盒

/// 请求结果在 URLSession 回调线程与等待线程之间传递。
private final class UpdateRequestState: @unchecked Sendable {
    private let lock = NSLock()
    private var storedResult: Result<Data, Error>?
    private var storedFinalURL: URL?

    var finalURL: URL? {
        lock.lock()
        defer { lock.unlock() }
        return storedFinalURL
    }

    func complete(data: Data?, response: URLResponse?, error: Error?, url: URL) {
        lock.lock()
        defer { lock.unlock() }
        storedFinalURL = response?.url
        if let error {
            storedResult = .failure(AppUpdateError.network(url: url.absoluteString, message: error.localizedDescription))
            return
        }
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            storedResult = .failure(AppUpdateError.network(url: url.absoluteString, message: "HTTP \(http.statusCode)"))
            return
        }
        guard let data else {
            storedResult = .failure(AppUpdateError.network(url: url.absoluteString, message: "没有返回内容。"))
            return
        }
        storedResult = .success(data)
    }

    func complete(_ result: Result<Data, Error>) {
        lock.lock()
        defer { lock.unlock() }
        if storedResult == nil {
            storedResult = result
        }
    }

    func result() throws -> Data {
        lock.lock()
        defer { lock.unlock() }
        guard let storedResult else {
            throw AppUpdateError.network(url: "", message: "请求未完成。")
        }
        return try storedResult.get()
    }
}

// MARK: - 下载代理

private final class UpdateDownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let url: URL
    private let destination: URL
    private let label: String
    private let progress: (@Sendable (AppUpdateProgress) -> Void)?
    private let state: UpdateRequestState
    private let completion: @Sendable () -> Void
    private let lock = NSLock()
    private let startedAt = Date()
    private var didMoveFile = false
    private var lastReport = Date(timeIntervalSince1970: 0)

    init(
        url: URL,
        destination: URL,
        label: String,
        progress: (@Sendable (AppUpdateProgress) -> Void)?,
        state: UpdateRequestState,
        completion: @escaping @Sendable () -> Void
    ) {
        self.url = url
        self.destination = destination
        self.label = label
        self.progress = progress
        self.state = state
        self.completion = completion
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let now = Date()
        let finished = totalBytesExpectedToWrite > 0 && totalBytesWritten >= totalBytesExpectedToWrite
        lock.lock()
        let shouldReport = finished || now.timeIntervalSince(lastReport) >= 0.2
        if shouldReport {
            lastReport = now
        }
        lock.unlock()
        guard shouldReport else {
            return
        }
        progress?(Self.progress(label: label, written: totalBytesWritten, expected: totalBytesExpectedToWrite, elapsed: now.timeIntervalSince(startedAt)))
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
            lock.lock()
            didMoveFile = true
            lock.unlock()
        } catch {
            state.complete(.failure(AppUpdateError.installFailed(error.localizedDescription)))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        defer { completion() }
        if let error {
            state.complete(.failure(AppUpdateError.network(url: url.absoluteString, message: error.localizedDescription)))
            return
        }
        if let http = task.response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            state.complete(.failure(AppUpdateError.network(url: url.absoluteString, message: "HTTP \(http.statusCode)")))
            return
        }
        lock.lock()
        let moved = didMoveFile
        lock.unlock()
        guard moved else {
            state.complete(.failure(AppUpdateError.network(url: url.absoluteString, message: "没有下载到文件。")))
            return
        }
        // 文件已经在 `didFinishDownloadingTo` 里落盘，这里只标记成功。
        state.complete(.success(Data()))
        progress?(AppUpdateProgress(message: "\(label) 100%", fraction: 1))
    }

    static func progress(label: String, written: Int64, expected: Int64, elapsed: TimeInterval) -> AppUpdateProgress {
        guard expected > 0 else {
            return AppUpdateProgress(message: label)
        }
        let fraction = min(1, Double(written) / Double(expected))
        let percent = Int((fraction * 100).rounded())
        let speed = speedText(bytes: written, elapsed: elapsed)
        let message = speed.isEmpty ? "\(label) \(percent)%" : "\(label) \(percent)% · \(speed)"
        return AppUpdateProgress(message: message, fraction: fraction)
    }

    static func speedText(bytes: Int64, elapsed: TimeInterval) -> String {
        guard elapsed > 0.3, bytes > 0 else {
            return ""
        }
        var value = Double(bytes) / elapsed
        let units = ["B/s", "KB/s", "MB/s", "GB/s"]
        var index = 0
        while value >= 1024, index < units.count - 1 {
            value /= 1024
            index += 1
        }
        return String(format: "%.1f %@", value, units[index])
    }
}

private extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
