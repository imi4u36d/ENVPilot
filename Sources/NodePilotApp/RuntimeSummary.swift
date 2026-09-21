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

struct RuntimeSummary: Identifiable {
    static let emptyVersion = "--"

    let kind: RuntimeKind
    let version: String
    let path: String?
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
            current: nil,
            isCurrentValid: false,
            options: []
        )
    }
}

// MARK: - Snapshot readers

/// 把 `NodeRuntimeSnapshot` 折算成页面直接可读的 `RuntimeSummary`。
///
/// 版本只由全局选择决定：这里不再有「按当前作用域（项目目录）解析 `.envpilot`」那一步，
/// 所以整条派生是纯计算，不需要后台任务，也没有文件 IO。
enum RuntimeSnapshotReader {
    static func summary(
        for kind: RuntimeKind,
        snapshot: NodeRuntimeSnapshot
    ) -> RuntimeSummary {
        let installed = installations(for: kind, in: snapshot)
        let settings = snapshot.settings
        let shell = ShellIntegrationService()

        let effectiveVersion: String?
        switch kind {
        case .node:
            effectiveVersion = shell.resolveEffectiveVersion(settings: settings)
        case .java:
            effectiveVersion = shell.resolveEffectiveJavaVersion(settings: settings)
        case .python:
            effectiveVersion = shell.resolveEffectivePythonVersion(settings: settings)
        }

        let matched = effectiveVersion.flatMap { value in
            installed.first { matches(installed: $0.version, requested: value, kind: kind) }
        }

        let path = matched?.path ?? defaultPath(for: kind, in: settings)

        return RuntimeSummary(
            kind: kind,
            version: matched?.version ?? effectiveVersion ?? RuntimeSummary.emptyVersion,
            path: path,
            current: matched,
            isCurrentValid: effectiveVersion == nil || matched != nil,
            options: installed
        )
    }

    static func summaries(for snapshot: NodeRuntimeSnapshot) -> [RuntimeSummary] {
        RuntimeKind.allCases.map { summary(for: $0, snapshot: snapshot) }
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

    static func activationScript(for snapshot: NodeRuntimeSnapshot) -> String {
        ShellIntegrationService().renderActivationScript(
            settings: snapshot.settings,
            nodeInstallations: snapshot.installations,
            javaInstallations: snapshot.javaInstallations,
            pythonInstallations: snapshot.pythonInstallations
        )
    }
}
