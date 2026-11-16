// swift-tools-version: 6.0
// SPDX-License-Identifier: MIT
import PackageDescription

// Models and view models of the X1 Scan application, tested with `swift test`.
// The only views are the reusable components of the compact settings panel
// (Sources/X1ScanCore/UI): no state of their own, no interface text.
let package = Package(
    name: "X1ScanCore",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "X1ScanCore", targets: ["X1ScanCore"]),
    ],
    dependencies: [
        .package(path: "../../X1Kit"),
    ],
    targets: [
        .target(name: "X1ScanCore", dependencies: [.product(name: "X1Kit", package: "X1Kit")],
                resources: [.process("Resources")]),
        .testTarget(name: "X1ScanCoreTests", dependencies: ["X1ScanCore"]),
    ]
)
