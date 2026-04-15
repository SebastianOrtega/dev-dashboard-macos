import AppKit
import SwiftUI

@main
struct DevDashboardMenuBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        Settings {
            VStack(alignment: .leading, spacing: 12) {
                Text("Dev Dashboard Menu Bar")
                    .font(.headline)
                Text("The app runs natively in Swift and detects processes with lsof/ps.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(20)
            .frame(width: 360)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let store = DashboardStore()
    private let popover = NSPopover()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

    private lazy var statusMenu: NSMenu = {
        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(
            withTitle: "Quit Dev Dashboard",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        return menu
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        configurePopover()
        configureStatusItem()
    }

    func menuDidClose(_ menu: NSMenu) {
        statusItem.menu = nil
    }

    @objc
    private func handleStatusItemClick(_ sender: AnyObject?) {
        guard let button = statusItem.button else { return }

        switch NSApp.currentEvent?.type {
        case .rightMouseUp:
            if popover.isShown {
                popover.performClose(sender)
            }

            statusItem.menu = statusMenu
            button.performClick(sender)
        default:
            togglePopover(relativeTo: button)
        }
    }

    @objc
    private func quitApp() {
        store.quitApp()
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 620, height: 720)
        popover.contentViewController = NSHostingController(
            rootView: MenuBarContentView(store: store)
        )
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }

        button.image = NSImage(
            systemSymbolName: "bolt.horizontal.circle.fill",
            accessibilityDescription: "Dev Dashboard"
        )
        button.image?.isTemplate = true
        button.toolTip = "Dev Dashboard"
        button.target = self
        button.action = #selector(handleStatusItemClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func togglePopover(relativeTo button: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(button)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}
