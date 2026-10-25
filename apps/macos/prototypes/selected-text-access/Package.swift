// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SelectedTextAccessPrototype",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "SelectedTextAccessPrototype",
            path: "Sources"
        )
    ]
)
