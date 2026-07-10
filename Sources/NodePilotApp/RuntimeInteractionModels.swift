import Foundation

enum RuntimeInstallationStage: String, Sendable {
    case preparing = "准备"
    case downloading = "下载"
    case verifying = "校验"
    case extracting = "解压"
    case configuring = "配置"
    case compiling = "编译"
    case installing = "安装"
    case completed = "完成"
}

struct RuntimeInstallationProgress: Equatable, Sendable {
    let candidateID: String
    let stage: RuntimeInstallationStage
    let fractionCompleted: Double?
    let message: String

    init(candidateID: String, message: String) {
        self.candidateID = candidateID
        self.stage = Self.stage(for: message)
        self.fractionCompleted = Self.fraction(from: message)
        self.message = message
    }

    private static func stage(for message: String) -> RuntimeInstallationStage {
        if message.contains("完成") {
            return .completed
        }
        if message.contains("下载") {
            return .downloading
        }
        if message.contains("校验") {
            return .verifying
        }
        if message.contains("解压") {
            return .extracting
        }
        if message.contains("配置") {
            return .configuring
        }
        if message.contains("编译") {
            return .compiling
        }
        if message.contains("写入") || message.contains("安装") {
            return .installing
        }
        return .preparing
    }

    private static func fraction(from message: String) -> Double? {
        guard let percentIndex = message.firstIndex(of: "%") else {
            return nil
        }

        var startIndex = percentIndex
        while startIndex > message.startIndex {
            let previousIndex = message.index(before: startIndex)
            guard message[previousIndex].isNumber else {
                break
            }
            startIndex = previousIndex
        }

        guard startIndex < percentIndex,
              let percentage = Double(message[startIndex..<percentIndex]) else {
            return nil
        }
        return min(max(percentage / 100, 0), 1)
    }
}

enum RuntimeUninstallTarget {
    case node(version: String, path: String, isCurrent: Bool)
    case java(version: String, path: String, isCurrent: Bool)
    case python(version: String, path: String, isCurrent: Bool)
}

struct RuntimeUninstallRequest: Identifiable {
    let id = UUID()
    let target: RuntimeUninstallTarget

    var displayName: String {
        switch target {
        case .node(let version, _, _):
            return "Node \(version)"
        case .java(let version, _, _):
            return "JDK \(version)"
        case .python(let version, _, _):
            return "Python \(version)"
        }
    }

    var path: String {
        switch target {
        case .node(_, let path, _), .java(_, let path, _), .python(_, let path, _):
            return path
        }
    }

    var isCurrent: Bool {
        switch target {
        case .node(_, _, let isCurrent), .java(_, _, let isCurrent), .python(_, _, let isCurrent):
            return isCurrent
        }
    }
}
