// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 Globodai FZCO

import Foundation
import os

// MARK: - Dependency Container

/// Lightweight dependency injection container.
///
/// No third-party frameworks — uses a simple key-value store with type-safe resolution.
/// Supports lazy initialization and singleton lifecycle.
///
/// Usage:
/// ```swift
/// DependencyContainer.shared.register(AuthRepository.self) { RemoteAuthRepository() }
/// let repo: AuthRepository = DependencyContainer.shared.resolve()
/// ```
@Observable
final class DependencyContainer: @unchecked Sendable {

    static let shared = DependencyContainer()

    private let logger = Logger(subsystem: "io.okaiwa.app", category: "DI")
    private var factories: [String: () -> Any] = [:]
    private var singletons: [String: Any] = [:]
    private let lock = NSRecursiveLock()

    // MARK: - Well-Known Dependencies

    private(set) var authViewModel = AuthViewModel()
    private(set) var router = AppRouter()

    private init() {}

    // MARK: - Registration

    /// Register a factory closure for a given protocol or type.
    func register<T>(_ type: T.Type, factory: @escaping () -> T) {
        let key = String(describing: type)
        lock.lock()
        defer { lock.unlock() }
        factories[key] = factory
        logger.debug("Registered dependency: \(key)")
    }

    /// Register a pre-built singleton instance.
    func registerSingleton<T>(_ type: T.Type, instance: T) {
        let key = String(describing: type)
        lock.lock()
        defer { lock.unlock() }
        singletons[key] = instance
        logger.debug("Registered singleton: \(key)")
    }

    // MARK: - Resolution

    /// Resolve a dependency by type. Returns a singleton if available, otherwise
    /// creates via factory and caches as singleton.
    func resolve<T>(_ type: T.Type = T.self) -> T {
        let key = String(describing: type)
        lock.lock()
        defer { lock.unlock() }

        // Check singleton cache first
        if let cached = singletons[key] as? T {
            return cached
        }

        // Create from factory and cache
        guard let factory = factories[key] else {
            fatalError("No dependency registered for \(key). Call register() before resolve().")
        }

        guard let instance = factory() as? T else {
            fatalError("Factory for \(key) returned wrong type.")
        }

        singletons[key] = instance
        logger.debug("Resolved and cached: \(key)")
        return instance
    }

    /// Resolve optionally — returns nil if not registered.
    func resolveOptional<T>(_ type: T.Type = T.self) -> T? {
        let key = String(describing: type)
        lock.lock()
        defer { lock.unlock() }

        if let cached = singletons[key] as? T {
            return cached
        }

        guard let factory = factories[key],
              let instance = factory() as? T else {
            return nil
        }

        singletons[key] = instance
        return instance
    }

    // MARK: - Bootstrap

    /// Register all application dependencies.
    /// Called once during app initialization.
    func bootstrap() {
        logger.info("Bootstrapping dependency container")

        // Shared utilities
        registerSingleton(KeychainManager.self, instance: KeychainManager())
        registerSingleton(SecureEnclaveManager.self, instance: SecureEnclaveManager())

        // ViewModels are @Observable and held directly
        authViewModel = AuthViewModel()
        router = AppRouter()

        logger.info("Dependency container bootstrapped")
    }

    /// MainActor-isolated resolver for the identity-auth service — the
    /// service is @MainActor and holds a SessionStore.shared reference
    /// so the lazy factory in `resolve()` can't materialize it without
    /// main-actor context. `@MainActor` annotation on the accessor
    /// lets SwiftUI `.task { }` hops call it cleanly.
    @MainActor
    func identityAuthService() -> IdentityAuthService {
        let key = String(describing: IdentityAuthService.self)
        lock.lock()
        defer { lock.unlock() }
        if let cached = singletons[key] as? IdentityAuthService {
            return cached
        }
        let fresh = IdentityAuthService(sessionStore: SessionStore.shared)
        singletons[key] = fresh
        return fresh
    }

    // MARK: - Testing

    /// Reset all registrations. For testing only.
    func reset() {
        lock.lock()
        defer { lock.unlock() }
        factories.removeAll()
        singletons.removeAll()
        logger.warning("Dependency container reset — testing only")
    }
}

// MARK: - Property Wrapper

/// Property wrapper for injecting dependencies from the shared container.
///
/// ```swift
/// @Injected var authRepo: AuthRepository
/// ```
@propertyWrapper
struct Injected<T> {
    private let type: T.Type

    var wrappedValue: T {
        DependencyContainer.shared.resolve(type)
    }

    init(_ type: T.Type = T.self) {
        self.type = type
    }
}
