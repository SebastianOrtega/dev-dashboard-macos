import Darwin
import Foundation

struct ProcessScanner {
    private let excludedPorts: Set<Int> = [7000, 7001]
    private let typicalDevPorts: Set<Int> = [3000, 3001, 4000, 4100, 4173, 4200, 4321, 5000, 5173, 5174, 8000, 8080, 8787]
    private let frontendHints = [
        "vite",
        "next dev",
        "next/dist/bin/next",
        "webpack-dev-server",
        "astro dev",
        "nuxt dev",
        "parcel",
        "react-scripts start"
    ]
    private let pythonServerHints = [
        "http.server",
        "uvicorn",
        "gunicorn",
        "flask",
        "manage.py runserver",
        "django",
        "hypercorn",
        "streamlit",
        "fastapi"
    ]
    private let nodeBackendHints = [
        "express",
        "fastify",
        "koa",
        "hono",
        "nest",
        "nodemon",
        "tsx",
        "ts-node",
        "server",
        "api",
        "dev"
    ]
    private let genericDevHints = [
        "node",
        "npm",
        "pnpm",
        "yarn",
        "bun",
        "vite",
        "next",
        "python",
        "uvicorn",
        "gunicorn",
        "flask",
        "django",
        "webpack",
        "astro",
        "nuxt",
        "parcel",
        "remix",
        "serve",
        "dev server"
    ]
    private let ignoreCommandHints = [
        "electron",
        "chrome",
        "firefox",
        "language_server",
        "controlcenter",
        "rapportd",
        "gitnexus mcp",
        "cloudflared",
        "codex",
        "claude",
        "cursor"
    ]

    func scan() throws -> ScanSnapshot {
        let lsofOutput = try Shell.run(
            "/usr/sbin/lsof",
            arguments: ["-nP", "-iTCP", "-sTCP:LISTEN", "-Fpcn"],
            allowNonZeroExit: true
        )

        let listeners = parseListeners(from: lsofOutput)
        let pids = listeners.keys.sorted()

        guard !pids.isEmpty else {
            return .empty
        }

        let pidArgument = pids.map(String.init).joined(separator: ",")
        let psOutput = try Shell.run(
            "/bin/ps",
            arguments: ["-ww", "-o", "pid=,ppid=,user=,etime=,args=", "-p", pidArgument]
        )
        let cwdOutput = try Shell.run(
            "/usr/sbin/lsof",
            arguments: ["-a", "-d", "cwd", "-p", pidArgument, "-Fn"],
            allowNonZeroExit: true
        )

        let psDetails = parsePSDetails(from: psOutput)
        let cwdMap = parseCwdMap(from: cwdOutput)

        var processes = pids.compactMap { pid -> DevProcess? in
            guard let listener = listeners[pid] else { return nil }
            return buildProcess(
                pid: pid,
                listener: listener,
                detail: psDetails[pid],
                cwd: cwdMap[pid]
            )
        }
        .filter(\.hasPorts)
        .filter(isDevelopmentProcess(_:))

        let warnings = annotate(processes: &processes)
        let summary = ScanSummary(
            total: processes.count,
            frontends: processes.filter { $0.role == .frontend }.count,
            backends: processes.filter { $0.role == .backend }.count,
            duplicates: processes.filter { $0.warnings.contains("duplicated") }.count,
            suspicious: processes.filter { $0.warnings.contains("suspicious") }.count
        )

        return ScanSnapshot(
            generatedAt: Date(),
            processes: processes.sorted { $0.pid < $1.pid },
            warnings: warnings,
            summary: summary
        )
    }

    func terminateProcess(pid: Int32, force: Bool = false) async throws -> ProcessTerminationResult {
        let signal = force ? SIGKILL : SIGTERM
        let signalName = force ? "SIGKILL" : "SIGTERM"

        if kill(pid, signal) != 0 {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EPERM)
        }

        try await Task.sleep(nanoseconds: force ? 250_000_000 : 800_000_000)

        let stillRunning = kill(pid, 0) == 0
        return ProcessTerminationResult(
            ok: !stillRunning,
            pid: pid,
            signalName: signalName,
            requiresForce: stillRunning && !force
        )
    }

    func terminateProject(cwd: String, force: Bool = false) async throws -> ProjectTerminationResult {
        let snapshot = try scan()
        let targets = snapshot.processes.filter { $0.cwd == cwd }

        let results = try await withThrowingTaskGroup(of: ProcessTerminationResult.self) { group in
            for process in targets {
                group.addTask {
                    try await terminateProcess(pid: process.pid, force: force)
                }
            }

            var collected: [ProcessTerminationResult] = []
            for try await result in group {
                collected.append(result)
            }
            return collected.sorted { $0.pid < $1.pid }
        }

        return ProjectTerminationResult(
            ok: results.allSatisfy(\.ok),
            cwd: cwd,
            results: results
        )
    }

    private func parseListeners(from output: String) -> [Int32: ListenerRecord] {
        var records: [Int32: ListenerRecord] = [:]
        var currentPID: Int32?

        // `lsof -F` expone un stream de campos. `p` inicia un proceso y los
        // siguientes `n` corresponden a sockets/FDs asociados a ese PID.
        for line in output.split(separator: "\n", omittingEmptySubsequences: false) {
            guard let prefix = line.first else { continue }
            let value = String(line.dropFirst())

            switch prefix {
            case "p":
                currentPID = Int32(value)
                if let pid = currentPID {
                    records[pid] = records[pid] ?? ListenerRecord(name: nil, sockets: [])
                }
            case "c":
                guard let pid = currentPID else { continue }
                records[pid]?.name = value
            case "n":
                guard let pid = currentPID, let socket = parseSocket(String(value)) else { continue }
                guard !excludedPorts.contains(socket.port) else { continue }
                if records[pid]?.sockets.contains(socket) != true {
                    records[pid]?.sockets.append(socket)
                }
            default:
                continue
            }
        }

        return records.filter { !$0.value.sockets.isEmpty }
    }

    private func parseSocket(_ raw: String) -> PortBinding? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }

        let host: String
        let portString: String

        if value.hasPrefix("[") {
            guard
                let closing = value.firstIndex(of: "]"),
                value.index(after: closing) < value.endIndex,
                value[value.index(after: closing)] == ":"
            else {
                return nil
            }

            host = String(value[value.index(after: value.startIndex)..<closing])
            portString = String(value[value.index(closing, offsetBy: 2)...])
        } else {
            guard let colon = value.lastIndex(of: ":") else { return nil }
            host = String(value[..<colon])
            portString = String(value[value.index(after: colon)...])
        }

        guard let port = Int(portString) else { return nil }
        let normalizedHost = (host == "*" || host == "::") ? "0.0.0.0" : host
        let address: String

        switch normalizedHost {
        case "127.0.0.1", "::1", "localhost":
            address = "localhost"
        default:
            address = normalizedHost
        }

        return PortBinding(port: port, address: address, host: normalizedHost, raw: value)
    }

    private func parsePSDetails(from output: String) -> [Int32: PSDetail] {
        var details: [Int32: PSDetail] = [:]

        // `ps` no devuelve JSON; aquí consumimos 4 columnas fijas y dejamos el
        // resto de la línea intacto como comando completo.
        for rawLine in output.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }

            let parts = line.split(separator: " ", maxSplits: 4, omittingEmptySubsequences: true)
            guard parts.count == 5, let pid = Int32(parts[0]), let ppid = Int32(parts[1]) else {
                continue
            }

            details[pid] = PSDetail(
                pid: pid,
                ppid: ppid,
                user: String(parts[2]),
                elapsed: String(parts[3]),
                command: String(parts[4])
            )
        }

        return details
    }

    private func parseCwdMap(from output: String) -> [Int32: String] {
        var cwdMap: [Int32: String] = [:]
        var currentPID: Int32?

        for line in output.split(separator: "\n", omittingEmptySubsequences: false) {
            guard let prefix = line.first else { continue }
            let value = String(line.dropFirst())

            switch prefix {
            case "p":
                currentPID = Int32(value)
            case "n":
                if let pid = currentPID {
                    cwdMap[pid] = value
                }
            default:
                continue
            }
        }

        return cwdMap
    }

    private func buildProcess(
        pid: Int32,
        listener: ListenerRecord,
        detail: PSDetail?,
        cwd: String?
    ) -> DevProcess {
        let runtime = RuntimeInfo(
            raw: detail?.elapsed,
            seconds: parseElapsed(detail?.elapsed),
            label: formatRuntime(parseElapsed(detail?.elapsed))
        )

        return DevProcess(
            pid: pid,
            name: listener.name ?? commandBasename(from: detail?.command) ?? "unknown",
            command: detail?.command,
            ports: listener.sockets.sorted { $0.port < $1.port },
            runtime: runtime,
            cwd: cwd,
            projectName: cwd.map { URL(fileURLWithPath: $0).lastPathComponent },
            user: detail?.user,
            projectProcessCount: 0,
            duplicateCount: 0,
            warnings: [],
            appType: classify(
                name: listener.name,
                command: detail?.command,
                cwd: cwd
            ).appType,
            role: classify(
                name: listener.name,
                command: detail?.command,
                cwd: cwd
            ).role
        )
    }

    private func classify(name: String?, command: String?, cwd: String?) -> (appType: String, role: ProcessRole) {
        let haystack = [name, command, cwd]
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()

        let isVite = frontendHints.filter { $0.contains("vite") }.contains { haystack.contains($0) } || haystack.contains(" vite ") || haystack.hasSuffix("vite") || haystack.hasPrefix("vite ")
        let isNext = haystack.contains("next dev") || haystack.contains("next/dist/bin/next")
        let isPythonServer = haystack.contains("python") && pythonServerHints.contains { haystack.contains($0) }
        let isNodeLike = haystack.range(of: #"\b(node|npm|pnpm|yarn|bun|tsx|ts-node|nodemon)\b"#, options: .regularExpression) != nil
        let hasProjectContext =
            ((cwd?.hasPrefix("/Users/") == true) && cwd != "/") ||
            ((command?.contains("/Users/") == true) && (command?.contains("/Applications/") != true))
        let looksLikeBackendEntry =
            nodeBackendHints.contains { haystack.contains($0) } ||
            haystack.range(of: #"\b(src|app|server|index)\.(js|mjs|cjs|ts)\b"#, options: .regularExpression) != nil

        if isVite {
            return ("vite frontend", .frontend)
        }

        if isNext {
            return ("next dev server", .frontend)
        }

        if isNodeLike && hasProjectContext && looksLikeBackendEntry {
            return ("node backend", .backend)
        }

        if isPythonServer {
            return ("python local server", .backend)
        }

        return ("unknown", .unknown)
    }

    private func isDevelopmentProcess(_ process: DevProcess) -> Bool {
        let haystack = [process.name, process.command, process.cwd]
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()

        let hasProjectContext =
            ((process.cwd?.hasPrefix("/Users/") == true) && process.cwd != "/") ||
            ((process.command?.contains("/Users/") == true) && (process.command?.contains("/Applications/") != true))
        let looksLikeBackendEntry =
            nodeBackendHints.contains { haystack.contains($0) } ||
            haystack.range(of: #"\b(src|app|server|index)\.(js|mjs|cjs|ts)\b"#, options: .regularExpression) != nil
        let ignored = ignoreCommandHints.contains { haystack.contains($0) }
        let classified = classify(name: process.name, command: process.command, cwd: process.cwd)

        return !ignored &&
            hasProjectContext &&
            (
                classified.appType != "unknown" ||
                (haystack.contains("python") && pythonServerHints.contains { haystack.contains($0) }) ||
                (genericDevHints.contains { haystack.contains($0) } && looksLikeBackendEntry)
            )
    }

    private func annotate(processes: inout [DevProcess]) -> [WarningBanner] {
        var byCwd: [String: [Int32]] = [:]
        var bySignature: [String: [Int32]] = [:]
        var typicalCount = 0

        for process in processes {
            if let cwd = process.cwd {
                byCwd[cwd, default: []].append(process.pid)
            }

            let signature = "\(process.appType)|\(process.cwd ?? "unknown")|\(process.name)"
            bySignature[signature, default: []].append(process.pid)

            if process.ports.contains(where: { typicalDevPorts.contains($0.port) }) {
                typicalCount += 1
            }
        }

        for index in processes.indices {
            let process = processes[index]
            let signature = "\(process.appType)|\(process.cwd ?? "unknown")|\(process.name)"
            let projectPeers = process.cwd.flatMap { byCwd[$0] } ?? []
            let similarProcesses = bySignature[signature] ?? []

            var warnings: [String] = []
            if similarProcesses.count > 1 {
                warnings.append("duplicated")
            }
            if projectPeers.count > 1 {
                warnings.append("suspicious")
            }

            processes[index] = DevProcess(
                pid: process.pid,
                name: process.name,
                command: process.command,
                ports: process.ports,
                runtime: process.runtime,
                cwd: process.cwd,
                projectName: process.projectName,
                user: process.user,
                projectProcessCount: projectPeers.count,
                duplicateCount: max(similarProcesses.count - 1, 0),
                warnings: Array(Set(warnings)),
                appType: process.appType,
                role: process.role
            )
        }

        var banners: [WarningBanner] = []

        if typicalCount > 1 {
            banners.append(
                WarningBanner(
                    type: "multi-dev-ports",
                    level: "warning",
                    message: "Hay varios procesos ocupando puertos típicos de desarrollo."
                )
            )
        }

        if processes.contains(where: { $0.warnings.contains("duplicated") }) {
            banners.append(
                WarningBanner(
                    type: "duplicates",
                    level: "warning",
                    message: "Se detectaron procesos parecidos o posiblemente duplicados."
                )
            )
        }

        if processes.contains(where: { $0.warnings.contains("suspicious") }) {
            banners.append(
                WarningBanner(
                    type: "same-project",
                    level: "warning",
                    message: "Hay más de un proceso escuchando desde la misma carpeta de proyecto."
                )
            )
        }

        return banners
    }

    private func parseElapsed(_ value: String?) -> Int? {
        guard let value else { return nil }

        // `ps etime` en macOS puede venir como `MM:SS`, `HH:MM:SS` o `DD-HH:MM:SS`.
        let daySplit = value.split(separator: "-", omittingEmptySubsequences: true)
        let timePart = String(daySplit.last ?? "")
        let days = daySplit.count == 2 ? Int(daySplit[0]) ?? 0 : 0
        let pieces = timePart.split(separator: ":").compactMap { Int($0) }

        switch pieces.count {
        case 2:
            return days * 86_400 + pieces[0] * 60 + pieces[1]
        case 3:
            return days * 86_400 + pieces[0] * 3_600 + pieces[1] * 60 + pieces[2]
        default:
            return nil
        }
    }

    private func formatRuntime(_ seconds: Int?) -> String {
        guard let seconds else { return "desconocido" }

        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60
        let remainder = seconds % 60

        if days > 0 {
            return "\(days)d \(hours)h"
        }

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }

        if minutes > 0 {
            return "\(minutes)m \(remainder)s"
        }

        return "\(remainder)s"
    }

    private func commandBasename(from command: String?) -> String? {
        guard let command else { return nil }
        let firstToken = command.split(separator: " ").first.map(String.init)
        return firstToken.map { URL(fileURLWithPath: $0).lastPathComponent }
    }
}

private struct ListenerRecord {
    var name: String?
    var sockets: [PortBinding]
}

private struct PSDetail {
    let pid: Int32
    let ppid: Int32
    let user: String
    let elapsed: String
    let command: String
}
