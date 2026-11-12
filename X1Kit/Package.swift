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

        .target(name: "X1TestSupport", dependencies: ["X1Transport"], path: "Tests/X1TestSupport"),
        .testTarget(name: "X1TransportTests", dependencies: ["X1Transport", "X1TestSupport"]),
        .testTarget(name: "X1ProtocolTests", dependencies: ["X1Protocol", "X1Transport", "X1TestSupport"]),
        .testTarget(name: "X1PreviewTests", dependencies: ["X1Preview", "X1Protocol", "X1Transport", "X1TestSupport"]),
        .testTarget(name: "X1ImageTests", dependencies: ["X1Image", "X1Preview", "X1Transport", "X1TestSupport"]),
    ]
)
