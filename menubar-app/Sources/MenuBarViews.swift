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
            return "Terminate process"
        case .forceTerminate:
            return "Force quit process"
        case .terminateProject:
            return "Terminate project"
        case .forceTerminateProject:
            return "Force quit project"
        }
    }

    var message: String {
        switch self {
        case .terminate(let process):
            return "SIGTERM will be sent to process \(process.pid) (\(process.name))."
        case .forceTerminate(let process):
            return "Process \(process.pid) is still running. This will send SIGKILL."
        case .terminateProject(let process):
            return "SIGTERM will be sent to the processes detected in \(process.cwd ?? "this project")."
        case .forceTerminateProject:
            return "One or more project processes are still running. This will send SIGKILL."
        }
    }

    var confirmLabel: String {
        switch self {
        case .terminate, .terminateProject:
            return "Terminate"
        case .forceTerminate, .forceTerminateProject:
            return "Force quit"
        }
    }
}

struct MenuBarContentView: View {
    @ObservedObject var store: DashboardStore

    @State private var searchText = ""
    @State private var selectedProcess: DevProcess?
    @State private var pendingConfirmation: PendingConfirmation?

    private var isShowingOverlay: Bool {
        selectedProcess != nil || pendingConfirmation != nil
    }

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
        ZStack {
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
            .blur(radius: isShowingOverlay ? 1.5 : 0)
            .allowsHitTesting(!isShowingOverlay)

            if isShowingOverlay {
                overlayLayer
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .animation(.easeInOut(duration: 0.16), value: isShowingOverlay)
        .task {
            await store.start()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Dev Dashboard")
                        .font(.title3.weight(.semibold))
                    Text("Monitor development processes from the menu bar")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if store.isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            Text("Last refresh: \(store.snapshot.generatedAt.formatted(date: .omitted, time: .standard))")
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
                TextField("Search by port, PID, name, or command", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))

            HStack {
                Toggle("Auto refresh", isOn: $store.autoRefresh)
                    .toggleStyle(.switch)

                Picker("Interval", selection: $store.refreshInterval) {
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
                    Button("Open Settings") {
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
                        Text("No processes detected")
                            .font(.headline)
                        Text("No development processes are listening on ports.")
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
            Text("Ports 7000 and 7001 are still excluded to keep compatibility with the web version.")
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

    @ViewBuilder
    private var overlayLayer: some View {
        ZStack {
            Rectangle()
                .fill(.black.opacity(0.18))
                .ignoresSafeArea()

            if let process = selectedProcess {
                ProcessDetailOverlayView(
                    process: latestProcess(for: process),
                    onClose: { selectedProcess = nil },
                    onCopy: { store.copyToClipboard($0) },
                    onKill: { pendingConfirmation = .terminate(latestProcess(for: process)) },
                    onKillProject: {
                        let latest = latestProcess(for: process)
                        if latest.cwd != nil {
                            pendingConfirmation = .terminateProject(latest)
                        }
                    }
                )
                .frame(maxWidth: 560, maxHeight: 640)
                .padding(20)
            }

            if let confirmation = pendingConfirmation {
                ConfirmationOverlayView(
                    title: confirmation.title,
                    message: confirmation.message,
                    confirmLabel: confirmation.confirmLabel,
                    onCancel: { pendingConfirmation = nil },
                    onConfirm: {
                        let current = confirmation
                        pendingConfirmation = nil
                        Task { await handleConfirmation(current) }
                    }
                )
                .frame(maxWidth: 420)
                .padding(24)
            }
        }
        .zIndex(10)
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

                    Text(process.cwd ?? "unknown")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                HStack(spacing: 6) {
                    ProcessActionButton(symbol: "info.circle", title: "Details", action: onDetail)
                    ProcessActionButton(symbol: "doc.on.doc", title: "Copy command", action: onCopy)
                    ProcessActionButton(symbol: "power", title: "Terminate process", role: .destructive, action: onKill)
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

private struct ProcessDetailOverlayView: View {
    let process: DevProcess
    let onClose: () -> Void
    let onCopy: (String) -> Void
    let onKill: () -> Void
    let onKillProject: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Process details")
                    .font(.headline)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Close")
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 12)

            Divider()

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

                    detailBlock(title: "Full command", value: process.command ?? "unknown")
                    detailBlock(title: "Working directory", value: process.cwd ?? "unknown")

                    commandBlock(title: "Inspect by PID", value: process.inspectionCommands.inspectPid)

                    if let inspectPorts = process.inspectionCommands.inspectPorts {
                        commandBlock(title: "Inspect by port", value: inspectPorts)
                    }

                    commandBlock(title: "Terminate gracefully", value: process.inspectionCommands.terminatePid)
                    commandBlock(title: "Force quit by PID", value: process.inspectionCommands.forcePid)

                    if let forcePorts = process.inspectionCommands.forcePorts {
                        commandBlock(title: "Force quit by port", value: forcePorts)
                    }

                    HStack(spacing: 10) {
                        Button {
                            if let command = process.command {
                                onCopy(command)
                            }
                        } label: {
                            Label("Copy command", systemImage: "doc.on.doc")
                        }
                        .buttonStyle(.bordered)

                        Button(role: .destructive, action: onKill) {
                            Label("Terminate process", systemImage: "power")
                        }
                        .buttonStyle(.bordered)

                        if process.cwd != nil {
                            Button(role: .destructive, action: onKillProject) {
                                Label("Terminate project", systemImage: "folder.badge.minus")
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
                .padding(20)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(NSColor.windowBackgroundColor))
                .shadow(color: .black.opacity(0.16), radius: 24, y: 10)
        )
    }

    private var detailGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2), spacing: 12) {
            detailCard(label: "Ports", value: process.portSummary)
            detailCard(label: "Type", value: process.appType)
            detailCard(label: "Runtime", value: process.runtime.label)
            detailCard(label: "Processes in folder", value: "\(process.projectProcessCount)")
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
                .help("Copy")
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

private struct ConfirmationOverlayView: View {
    let title: String
    let message: String
    let confirmLabel: String
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.headline)

            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .buttonStyle(.bordered)
                Button(confirmLabel, role: .destructive, action: onConfirm)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(NSColor.windowBackgroundColor))
                .shadow(color: .black.opacity(0.16), radius: 20, y: 8)
        )
    }
}
