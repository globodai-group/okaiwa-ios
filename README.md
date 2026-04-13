# Okaiwa for iOS — Secure Messenger & Wallet

[![Build](https://github.com/okaiwa/okaiwa-ios/actions/workflows/build.yml/badge.svg)](https://github.com/okaiwa/okaiwa-ios/actions/workflows/build.yml)
[![License: AGPL v3](https://img.shields.io/badge/License-AGPL%20v3-blue.svg)](https://www.gnu.org/licenses/agpl-3.0)
[![Platform](https://img.shields.io/badge/platform-iOS%2017%2B-lightgrey)](https://developer.apple.com/ios/)
[![Swift](https://img.shields.io/badge/Swift-5.9%2B-orange)](https://swift.org)

**Okaiwa** is a privacy-first messenger with an embedded non-custodial crypto wallet. End-to-end encrypted messaging powered by the Signal Protocol, combined with secure on-chain transactions — all in one app.

> *Your messages. Your keys. Your sovereignty.*

---

## Screenshots

| Conversations | Chat | Wallet | Settings |
|:---:|:---:|:---:|:---:|
| *Coming soon* | *Coming soon* | *Coming soon* | *Coming soon* |

---

## Features

- **End-to-end encryption** — Signal Protocol (Double Ratchet, X3DH, Sealed Sender)
- **Ephemeral messages** — Auto-delete with configurable timers
- **Embedded crypto wallet** — Ethereum, Polygon, Arbitrum, Base (non-custodial)
- **Secure Enclave signing** — Private keys never leave the hardware
- **Screen security** — Screenshot prevention, app-switcher masking
- **No metadata leaks** — Sealed sender, hashed contacts, minimal server state
- **Encrypted calls** — VoIP with SRTP encryption (planned)
- **Security score** — Real-time audit of your device security posture

---

## Architecture

```
Okaiwa/
├── App/                    # Application entry point, DI, delegates
├── Core/                   # Config, DI, Navigation, Theme, Errors
├── Features/
│   ├── Auth/               # Registration, verification, key generation
│   ├── Chat/               # Conversations, messages, encryption
│   ├── Contacts/           # Discovery, safety numbers
│   ├── Wallet/             # Multi-chain wallet, transactions
│   ├── Calls/              # Encrypted VoIP
│   ├── Settings/           # Security score, preferences
│   └── Profile/            # User profile management
├── Shared/                 # Utilities, extensions, components
OkaiwaTests/
├── Unit/
└── Integration/
```

**Pattern:** Clean Architecture + MVVM

- **Domain** — Entities, Repository protocols, Use Cases (pure business logic)
- **Data** — Repository implementations, API data sources, local persistence
- **Presentation** — ViewModels (`@Observable`), SwiftUI Views

**Key dependencies** (local SPM packages):

| Package | Purpose |
|---------|---------|
| `SignalCore` | Signal Protocol implementation (X3DH, Double Ratchet) |
| `WalletCore` | HD wallet derivation, transaction signing |
| `CryptoUtils` | PBKDF2, AES-GCM, hashing utilities |
| `OkaiwaDB` | SQLCipher-backed encrypted persistence |
| `APIClient` | Type-safe networking, WebSocket transport |

---

## Requirements

- Xcode 15.0+
- iOS 17.0+
- Swift 5.9+
- macOS 14+ (for building)

## Build

```bash
# Clone with submodules
git clone --recursive https://github.com/okaiwa/okaiwa-ios.git
cd okaiwa-ios

# Resolve SPM dependencies
xcodebuild -resolvePackageDependencies

# Build
xcodebuild -scheme Okaiwa -destination 'platform=iOS Simulator,name=iPhone 15'

# Run tests
xcodebuild test -scheme Okaiwa -destination 'platform=iOS Simulator,name=iPhone 15'
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines on code style, commit conventions, and the PR process.

## Security

If you discover a security vulnerability, please report it responsibly. See [SECURITY.md](SECURITY.md).

## License

This project is licensed under the **GNU Affero General Public License v3.0** — see [LICENSE](LICENSE) for details.

Copyright 2026 Globodai FZCO.
