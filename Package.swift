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
        // points used by the chat layer.
        //
        // ⚠️ KNOWN LIMITATION (pre-existing — flagged 2026-05-21 by the
        // dependency/security audit, NOT fixed here because the fix is
        // an architecture change out of audit scope):
        //
        // This `.package(url:)` declaration cannot be resolved by
        // SwiftPM. signalapp/libsignal keeps its Package.swift under
        // `swift/`, not at the repo root, and the upstream swift/
        // README states plainly that "Use as a Swift Package ...is not
        // supported" — the canonical integration path is CocoaPods
        // (`pod 'LibSignalClient'`). `swift package resolve` fails with
        // "Package.swift doesn't exist in file system"; only the Xcode
        // build (xcodebuild) papers over it. Migrating libsignal to
        // CocoaPods, or to a root-manifest distribution repo, is the
        // proper fix and should be tracked as its own task.
        //
        // Because the dependency cannot be resolved or built locally,
        // the pin is intentionally LEFT at 0.92.1 (0.94.1 is the latest
        // tag as of 2026-05-21; no security advisory affects 0.92.x —
        // 0.93/0.94 release notes are feature-only). Bumping a pin we
        // cannot resolve, build or test would be unverifiable.
        .package(url: "https://github.com/signalapp/libsignal.git", from: "0.92.1"),

        // Trust Wallet's wallet-core. Provides HDWallet (BIP-39
        // mnemonic) and CoinType-driven address derivation for
        // ETH/BTC/SOL.
        //
        // SECURITY — CVE-2025-66692: a buffer over-read in
        // `PublicKey::verify()` lets a remote peer trigger a DoS by
        // feeding a malformed signature. Fixed upstream in commit
        // 5668c67 (PR #4565), first shipped in the 4.4.0 XCFramework.
        // wallet-core 4.2.9 — the version this project ran until this
        // audit — predates the fix and is vulnerable.
        //
        // We CANNOT fix this by bumping the `.package(url:)` pin:
        // wallet-core's own Package.swift is buggy and hard-codes the
        // 4.2.9 XCFramework `.binaryTarget` URL on EVERY tag through
        // 4.6.9 (verified 2026-05-21 against the repo manifests). A
        // source pin of `from: "4.6.9"` would still resolve the
        // vulnerable 4.2.9 binary at runtime.
        //
        // The real 4.6.9 XCFramework IS published as a release asset
        // — it just isn't referenced by the upstream manifest. So we
        // declare it as a direct `.binaryTarget` below, pointing at
        // the 4.6.9 release zips with checksums verified locally via
        // `swift package compute-checksum` against the canonical
        // `Package.swift` release asset. This pulls the patched
        // binary (CVE-2025-66692 + the 4.6.x address-parsing
        // hardening, PRs #4760-#4763) while keeping `import WalletCore`
        // unchanged at every call site.

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
                // `WalletCore` + `WalletCoreSwiftProtobuf` are local
                // `.binaryTarget`s (see below) pinned to the patched
                // 4.6.9 XCFramework — CVE-2025-66692.
                "WalletCore",
                "WalletCoreSwiftProtobuf",
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

        // MARK: - Trust Wallet wallet-core (binary)
        //
        // Direct `.binaryTarget`s pinned to the wallet-core 4.6.9
        // release XCFrameworks. See the SECURITY note in the
        // `dependencies` block above for why we bypass wallet-core's
        // own (buggy, 4.2.9-pinned) Package.swift. Checksums verified
        // 2026-05-21 with `swift package compute-checksum` against the
        // canonical Package.swift asset of the 4.6.9 GitHub release.
        .binaryTarget(
            name: "WalletCore",
            url: "https://github.com/trustwallet/wallet-core/releases/download/4.6.9/WalletCore.xcframework.zip",
            checksum: "5dcd70cee8b80c8e5b0c2a6aa29b28a22344ee5773d6e0bc625d175b46679fda"
        ),
        .binaryTarget(
            name: "WalletCoreSwiftProtobuf",
            url: "https://github.com/trustwallet/wallet-core/releases/download/4.6.9/WalletCoreSwiftProtobuf.xcframework.zip",
            checksum: "88f83ae22ea8a4f34da3e2f3e78fd97efdb3a1d58599e09063491856826cff76"
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
