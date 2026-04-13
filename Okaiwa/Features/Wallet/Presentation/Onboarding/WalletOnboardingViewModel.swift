import Foundation
import Observation

/// Linear state machine for the "Créer un wallet" onboarding — mirrors
/// `WalletOnboardingViewModel.kt` step-for-step.
public enum WalletOnboardingStep {
    case method
    case securityTips
    case seedPhraseDisplay   // seed flow only
    case seedPhraseVerify    // seed flow only
    case passkeyCreation     // passkey flow only — biometric + cloud sync
    case nameWallet
    case ready
}

public enum WalletCreationMethod {
    case seedPhrase
    case passkey
}

@Observable
public final class WalletOnboardingViewModel {
    public var step: WalletOnboardingStep = .method
    public var method: WalletCreationMethod = .seedPhrase
    public private(set) var mnemonic: [String] = []
    public private(set) var verifyIndices: [Int] = []
    public var walletName: String = ""
    public var savedToPasswordManager: Bool = false

    public init() {}

    public func selectMethod(_ m: WalletCreationMethod) {
        method = m
        step = .securityTips
    }

    public func onSecurityTipsAccepted() {
        switch method {
        case .seedPhrase:
            mnemonic = MockMnemonicGenerator.generate24()
            verifyIndices = [
                Int.random(in: 2...7),
                Int.random(in: 10...15),
                Int.random(in: 18...23),
            ]
            step = .seedPhraseDisplay
        case .passkey:
            // Skips seed display + verify — the private key lives in
            // Secure Enclave and the user authenticates with biometrics.
            step = .passkeyCreation
        }
    }

    /// Called by the passkey step after the system biometric prompt.
    public func onPasskeyCreated() {
        step = .nameWallet
    }

    public func onSeedPhraseAcknowledged() {
        step = .seedPhraseVerify
    }

    public func onVerificationSuccess() {
        step = .nameWallet
    }

    public func confirmName() {
        step = .ready
    }

    public func markSavedToPasswordManager() {
        savedToPasswordManager = true
    }

    /// Returns true if we moved back a step, false if already at the
    /// entry step (caller should exit the flow).
    @discardableResult
    public func previousStep() -> Bool {
        let prev: WalletOnboardingStep?
        switch step {
        case .method:             prev = nil
        case .securityTips:       prev = .method
        case .seedPhraseDisplay:  prev = .securityTips
        case .seedPhraseVerify:   prev = .seedPhraseDisplay
        case .passkeyCreation:    prev = .securityTips
        case .nameWallet:
            prev = (method == .seedPhrase) ? .seedPhraseVerify : .passkeyCreation
        case .ready:              prev = nil
        }
        if let prev { step = prev; return true }
        return false
    }
}
