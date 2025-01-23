// swift-tools-version:6.0
import PackageDescription

let package = Package(
  name: "SwiftJSONSanitizer",
  platforms: [
    .macOS(.v10_15),
    .iOS(.v13),
    .tvOS(.v12),
    .watchOS(.v9)
  ],
  products: [
    .library(
      name: "SwiftJSONSanitizerDynamic",
      type: .dynamic,
      targets: ["SwiftJSONSanitizer"]
    ),
    .library(
      name: "SwiftJSONSanitizer",
      targets: ["SwiftJSONSanitizer"]
    ),
  ],
  targets: [
    .target(
      name: "SwiftJSONSanitizer",
      dependencies: [],
      linkerSettings: [
        .unsafeFlags(["-Wl,-make_mergeable"])
      ]),
    .testTarget(
      name: "SwiftJSONSanitizerTests",
      dependencies: ["SwiftJSONSanitizer"]
    )
  ]
)
