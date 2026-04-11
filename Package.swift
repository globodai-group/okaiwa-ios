// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Okaiwa",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "OkaiwaCore",
            targets: ["OkaiwaCore"]
        ),
        .library(
            name: "OkaiwaFeatures",
            targets: ["OkaiwaFeatures"]
        ),
        .library(
            name: "OkaiwaShared",
            targets: ["OkaiwaShared"]
        )
    ],
    dependencies: [
        // Local packages — sibling repositories in the Okaiwa workspace.
        // Uncomment when the corresponding repositories are cloned:
        // .package(path: "../okaiwa-signal-core/swift"),
        // .package(path: "../okaiwa-wallet-core/swift"),
        // .package(path: "../okaiwa-crypto-utils/swift"),
        // .package(path: "../okaiwa-server/clients/swift"),
    ],
    targets: [
        // MARK: - Core
        .target(
            name: "OkaiwaCore",
            dependencies: [
                "OkaiwaShared",
            ],
            path: "Okaiwa/Core"
        ),

        // MARK: - Features
        .target(
            name: "OkaiwaFeatures",
            dependencies: [
                "OkaiwaCore",
                "OkaiwaShared",
            ],
            path: "Okaiwa/Features"
        ),

        // MARK: - Shared utilities
        .target(
            name: "OkaiwaShared",
            dependencies: [],
            path: "Okaiwa/Shared"
        ),

        // MARK: - Tests
        .testTarget(
            name: "OkaiwaUnitTests",
            dependencies: [
                "OkaiwaCore",
                "OkaiwaFeatures",
                "OkaiwaShared",
            ],
            path: "OkaiwaTests/Unit"
        ),
        .testTarget(
            name: "OkaiwaIntegrationTests",
            dependencies: [
                "OkaiwaCore",
                "OkaiwaFeatures",
            ],
            path: "OkaiwaTests/Integration"
        ),
    ]
)
