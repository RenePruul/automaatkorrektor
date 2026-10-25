// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MenuBarInteractionPrototype",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "MenuBarInteractionPrototype",
            path: "Sources"
        )
    ]
)
