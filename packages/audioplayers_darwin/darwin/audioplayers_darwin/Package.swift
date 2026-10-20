// swift-tools-version: 5.9

import PackageDescription

let package = Package(
  name: "audioplayers_darwin",
  platforms: [
    .iOS("13.0"),
    .macOS("10.15"),
  ],
  products: [
    .library(name: "audioplayers-darwin", targets: ["audioplayers_darwin"])
  ],
  dependencies: [
    .package(name: "FlutterFramework", path: "../FlutterFramework")
  ],
  targets: [
    .target(
      name: "audioplayers_darwin",
      dependencies: [
        .product(name: "FlutterFramework", package: "FlutterFramework")
      ]
    )
  ]
)
