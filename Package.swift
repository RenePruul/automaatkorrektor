// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "Automaatkorrektor",
  platforms: [.macOS(.v14)],
  products: [
    .library(name: "AutomaatkorrektorCore", targets: ["AutomaatkorrektorCore"]),
    .executable(name: "Automaatkorrektor", targets: ["AutomaatkorrektorMacOS"]),
  ],
  targets: [
    .target(name: "AutomaatkorrektorCore"),
    .executableTarget(
      name: "AutomaatkorrektorMacOS",
      dependencies: ["AutomaatkorrektorCore"]
    ),
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
