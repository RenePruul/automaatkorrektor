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
  targets: [
    .target(name: "AutomaatkorrektorCore"),
    .executableTarget(
      name: "AutomaatkorrektorMacOS",
      dependencies: ["AutomaatkorrektorCore"]
    ),
    .executableTarget(name: "NativeTextControlHost"),
    .testTarget(
      name: "AutomaatkorrektorCoreTests",
      dependencies: ["AutomaatkorrektorCore"]
    ),
    .testTarget(
      name: "AutomaatkorrektorMacOSTests",
      dependencies: ["AutomaatkorrektorMacOS", "AutomaatkorrektorCore"],
      resources: [.copy("Fixtures")]
    ),
  ]
)
