import AppKit
import Foundation
import ServiceManagement
import SwiftUI

@MainActor
final class DashboardStore: ObservableObject {
    @Published private(set) var snapshot: ScanSnapshot = .empty
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    @Published var autoRefresh = true {
        didSet { configureRefreshLoop() }
    }
    @Published var refreshInterval: TimeInterval = 5 {
        didSet { configureRefreshLoop() }
    }
    @Published private(set) var launchAtLoginEnabled = false
    @Published private(set) var launchAtLoginStatusText = "Not configured"
    @Published private(set) var launchAtLoginRequiresApproval = false

    private let scanner = ProcessScanner()
    private var refreshTask: Task<Void, Never>?
    private var started = false

    deinit {
        refreshTask?.cancel()
    }

    func start() async {
        guard !started else { return }
        started = true
        await refresh(showLoading: true)
        refreshLaunchAtLoginState()
        configureRefreshLoop()
    }

    func refresh(showLoading: Bool = false) async {
        if showLoading {
            isLoading = true
        }

        do {
            snapshot = try scanner.scan()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    func terminate(_ process: DevProcess, force: Bool = false) async -> ProcessTerminationResult? {
        do {
            let result = try await scanner.terminateProcess(pid: process.pid, force: force)
            await refresh()
            return result
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func terminateProject(cwd: String, force: Bool = false) async -> ProjectTerminationResult? {
        do {
            let result = try await scanner.terminateProject(cwd: cwd, force: force)
            await refresh()
            return result
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            refreshLaunchAtLoginState()
            errorMessage = nil
        } catch {
            refreshLaunchAtLoginState()
            errorMessage = error.localizedDescription
        }
    }

    func openLoginItemsSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") else {
            return
        }

        NSWorkspace.shared.open(url)
    }

    private func configureRefreshLoop() {
        refreshTask?.cancel()
        guard autoRefresh else { return }

        refreshTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(refreshInterval * 1_000_000_000))
                await refresh()
            }
        }
    }

    private func refreshLaunchAtLoginState() {
        let status = SMAppService.mainApp.status

        switch status {
        case .enabled:
            launchAtLoginEnabled = true
            launchAtLoginRequiresApproval = false
            launchAtLoginStatusText = "Enabled"
        case .requiresApproval:
            launchAtLoginEnabled = false
            launchAtLoginRequiresApproval = true
            launchAtLoginStatusText = "Approval required"
        case .notFound:
            launchAtLoginEnabled = false
            launchAtLoginRequiresApproval = false
            launchAtLoginStatusText = "Not found"
        case .notRegistered:
            launchAtLoginEnabled = false
            launchAtLoginRequiresApproval = false
            launchAtLoginStatusText = "Disabled"
        @unknown default:
            launchAtLoginEnabled = false
            launchAtLoginRequiresApproval = false
            launchAtLoginStatusText = "Unknown"
        }
    }
}
