// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "KhaiCleanMac",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "KhaiCleanMac",
            path: "Sources/KhaiCleanMac"
        )
    ]
)
