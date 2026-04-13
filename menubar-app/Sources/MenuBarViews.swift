import SwiftUI

private enum PendingConfirmation: Identifiable {
    case terminate(DevProcess)
    case forceTerminate(DevProcess)
    case terminateProject(DevProcess)
    case forceTerminateProject(DevProcess)

    var id: String {
        switch self {
        case .terminate(let process):
            return "terminate-\(process.id)"
        case .forceTerminate(let process):
            return "force-terminate-\(process.id)"
        case .terminateProject(let process):
            return "terminate-project-\(process.id)"
        case .forceTerminateProject(let process):
            return "force-terminate-project-\(process.id)"
        }
    }

    var title: String {
        switch self {
        case .terminate:
            return "Terminar proceso"
        case .forceTerminate:
            return "Forzar cierre"
        case .terminateProject:
            return "Terminar proyecto"
        case .forceTerminateProject:
            return "Forzar cierre del proyecto"
        }
    }

    var message: String {
        switch self {
        case .terminate(let process):
            return "Se enviará SIGTERM al proceso \(process.pid) (\(process.name))."
        case .forceTerminate(let process):
            return "El proceso \(process.pid) sigue vivo. Esto enviará SIGKILL."
        case .terminateProject(let process):
            return "Se enviará SIGTERM a los procesos detectados en \(process.cwd ?? "este proyecto")."
        case .forceTerminateProject:
            return "Uno o más procesos del proyecto siguen vivos. Esto enviará SIGKILL."
        }
    }

    var confirmLabel: String {
        switch self {
        case .terminate, .terminateProject:
            return "Cerrar"
        case .forceTerminate, .forceTerminateProject:
            return "Forzar"
        }
    }
}

struct MenuBarContentView: View {
    @ObservedObject var store: DashboardStore

    @State private var searchText = ""
    @State private var selectedProcess: DevProcess?
    @State private var pendingConfirmation: PendingConfirmation?

    private var filteredProcesses: [DevProcess] {
        let term = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !term.isEmpty else { return store.snapshot.processes }

        return store.snapshot.processes.filter { process in
            let haystack = [
                String(process.pid),
                process.name,
                process.command ?? "",
                process.cwd ?? "",
                process.appType,
                process.portSummary
            ]
            .joined(separator: " ")
            .lowercased()

            return haystack.contains(term)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            summaryStrip
            if !store.snapshot.warnings.isEmpty {
                warningStrip
            }
            controls
            if let errorMessage = store.errorMessage {
                errorBanner(errorMessage)
            }
            processList
            footer
        }
        .padding(14)
        .frame(width: 620, height: 720)
        .task {
            await store.start()
        }
        .sheet(item: $selectedProcess) { process in
            ProcessDetailView(
                process: latestProcess(for: process),
                onCopy: { store.copyToClipboard($0) },
                onKill: { pendingConfirmation = .terminate(latestProcess(for: process)) },
                onKillProject: {
                    let latest = latestProcess(for: process)
                    if latest.cwd != nil {
                        pendingConfirmation = .terminateProject(latest)
                    }
                }
            )
            .frame(minWidth: 560, minHeight: 640)
        }
        .alert(item: $pendingConfirmation) { confirmation in
            Alert(
                title: Text(confirmation.title),
                message: Text(confirmation.message),
                primaryButton: .destructive(Text(confirmation.confirmLabel)) {
                    Task { await handleConfirmation(confirmation) }
                },
                secondaryButton: .cancel()
            )
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Dev Dashboard")
                        .font(.title3.weight(.semibold))
                    Text("Monitorea procesos de desarrollo desde la barra de menú")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if store.isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            Text("Último refresh: \(store.snapshot.generatedAt.formatted(date: .omitted, time: .standard))")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var summaryStrip: some View {
        HStack(spacing: 8) {
            SummaryBadge(label: "Total", value: store.snapshot.summary.total, tint: .primary)
            SummaryBadge(label: "Front", value: store.snapshot.summary.frontends, tint: .green)
            SummaryBadge(label: "Back", value: store.snapshot.summary.backends, tint: .blue)
            SummaryBadge(label: "Dup", value: store.snapshot.summary.duplicates, tint: .orange)
            SummaryBadge(label: "Susp", value: store.snapshot.summary.suspicious, tint: .red)
        }
    }

    private var warningStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(store.snapshot.warnings) { warning in
                    Label(warning.message, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.orange.opacity(0.12), in: Capsule())
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    private var controls: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Buscar por puerto, PID, nombre o comando", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))

            HStack {
                Toggle("Auto refresh", isOn: $store.autoRefresh)
                    .toggleStyle(.switch)

                Picker("Intervalo", selection: $store.refreshInterval) {
                    Text("3s").tag(3.0)
                    Text("5s").tag(5.0)
                    Text("10s").tag(10.0)
                }
                .pickerStyle(.segmented)
                .frame(width: 180)

                Spacer()

                Button {
                    Task { await store.refresh(showLoading: true) }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
            }
            .font(.caption)

            HStack(spacing: 10) {
                Toggle(
                    "Launch at Login",
                    isOn: Binding(
                        get: { store.launchAtLoginEnabled },
                        set: { store.setLaunchAtLogin($0) }
                    )
                )
                .toggleStyle(.switch)

                Text(store.launchAtLoginStatusText)
                    .font(.caption)
                    .foregroundStyle(store.launchAtLoginRequiresApproval ? .orange : .secondary)

                if store.launchAtLoginRequiresApproval {
                    Button("Abrir ajustes") {
                        store.openLoginItemsSettings()
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                }

                Spacer()
            }
        }
    }

    private var processList: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                if filteredProcesses.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "bolt.slash")
                            .font(.system(size: 26))
                            .foregroundStyle(.secondary)
                        Text("Sin procesos detectados")
                            .font(.headline)
                        Text("No hay procesos de desarrollo escuchando puertos.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                } else {
                    ForEach(filteredProcesses) { process in
                        ProcessRowView(
                            process: process,
                            onDetail: { selectedProcess = process },
                            onCopy: { store.copyToClipboard(process.command ?? "") },
                            onKill: { pendingConfirmation = .terminate(process) }
                        )
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .background(Color(NSColor.controlBackgroundColor).opacity(0.45), in: RoundedRectangle(cornerRadius: 16))
    }

    private var footer: some View {
        HStack {
            Text("Puertos 7000 y 7001 se siguen excluyendo para mantener compatibilidad con la versión web.")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Quit") {
                store.quitApp()
            }
            .buttonStyle(.borderless)
        }
    }

    private func errorBanner(_ message: String) -> some View {
        Text(message)
            .font(.caption)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            .foregroundStyle(.red)
    }

    private func latestProcess(for process: DevProcess) -> DevProcess {
        store.snapshot.processes.first(where: { $0.id == process.id }) ?? process
    }

    private func handleConfirmation(_ confirmation: PendingConfirmation) async {
        switch confirmation {
        case .terminate(let process):
            guard let result = await store.terminate(process, force: false) else { return }
            if result.requiresForce {
                pendingConfirmation = .forceTerminate(process)
            }
        case .forceTerminate(let process):
            _ = await store.terminate(process, force: true)
        case .terminateProject(let process):
            guard let cwd = process.cwd else { return }
            guard let result = await store.terminateProject(cwd: cwd, force: false) else { return }
            if result.results.contains(where: \.requiresForce) {
                pendingConfirmation = .forceTerminateProject(process)
            }
        case .forceTerminateProject(let process):
            guard let cwd = process.cwd else { return }
            _ = await store.terminateProject(cwd: cwd, force: true)
        }
    }
}

private struct SummaryBadge: View {
    let label: String
    let value: Int
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("\(value)")
                .font(.headline.monospacedDigit())
                .foregroundStyle(tint)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct ProcessRowView: View {
    let process: DevProcess
    let onDetail: () -> Void
    let onCopy: () -> Void
    let onKill: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text("#\(process.pid)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Text(process.name)
                            .font(.headline)
                    }

                    Text(process.cwd ?? "desconocido")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                HStack(spacing: 6) {
                    ProcessActionButton(symbol: "info.circle", title: "Detalle", action: onDetail)
                    ProcessActionButton(symbol: "doc.on.doc", title: "Copiar comando", action: onCopy)
                    ProcessActionButton(symbol: "power", title: "Matar proceso", role: .destructive, action: onKill)
                }
            }

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(process.portSummary)
                        .font(.callout.monospaced())
                    Text(process.appType)
                        .font(.caption.weight(.semibold))
                    Text(process.runtime.label)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 6) {
                    roleBadge
                    ForEach(process.warnings, id: \.self) { warning in
                        badge(for: warning)
                    }
                }
            }
        }
        .padding(12)
        .background(backgroundColor, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(borderColor, lineWidth: 1)
        )
    }

    private var backgroundColor: Color {
        if process.warnings.contains("duplicated") {
            return .orange.opacity(0.08)
        }

        if process.warnings.contains("suspicious") {
            return .red.opacity(0.08)
        }

        return Color(NSColor.windowBackgroundColor)
    }

    private var borderColor: Color {
        if process.warnings.contains("duplicated") {
            return .orange.opacity(0.25)
        }

        if process.warnings.contains("suspicious") {
            return .red.opacity(0.25)
        }

        return .black.opacity(0.06)
    }

    @ViewBuilder
    private var roleBadge: some View {
        switch process.role {
        case .frontend:
            capsule("frontend", color: .green)
        case .backend:
            capsule("backend", color: .blue)
        case .unknown:
            EmptyView()
        }
    }

    @ViewBuilder
    private func badge(for warning: String) -> some View {
        switch warning {
        case "duplicated":
            capsule("duplicated", color: .orange)
        case "suspicious":
            capsule("suspicious", color: .red)
        default:
            EmptyView()
        }
    }

    private func capsule(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.12), in: Capsule())
            .foregroundStyle(color)
    }
}

private struct ProcessActionButton: View {
    let symbol: String
    let title: String
    var role: ButtonRole?
    let action: () -> Void

    var body: some View {
        Button(role: role, action: action) {
            Image(systemName: symbol)
                .frame(width: 16, height: 16)
        }
        .buttonStyle(.borderless)
        .help(title)
    }
}

private struct ProcessDetailView: View {
    let process: DevProcess
    let onCopy: (String) -> Void
    let onKill: () -> Void
    let onKillProject: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(process.name)
                        .font(.title2.weight(.semibold))
                    Text("PID \(process.pid)")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                detailGrid

                detailBlock(title: "Comando completo", value: process.command ?? "desconocido")
                detailBlock(title: "Carpeta de trabajo", value: process.cwd ?? "desconocido")

                commandBlock(title: "Ver por PID", value: process.inspectionCommands.inspectPid)

                if let inspectPorts = process.inspectionCommands.inspectPorts {
                    commandBlock(title: "Ver por puerto", value: inspectPorts)
                }

                commandBlock(title: "Cerrar normal", value: process.inspectionCommands.terminatePid)
                commandBlock(title: "Forzar por PID", value: process.inspectionCommands.forcePid)

                if let forcePorts = process.inspectionCommands.forcePorts {
                    commandBlock(title: "Forzar por puerto", value: forcePorts)
                }

                HStack(spacing: 10) {
                    Button {
                        if let command = process.command {
                            onCopy(command)
                        }
                    } label: {
                        Label("Copiar comando", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.bordered)

                    Button(role: .destructive, action: onKill) {
                        Label("Matar proceso", systemImage: "power")
                    }
                    .buttonStyle(.bordered)

                    if process.cwd != nil {
                        Button(role: .destructive, action: onKillProject) {
                            Label("Matar proyecto", systemImage: "folder.badge.minus")
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .padding(20)
        }
    }

    private var detailGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2), spacing: 12) {
            detailCard(label: "Puertos", value: process.portSummary)
            detailCard(label: "Tipo", value: process.appType)
            detailCard(label: "Runtime", value: process.runtime.label)
            detailCard(label: "Procesos en carpeta", value: "\(process.projectProcessCount)")
        }
    }

    private func detailCard(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 14))
    }

    private func detailBlock(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout.monospaced())
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 14))
    }

    private func commandBlock(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title.uppercased())
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    onCopy(value)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("Copiar")
            }

            Text(value)
                .font(.callout.monospaced())
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 14))
    }
}
