// swift-tools-version: 6.0
// SPDX-License-Identifier: MIT
import PackageDescription

let package = Package(
    name: "X1Kit",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "X1Kit", targets: ["X1Transport", "X1Protocol", "X1Preview", "X1Image"]),
    ],
    targets: [
        // Thin C layer over SCSITaskUserClient (adapted from tools/x1probe). No policy here:
        // the read-only guard lives in X1Transport.IOKitTransport, before any call into this target.
        .target(
            name: "CX1IOKit",
            linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("CoreFoundation")]
        ),
        .target(name: "X1Transport", dependencies: ["CX1IOKit"]),
        .target(name: "X1Protocol", dependencies: ["X1Transport"]),
        .target(name: "X1Preview", dependencies: ["X1Transport", "X1Protocol"]),
        .target(name: "X1Image"),
        // Window calculator, simulator only: no dependency, and not in the X1Kit product, so
        // that nothing in the app or the transport can reach it (docs/decisions.md,
        // "Window calculator"). Only X1Preview may depend on it later (a check of offset 62
        // would live there, before the transport), after CLAUDE.md rule 4 is changed.
        .target(name: "X1Geometry"),

        .target(name: "X1TestSupport", dependencies: ["X1Transport", "X1Protocol"], path: "Tests/X1TestSupport"),
        .testTarget(name: "X1TransportTests", dependencies: ["X1Transport", "X1TestSupport"]),
        .testTarget(name: "X1ProtocolTests", dependencies: ["X1Protocol", "X1Transport", "X1TestSupport"]),
        .testTarget(name: "X1PreviewTests", dependencies: ["X1Preview", "X1Protocol", "X1Transport", "X1TestSupport"]),
        .testTarget(name: "X1GeometryTests", dependencies: ["X1Geometry", "X1TestSupport"]),
        .testTarget(name: "X1ImageTests", dependencies: ["X1Image", "X1Preview", "X1Transport", "X1TestSupport"]),
    ]
)
