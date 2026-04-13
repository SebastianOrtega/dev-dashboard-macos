// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DevDashboardMenuBar",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "dev-dashboard-menubar",
            targets: ["DevDashboardMenuBar"]
        )
    ],
    targets: [
        .executableTarget(
            name: "DevDashboardMenuBar",
            path: "Sources"
        )
    ]
)
