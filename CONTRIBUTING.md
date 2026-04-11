# Contributing to Okaiwa iOS

Thank you for your interest in contributing to Okaiwa. This document provides guidelines and conventions for contributing to the iOS client.

## Code of Conduct

By participating in this project, you agree to uphold a respectful and inclusive environment.

## Getting Started

1. Fork the repository
2. Clone your fork with submodules: `git clone --recursive <your-fork-url>`
3. Create a feature branch from `dev`: `git checkout -b feat/your-feature dev`
4. Make your changes following the guidelines below
5. Push and open a Pull Request against `dev`

## Branch Strategy

| Branch | Purpose |
|--------|---------|
| `main` | Production releases only |
| `rec` | Release candidates, QA |
| `dev` | Active development |

- Feature branches: `feat/short-description`
- Bug fixes: `fix/short-description`
- Hotfixes: `hotfix/short-description`

## Swift Style Guide

### General

- **Swift 5.9+** — Use modern concurrency (`async`/`await`, actors)
- **SwiftUI** for all new views
- **@Observable** macro (not `ObservableObject`) for view models
- **No force unwraps** (`!`) except in tests or guaranteed-safe patterns
- **No `print()`** — Use `os.Logger` for debug output

### Naming

- Types: `UpperCamelCase` (e.g., `ConversationListViewModel`)
- Functions/properties: `lowerCamelCase` (e.g., `sendMessage()`)
- Protocols: Nouns or adjectives (e.g., `ChatRepository`, `Sendable`)
- Use cases: `VerbNounUseCase` (e.g., `SendMessageUseCase`)

### Architecture

Follow **Clean Architecture + MVVM**:

```
Feature/
├── Domain/
│   ├── Entities/        # Pure data models
│   ├── Repositories/    # Protocol definitions
│   └── UseCases/        # Business logic
├── Data/
│   ├── DataSources/     # API, local DB
│   ├── Models/          # DTOs, API models
│   └── Repositories/    # Protocol implementations
└── Presentation/
    ├── ViewModels/      # @Observable, state management
    └── Views/           # SwiftUI views
```

### Security

- **Never log sensitive data** (keys, tokens, message content)
- **Always use Keychain** for secrets (never UserDefaults)
- **Use Secure Enclave** for signing keys when available
- **Validate all server responses** before processing
- **Encrypt local storage** via SQLCipher

## Commit Conventions

Follow [Conventional Commits](https://www.conventionalcommits.org/):

```
type(scope): short description

[optional body]

[optional footer]
```

**Types:** `feat`, `fix`, `refactor`, `test`, `docs`, `chore`, `ci`, `perf`, `security`

**Examples:**

```
feat(chat): add ephemeral message timer UI
fix(wallet): correct gas estimation for EIP-1559
refactor(auth): migrate to @Observable macro
security(crypto): rotate pre-key bundle on session reset
```

## Pull Request Process

1. Ensure your branch is up to date with `dev`
2. All tests must pass: `xcodebuild test`
3. No SwiftLint warnings
4. Fill out the PR template completely
5. Request review from at least one maintainer
6. Security-sensitive changes require two approvals

## Testing

- Unit tests for all use cases and view models
- Integration tests for repository implementations
- Use `XCTest` and `Swift Testing` frameworks
- Mock protocols, not concrete types
- Target: 80%+ code coverage for domain layer

## Questions?

Open a Discussion on GitHub or reach out at contributors@okaiwa.io.

---

Copyright 2026 Globodai FZCO
