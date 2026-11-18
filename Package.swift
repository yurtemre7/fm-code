// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "fm-code",
    platforms: [.macOS(.v26)],
    targets: [
        .target(name: "FMCodeCore"),
        .executableTarget(name: "fm-code", dependencies: ["FMCodeCore"]),
        .testTarget(name: "FMCodeCoreTests", dependencies: ["FMCodeCore"]),
    ]
)
