// swift-tools-version: 6.0
// SPDX-License-Identifier: MIT
import PackageDescription

// Models and view models of the X1 Scan application. No user interface here,
// so that everything can be tested with `swift test`.
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
        .target(name: "X1ScanCore", dependencies: [.product(name: "X1Kit", package: "X1Kit")]),
        .testTarget(name: "X1ScanCoreTests", dependencies: ["X1ScanCore"]),
    ]
)
