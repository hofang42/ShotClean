// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "ShotCleanCore",
  platforms: [.iOS(.v17), .macOS(.v14)],
  products: [
    .library(name: "ShotCleanCore", targets: ["ShotCleanCore"])
  ],
  targets: [
    .target(name: "ShotCleanCore"),
    .testTarget(
      name: "ShotCleanCoreTests",
      dependencies: ["ShotCleanCore"],
      resources: [.copy("Fixtures")]
    ),
  ],
  swiftLanguageModes: [.v6]
)
