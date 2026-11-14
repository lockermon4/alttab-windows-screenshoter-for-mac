// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "QuickTab",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "QuickTab",
            path: "Sources/QuickTab",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("ServiceManagement"),
            ]
        )
    ]
)
