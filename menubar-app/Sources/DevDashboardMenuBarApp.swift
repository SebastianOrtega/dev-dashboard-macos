import AppKit
import SwiftUI

@main
struct DevDashboardMenuBarApp: App {
    @StateObject private var store = DashboardStore()

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra("Dev Dashboard", systemImage: "bolt.horizontal.circle.fill") {
            MenuBarContentView(store: store)
        }
        .menuBarExtraStyle(.window)

        Settings {
            VStack(alignment: .leading, spacing: 12) {
                Text("Dev Dashboard Menubar")
                    .font(.headline)
                Text("La app corre nativamente en Swift y detecta procesos usando lsof/ps.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(20)
            .frame(width: 360)
        }
    }
}
