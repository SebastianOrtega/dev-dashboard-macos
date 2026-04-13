import Foundation

struct PortBinding: Hashable, Identifiable {
    let port: Int
    let address: String
    let host: String
    let raw: String

    var id: String {
        "\(host):\(port)"
    }
}

enum ProcessRole: String, Hashable {
    case frontend
    case backend
    case unknown
}

struct RuntimeInfo: Hashable {
    let raw: String?
    let seconds: Int?
    let label: String
}

struct WarningBanner: Hashable, Identifiable {
    let type: String
    let level: String
    let message: String

    var id: String { type }
}

struct ScanSummary: Hashable {
    let total: Int
    let frontends: Int
    let backends: Int
    let duplicates: Int
    let suspicious: Int

    static let empty = ScanSummary(
        total: 0,
        frontends: 0,
        backends: 0,
        duplicates: 0,
        suspicious: 0
    )
}

struct DevProcess: Hashable, Identifiable {
    let pid: Int32
    let name: String
    let command: String?
    let ports: [PortBinding]
    let runtime: RuntimeInfo
    let cwd: String?
    let projectName: String?
    let user: String?
    let projectProcessCount: Int
    let duplicateCount: Int
    let warnings: [String]
    let appType: String
    let role: ProcessRole

    var id: Int32 { pid }

    var portSummary: String {
        ports
            .map { "\($0.address):\($0.port)" }
            .joined(separator: ", ")
    }

    var hasPorts: Bool {
        !ports.isEmpty
    }

    var inspectionCommands: ProcessTerminalCommands {
        let uniquePorts = Array(Set(ports.map(\.port))).sorted()

        return ProcessTerminalCommands(
            inspectPid: "ps -p \(pid) -o pid=,ppid=,etime=,args=",
            inspectPorts: uniquePorts.isEmpty
                ? nil
                : uniquePorts.map { "lsof -nP -iTCP:\($0) -sTCP:LISTEN" }.joined(separator: "\n"),
            terminatePid: "kill \(pid)",
            forcePid: "kill -9 \(pid)",
            forcePorts: uniquePorts.isEmpty
                ? nil
                : uniquePorts.map { "kill -9 $(lsof -ti:\($0))" }.joined(separator: "\n")
        )
    }
}

struct ProcessTerminalCommands: Hashable {
    let inspectPid: String
    let inspectPorts: String?
    let terminatePid: String
    let forcePid: String
    let forcePorts: String?
}

struct ScanSnapshot: Hashable {
    let generatedAt: Date
    let processes: [DevProcess]
    let warnings: [WarningBanner]
    let summary: ScanSummary

    static let empty = ScanSnapshot(
        generatedAt: Date(),
        processes: [],
        warnings: [],
        summary: .empty
    )
}

struct ProcessTerminationResult: Hashable {
    let ok: Bool
    let pid: Int32
    let signalName: String
    let requiresForce: Bool
}

struct ProjectTerminationResult: Hashable {
    let ok: Bool
    let cwd: String
    let results: [ProcessTerminationResult]
}
