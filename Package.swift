// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "vscreen",
    platforms: [.macOS("26.0")],
    targets: [
        .target(
            name: "CPrivate",
            path: "Sources/CPrivate"
        ),
        .executableTarget(
            name: "vscreen",
            dependencies: ["CPrivate"],
            path: "Sources/vscreen"
        ),
        .executableTarget(
            name: "vscreen-fixture",
            path: "Sources/vscreen-fixture"
        ),
    ]
)
