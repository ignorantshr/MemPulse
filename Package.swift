// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MemPulse",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "MemPulse", targets: ["MemPulse"])],
    targets: [
        .target(name: "ProcessProbe"),
        .executableTarget(name: "MemPulse", dependencies: ["ProcessProbe"]),
        .testTarget(name: "MemPulseTests", dependencies: ["MemPulse"])
    ]
)
