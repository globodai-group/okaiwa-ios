# Security Policy

## Supported Versions

| Version | Supported          |
|---------|--------------------|
| latest  | :white_check_mark: |
| < 1.0   | :x:                |

## Reporting a Vulnerability

If you discover a security vulnerability in Okaiwa, **please report it responsibly**.

**Do NOT open a public GitHub issue.**

Instead, send a detailed report to:

**security@okaiwa.io**

Include the following information:

- Description of the vulnerability
- Steps to reproduce
- Potential impact assessment
- Suggested fix (if any)

### What to Expect

- **Acknowledgement** within 48 hours
- **Assessment and triage** within 5 business days
- **Fix timeline** communicated within 10 business days
- **Credit** in the security advisory (unless you prefer anonymity)

### Scope

The following are in scope:

- End-to-end encryption implementation (Signal Protocol)
- Key management and storage (Keychain, Secure Enclave)
- Wallet private key handling and transaction signing
- Authentication and session management
- Data leakage (screenshots, clipboard, logs, backups)
- Network layer security (certificate pinning, TLS)
- WebSocket transport security

### Out of Scope

- Social engineering attacks
- Denial of service attacks
- Issues in third-party dependencies (report upstream)
- Bugs that require physical access to an unlocked device

## PGP Key

For encrypted communications, request our PGP public key at security@okaiwa.io.

## Acknowledgements

We thank the security research community for helping keep Okaiwa safe.

---

Copyright 2026 Globodai FZCO
