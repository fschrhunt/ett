// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ett",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "ett", path: "Sources/ett")
    ]
)
