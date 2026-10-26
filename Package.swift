// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "Automaatkorrektor",
  platforms: [.macOS(.v14)],
  products: [
    .library(name: "AutomaatkorrektorCore", targets: ["AutomaatkorrektorCore"]),
    .executable(name: "Automaatkorrektor", targets: ["AutomaatkorrektorMacOS"]),
    .executable(name: "NativeTextControlHost", targets: ["NativeTextControlHost"]),
  ],
  dependencies: [
    .package(
      url: "https://github.com/sindresorhus/KeyboardShortcuts.git",
      exact: "3.1.0"
    )
  ],
  targets: [
    .target(name: "AutomaatkorrektorCore"),
    .executableTarget(
      name: "AutomaatkorrektorMacOS",
      dependencies: [
        "AutomaatkorrektorCore",
        .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
      ]
    ),
    .executableTarget(name: "NativeTextControlHost"),
    .testTarget(
      name: "AutomaatkorrektorCoreTests",
      dependencies: ["AutomaatkorrektorCore"]
    ),
    .testTarget(
      name: "AutomaatkorrektorMacOSTests",
      dependencies: ["AutomaatkorrektorMacOS", "AutomaatkorrektorCore"]
    ),
  ]
)
