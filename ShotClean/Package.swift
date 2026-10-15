// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "ShotClean",
  platforms: [
    .iOS(.v17)
  ],
  products: [
    // An xtool project should contain exactly one library product,
    // representing the main app.
    .library(
      name: "ShotClean",
      targets: ["ShotClean"]
    )
  ],
  dependencies: [
    .package(path: "Packages/ShotCleanCore")
  ],
  targets: [
    .target(
      name: "ShotClean",
      dependencies: [
        .product(name: "ShotCleanCore", package: "ShotCleanCore")
      ]
    )
  ],
  swiftLanguageModes: [.v6]
)
