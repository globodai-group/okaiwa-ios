// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Okaiwa",
    // Development-language base. Every `Localizable.strings` entry
    // gets a guaranteed French fallback — if the runtime locale points
    // at a language we haven't shipped yet (e.g. Spanish), SwiftUI
    // resolves against this table rather than the English twin. See
    // `LocaleManager` for the override path.
    defaultLocalization: "fr",
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

        // Signal Foundation's official Swift bindings for the Signal
        // Protocol. Provides IdentityKeyPair, SignedPreKeyRecord,
        // session stores and the signalEncrypt/signalDecrypt entry
        // points used by the chat layer. Pinned to a confirmed stable
        // tag on github.com/signalapp/libsignal (latest verified at
        // v0.92.1 on 2026-04-09).
        .package(url: "https://github.com/signalapp/libsignal.git", from: "0.92.1"),

        // Trust Wallet's wallet-core, distributed as an XCFramework
        // via SPM. Provides HDWallet (BIP-39 mnemonic) and CoinType-
        // driven address derivation for ETH/BTC/SOL. Pinned against
        // the binary target URL published by the project. Note that
        // the upstream Package.swift on tag 4.6.3 still references
        // the 4.2.9 XCFramework zip at runtime — see the release
        // notes on github.com/trustwallet/wallet-core for context.
        .package(url: "https://github.com/trustwallet/wallet-core.git", from: "4.2.9"),

        // GRDB.swift + SQLCipher — on-device encrypted conversation
        // store (mirror of Android's Room + SQLCipher setup in
        // `OkaiwaDatabase.kt`). Canonical upstream GRDB ships source
        // only; wiring SQLCipher into an SPM-only project requires a
        // separate C target and a custom defines file, which Apple's
        // SwiftPM still can't express cleanly in 2026.
        //
        // DuckDuckGo maintains a well-scoped fork that bundles
        // SQLCipher Community Edition into an XCFramework and exposes
        // the same GRDB product. The package is consumed in production
        // by the DuckDuckGo iOS app (same threat model as ours: per-
        // install 32-byte passphrase in Keychain, AES-256 pages, HMAC
        // page integrity). Their releases track upstream GRDB with a
        // short lag (3.0.0 ≈ GRDB 7.4.1 + SQLCipher 4.7.0 as of
        // 2026-03 — see https://github.com/duckduckgo/GRDB.swift).
        //
        // We depend on the DuckDuckGo fork and import it as `GRDB`
        // in source files exactly as we would the upstream. The chat
        // layer's DAO patterns (Features/Chat/Data/Local/*.swift) run
        // identically either way — switching back to upstream GRDB
        // once Apple fixes SPM + C target interop is a one-line
        // Package.swift change.
        .package(url: "https://github.com/duckduckgo/GRDB.swift.git", from: "3.0.0"),
    ],
    targets: [
        // MARK: - Core
        .target(
            name: "OkaiwaCore",
            dependencies: [
                "OkaiwaShared",
            ],
            path: "Okaiwa/Core",
            // `.process("Resources")` runs the localization pipeline on
            // every `*.lproj/Localizable.strings` file under this
            // directory, generating a `Localizable.strings` per locale
            // in the module bundle. AppError.swift resolves copy via
            // `String(localized:, bundle: .module)`.
            resources: [
                .process("Resources"),
            ]
        ),

        // MARK: - Features
        .target(
            name: "OkaiwaFeatures",
            dependencies: [
                "OkaiwaCore",
                "OkaiwaShared",
                .product(name: "LibSignalClient", package: "libsignal"),
                .product(name: "WalletCore", package: "wallet-core"),
                // DuckDuckGo fork exposes the `GRDB` product identical
                // to upstream groue/GRDB.swift — call sites stay on
                // `import GRDB`. SQLCipher is bundled into the
                // XCFramework so there is no separate sqlcipher target
                // to pin here.
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            path: "Okaiwa/Features",
            // Same resource-bundle mechanism as OkaiwaCore. Every
            // `LocalizedStringKey("…")` and `String(localized: "…")`
            // site in Features/* resolves against `Bundle.module` for
            // OkaiwaFeatures, which picks up the localized strings
            // processed from `Resources/en.lproj` and `Resources/fr.lproj`.
            resources: [
                .process("Resources"),
            ]
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
