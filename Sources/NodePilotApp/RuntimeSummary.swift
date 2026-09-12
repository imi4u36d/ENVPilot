import Foundation
import ENVPilotCore

// MARK: - Unified runtime view models

struct InstalledRuntime: Identifiable, Hashable {
    let id: String
    let kind: RuntimeKind
    let version: String
    let path: String

    var isManaged: Bool {
        path.contains("/.envpilot/runtimes/")
    }
}

enum VersionSource: Equatable {
    case projectFile(path: String)
    case global
    case none

    var label: String {
        switch self {
        case .projectFile:
            return "项目声明"
        case .global:
            return "全局默认"
        case .none:
            return "未设置"
        }
    }
}

struct RuntimeSummary: Identifiable {
    static let emptyVersion = "--"

    let kind: RuntimeKind
    let version: String
    let path: String?
    let source: VersionSource
    let current: InstalledRuntime?
    let isCurrentValid: Bool
    let options: [InstalledRuntime]

    var id: String {
        kind.rawValue
    }

    static func empty(_ kind: RuntimeKind) -> RuntimeSummary {
        RuntimeSummary(
            kind: kind,
            version: emptyVersion,
            path: nil,
            source: .none,
            current: nil,
            isCurrentValid: false,
            options: []
        )
    }
}

// MARK: - Snapshot readers

enum RuntimeSnapshotReader {
    static let homeDirectory = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)

    static func summary(
        for kind: RuntimeKind,
        snapshot: NodeRuntimeSnapshot,
        directory: URL?
    ) -> RuntimeSummary {
        let installed = installations(for: kind, in: snapshot)
        let settings = snapshot.settings
        let shell = ShellIntegrationService()

        let effectiveVersion: String?
        switch kind {
        case .node:
            effectiveVersion = shell.resolveEffectiveVersion(settings: settings, cwd: directory)
        case .java:
            effectiveVersion = shell.resolveEffectiveJavaVersion(settings: settings, cwd: directory)
        case .python:
            effectiveVersion = shell.resolveEffectivePythonVersion(settings: settings, cwd: directory)
        }

        let fromProject: Bool
        if let directory, settings.projectVersionPreference == .followProjectFiles {
            let projectVersion: String?
            switch kind {
            case .node:
                projectVersion = ProjectNodeVersionResolver().resolveVersion(startingAt: directory)
            case .java:
                projectVersion = ProjectJavaVersionResolver().resolveVersion(startingAt: directory)
            case .python:
                projectVersion = ProjectPythonVersionResolver().resolveVersion(startingAt: directory)
            }
            fromProject = projectVersion != nil && projectVersion == effectiveVersion
        } else {
            fromProject = false
        }

        let source: VersionSource
        if fromProject, let file = nearestEnvPilotFile(in: directory ?? homeDirectory) {
            source = .projectFile(path: file.path)
        } else if effectiveVersion != nil {
            source = .global
        } else {
            source = .none
        }

        let matched = effectiveVersion.flatMap { value in
            installed.first { matches(installed: $0.version, requested: value, kind: kind) }
        }

        let path = matched?.path ?? defaultPath(for: kind, in: settings)

        return RuntimeSummary(
            kind: kind,
            version: matched?.version ?? effectiveVersion ?? RuntimeSummary.emptyVersion,
            path: path,
            source: source,
            current: matched,
            isCurrentValid: effectiveVersion == nil || matched != nil,
            options: installed
        )
    }

    static func summaries(
        for snapshot: NodeRuntimeSnapshot,
        directory: URL?
    ) -> [RuntimeSummary] {
        RuntimeKind.allCases.map { summary(for: $0, snapshot: snapshot, directory: directory) }
    }

    static func installations(for kind: RuntimeKind, in snapshot: NodeRuntimeSnapshot) -> [InstalledRuntime] {
        switch kind {
        case .node:
            snapshot.installations.map {
                InstalledRuntime(id: $0.executablePath, kind: .node, version: $0.version, path: $0.installPath)
            }
        case .java:
            snapshot.javaInstallations.map {
                InstalledRuntime(id: $0.homePath, kind: .java, version: $0.version, path: $0.homePath)
            }
        case .python:
            snapshot.pythonInstallations.map {
                InstalledRuntime(id: $0.executablePath, kind: .python, version: $0.version, path: $0.homePath)
            }
        }
    }

    static func defaultVersion(for kind: RuntimeKind, in settings: AppSettings) -> String? {
        switch kind {
        case .node:
            settings.selectedVersion
        case .java:
            settings.selectedJavaVersion
        case .python:
            settings.selectedPythonVersion
        }
    }

    static func defaultPath(for kind: RuntimeKind, in settings: AppSettings) -> String? {
        switch kind {
        case .node:
            settings.selectedNodePath
        case .java:
            settings.selectedJavaHome
        case .python:
            settings.selectedPythonHome
        }
    }

    static func matches(installed: String, requested: String, kind: RuntimeKind) -> Bool {
        if installed == requested {
            return true
        }
        let parts = requested.split(separator: ".").map(String.init)
        switch kind {
        case .node:
            return false
        case .java:
            guard let major = parts.first else {
                return false
            }
            return installed == major || installed.hasPrefix("\(major).")
        case .python:
            guard parts.count >= 2 else {
                return false
            }
            let feature = "\(parts[0]).\(parts[1])"
            return installed == feature || installed.hasPrefix("\(feature).")
        }
    }

    static func activationScript(
        for snapshot: NodeRuntimeSnapshot,
        directory: URL?
    ) -> String {
        ShellIntegrationService().renderActivationScript(
            settings: snapshot.settings,
            nodeInstallations: snapshot.installations,
            javaInstallations: snapshot.javaInstallations,
            pythonInstallations: snapshot.pythonInstallations,
            cwd: directory
        )
    }

    static func nearestEnvPilotFile(in directory: URL) -> URL? {
        var current = directory.standardizedFileURL
        let root = URL(fileURLWithPath: "/", isDirectory: true)
        while current.path != root.path {
            let candidate = current.appendingPathComponent(".envpilot")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path {
                break
            }
            current = parent
        }
        return nil
    }
}

// MARK: - Project inspection

struct ProjectRuntimeEntry: Identifiable {
    let kind: RuntimeKind
    let declaredVersion: String?
    let matchedInstallation: InstalledRuntime?
    let effectiveVersion: String
    let usesProjectDeclaration: Bool

    var id: String {
        kind.rawValue
    }

    var isSatisfied: Bool {
        if declaredVersion == nil {
            return true
        }
        return matchedInstallation != nil
    }
}

struct ProjectEnvironmentSnapshot {
    let directory: URL
    let envPilotFile: URL?
    let entries: [ProjectRuntimeEntry]

    var hasRequirements: Bool {
        entries.contains { $0.declaredVersion != nil }
    }
}

enum ProjectInspector {
    static func inspect(directory: URL, snapshot: NodeRuntimeSnapshot) -> ProjectEnvironmentSnapshot {
        let file = RuntimeSnapshotReader.nearestEnvPilotFile(in: directory)
        let declarations = file.map(readDeclarations) ?? [:]
        let followsProject = snapshot.settings.projectVersionPreference == .followProjectFiles

        let entries = RuntimeKind.allCases.map { kind -> ProjectRuntimeEntry in
            let raw = declarations[kind.envPilotKey]?.trimmingCharacters(in: .whitespacesAndNewlines)
            let declared = (raw?.isEmpty == false) ? raw : nil
            let installed = RuntimeSnapshotReader.installations(for: kind, in: snapshot)
            let matched = declared.flatMap { value in
                installed.first { RuntimeSnapshotReader.matches(installed: $0.version, requested: value, kind: kind) }
            }
            let globalDefault = RuntimeSnapshotReader.defaultVersion(for: kind, in: snapshot.settings)
            let effective = followsProject
                ? (declared ?? globalDefault ?? RuntimeSummary.emptyVersion)
                : (globalDefault ?? RuntimeSummary.emptyVersion)

            return ProjectRuntimeEntry(
                kind: kind,
                declaredVersion: declared,
                matchedInstallation: matched,
                effectiveVersion: effective,
                usesProjectDeclaration: followsProject && declared != nil
            )
        }

        return ProjectEnvironmentSnapshot(directory: directory, envPilotFile: file, entries: entries)
    }

    private static func readDeclarations(from file: URL) -> [String: String] {
        guard let contents = try? String(contentsOf: file, encoding: .utf8) else {
            return [:]
        }
        var result: [String: String] = [:]
        for line in contents.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else {
                continue
            }
            let parts = trimmed.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else {
                continue
            }
            let key = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            var value = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            if value.count >= 2,
               (value.hasPrefix("\"") && value.hasSuffix("\"")) || (value.hasPrefix("'") && value.hasSuffix("'")) {
                value = String(value.dropFirst().dropLast())
            }
            result[key] = value
        }
        return result
    }
}

extension RuntimeKind {
    var envPilotKey: String {
        switch self {
        case .node:
            return "NODE_VERSION"
        case .java:
            return "JAVA_VERSION"
        case .python:
            return "PYTHON_VERSION"
        }
    }
}
