// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "PermissionOnboardingPrototype",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "PermissionOnboardingPrototype",
            path: "Sources"
        )
    ]
)
