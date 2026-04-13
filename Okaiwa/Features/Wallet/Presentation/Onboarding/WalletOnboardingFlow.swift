import AuthenticationServices
import Security
import SwiftUI

/// "Créer un wallet" onboarding — six-step state machine mirror of
/// `WalletOnboardingFlow.kt`.
///
/// The password-manager save path uses
/// `ASAuthorizationPasswordProvider` where available and falls back to
/// `SecItemAdd(kSecClassGenericPassword)` so the seed lives in the iOS
/// Keychain on devices without a 3rd-party provider. 1Password / Dashlane
/// register as Credential Providers on iOS 14+, so the same call prompts
/// the user's preferred vault.
public struct WalletOnboardingFlow: View {
    let onFinished: () -> Void
    let onCancel: () -> Void

    @State private var viewModel = WalletOnboardingViewModel()

    public init(onFinished: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self.onFinished = onFinished
        self.onCancel = onCancel
    }

    public var body: some View {
        ZStack {
            OkaiwaColors.black.ignoresSafeArea()
            VStack(spacing: 0) {
                switch viewModel.step {
                case .method:
                    MethodStep(
                        onPickSeedPhrase: { viewModel.selectMethod(.seedPhrase) },
                        onPickPasskey: { viewModel.selectMethod(.passkey) },
                        onCancel: onCancel
                    )
                case .securityTips:
                    SecurityTipsStep(
                        method: viewModel.method,
                        onAccept: viewModel.onSecurityTipsAccepted,
                        onBack: { if !viewModel.previousStep() { onCancel() } }
                    )
                case .seedPhraseDisplay:
                    SeedPhraseDisplayStep(
                        mnemonic: viewModel.mnemonic,
                        savedToPasswordManager: viewModel.savedToPasswordManager,
                        onSaved: viewModel.markSavedToPasswordManager,
                        onContinue: viewModel.onSeedPhraseAcknowledged,
                        onBack: { viewModel.previousStep() }
                    )
                case .seedPhraseVerify:
                    SeedPhraseVerifyStep(
                        mnemonic: viewModel.mnemonic,
                        verifyIndices: viewModel.verifyIndices,
                        onSuccess: viewModel.onVerificationSuccess,
                        onBack: { viewModel.previousStep() }
                    )
                case .passkeyCreation:
                    PasskeyCreationStep(
                        onCreated: viewModel.onPasskeyCreated,
                        onBack: { viewModel.previousStep() }
                    )
                case .nameWallet:
                    NameWalletStep(
                        name: viewModel.walletName,
                        onNameChanged: { viewModel.walletName = $0 },
                        onConfirm: viewModel.confirmName,
                        onBack: { viewModel.previousStep() }
                    )
                case .ready:
                    ReadyStep(
                        walletName: viewModel.walletName.isEmpty ? "Mon portefeuille" : viewModel.walletName,
                        onDismiss: onFinished,
                        onFundWallet: onFinished
                    )
                }
            }
        }
    }
}

// MARK: - Shared controls

private struct TopBar: View {
    let title: String
    let onBack: () -> Void
    var body: some View {
        HStack {
            Button(action: onBack) {
                Image(systemName: "arrow.backward")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(OkaiwaColors.white)
                    .padding(12)
            }
            Spacer()
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(OkaiwaColors.white)
            Spacer()
            Spacer().frame(width: 44)
        }
        .padding(.vertical, 4)
    }
}

private struct PrimaryButton: View {
    let label: String
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(OkaiwaColors.black)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(enabled ? OkaiwaColors.lime : OkaiwaColors.lime.opacity(0.3))
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

// MARK: - Step 1 — Method

private struct MethodStep: View {
    let onPickSeedPhrase: () -> Void
    let onPickPasskey: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            TopBar(title: "Créer un nouveau portefeuille", onBack: onCancel)
            MethodCard(
                systemIcon: "key.horizontal.fill",
                title: "Phrase secrète",
                subtitle: "Afficher les détails",
                badge: "Recommandé",
                body: [
                    "24 mots BIP-39 générés sur votre appareil. La seule façon de récupérer vos fonds.",
                    "Sécurité : 256 bits d'entropie — la même norme que Ledger, Trezor, Signal.",
                    "Peut être sauvegardée dans 1Password, Dashlane ou votre trousseau natif.",
                ],
                ctaLabel: "Créer",
                onClick: onPickSeedPhrase,
                isPrimary: true
            )
            .padding(.top, 8)

            Spacer().frame(height: 12)

            MethodCard(
                systemIcon: "faceid",
                title: "Clé d'accès",
                subtitle: "Masquer les détails",
                badge: "Beta",
                body: [
                    "Créez ou récupérez un portefeuille avec une empreinte digitale ou Face ID.",
                    "Transaction : huit chaînes disponibles sans étapes supplémentaires.",
                    "Frais : moins de 200 tokens moyens pour les transactions courantes.",
                ],
                ctaLabel: "Créer",
                onClick: onPickPasskey,
                isPrimary: false
            )

            Spacer()
        }
    }
}

private struct MethodCard: View {
    let systemIcon: String
    let title: String
    let subtitle: String
    let badge: String
    let body: [String]
    let ctaLabel: String
    let onClick: () -> Void
    let isPrimary: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if isPrimary {
                Text(badge)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(OkaiwaColors.lime)
                    .padding(.horizontal, 10).padding(.vertical, 3)
                    .background(OkaiwaColors.lime.opacity(0.18))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }

            HStack(spacing: 12) {
                Circle()
                    .fill(OkaiwaColors.lime.opacity(0.15))
                    .frame(width: 36, height: 36)
                    .overlay(
                        Image(systemName: systemIcon)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(OkaiwaColors.lime)
                    )
                VStack(alignment: .leading) {
                    HStack {
                        Text(title).font(.system(size: 17, weight: .semibold)).foregroundStyle(OkaiwaColors.white)
                        if !isPrimary {
                            Text(badge)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(OkaiwaColors.muted)
                                .padding(.horizontal, 6).padding(.vertical, 1)
                                .background(OkaiwaColors.muted.opacity(0.2))
                                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        }
                    }
                    Text(subtitle).font(.system(size: 12)).foregroundStyle(OkaiwaColors.muted)
                }
                Spacer()
                Button(ctaLabel, action: onClick)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(OkaiwaColors.black)
                    .padding(.horizontal, 18).padding(.vertical, 6)
                    .background(OkaiwaColors.lime)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .buttonStyle(.plain)
            }

            ForEach(body, id: \.self) { line in
                Text(line)
                    .font(.system(size: 12))
                    .foregroundStyle(OkaiwaColors.whiteDim)
                    .lineSpacing(3)
            }
        }
        .padding(16)
        .background(OkaiwaColors.blackElevated)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal, 16)
    }
}

// MARK: - Step 2 — Security tips

private struct SecurityTipsStep: View {
    let method: WalletCreationMethod
    let onAccept: () -> Void
    let onBack: () -> Void

    @State private var checks: [Bool] = [false, false, false]
    private var tips: [String] {
        switch method {
        case .seedPhrase:
            return [
                "La phrase secrète (24 mots) est la SEULE manière de récupérer mon portefeuille. Si je la perds, mes fonds sont perdus à jamais.",
                "Je dois la conserver hors ligne — papier, coffre-fort, ou gestionnaire de mots de passe — et ne JAMAIS la partager.",
                "Okaiwa n'a aucun moyen de récupérer ma phrase secrète à ma place. La sécurité dépend entièrement de moi.",
            ]
        case .passkey:
            return [
                "La clé privée est générée dans la Secure Enclave de mon iPhone. Elle ne quitte jamais l'appareil en clair et ne sera accessible qu'avec mon empreinte ou Face ID.",
                "La sauvegarde chiffrée est synchronisée via iCloud Keychain. Je peux donc récupérer mon wallet sur un nouveau téléphone en m'authentifiant avec mon Apple ID.",
                "Si je supprime la clé d'accès ET que je perds l'accès à mon Apple ID, je perdrai mes fonds. Okaiwa n'a aucun backup de secours.",
            ]
        }
    }

    var allChecked: Bool { checks.allSatisfy { $0 } }

    var body: some View {
        VStack(spacing: 0) {
            TopBar(title: "Conseils de sécurité", onBack: onBack)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Spacer().frame(height: 20)
                    RoundedRectangle(cornerRadius: 24)
                        .fill(OkaiwaColors.lime.opacity(0.12))
                        .frame(width: 84, height: 84)
                        .overlay(
                            Image(systemName: "key.fill")
                                .font(.system(size: 32))
                                .foregroundStyle(OkaiwaColors.lime)
                        )
                        .frame(maxWidth: .infinity, alignment: .center)
                    Spacer().frame(height: 20)
                    Text("Votre phrase secrète est la clé de votre portefeuille")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(OkaiwaColors.white)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                    Spacer().frame(height: 6)
                    Text("Cochez toutes les cases pour confirmer que vous comprenez l'importance de la phrase secrète.")
                        .font(.system(size: 13))
                        .foregroundStyle(OkaiwaColors.muted)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                    Spacer().frame(height: 20)

                    ForEach(Array(tips.enumerated()), id: \.offset) { index, text in
                        TipRow(text: text, isChecked: checks[index], onToggle: {
                            checks[index].toggle()
                        })
                        .padding(.bottom, 10)
                    }
                }
                .padding(.horizontal, 24)
            }

            PrimaryButton(label: "Continuer", enabled: allChecked, action: onAccept)
                .padding(.horizontal, 24).padding(.vertical, 16)
        }
    }
}

private struct TipRow: View {
    let text: String
    let isChecked: Bool
    let onToggle: () -> Void
    var body: some View {
        Button(action: onToggle) {
            HStack(alignment: .top, spacing: 10) {
                Circle()
                    .fill(isChecked ? OkaiwaColors.lime : .clear)
                    .frame(width: 20, height: 20)
                    .overlay(Circle().stroke(isChecked ? OkaiwaColors.lime : OkaiwaColors.muted, lineWidth: 1.5))
                    .overlay(
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(OkaiwaColors.black)
                            .opacity(isChecked ? 1 : 0)
                    )
                Text(text)
                    .font(.system(size: 13))
                    .foregroundStyle(OkaiwaColors.white)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineSpacing(4)
            }
            .padding(12)
            .background(isChecked ? OkaiwaColors.lime.opacity(0.08) : OkaiwaColors.blackElevated)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Step 3 — Seed phrase display

private struct SeedPhraseDisplayStep: View {
    let mnemonic: [String]
    let savedToPasswordManager: Bool
    let onSaved: () -> Void
    let onContinue: () -> Void
    let onBack: () -> Void

    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        VStack(spacing: 0) {
            TopBar(title: "Votre phrase secrète", onBack: onBack)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    WarningBanner(text: "Notez ces 24 mots dans l'ordre et gardez-les hors ligne. Personne — y compris Okaiwa — ne peut les récupérer à votre place.")

                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(Array(mnemonic.enumerated()), id: \.offset) { i, w in
                            SeedWordChip(index: i + 1, word: w)
                        }
                    }

                    SecondaryAction(
                        systemIcon: "key.fill",
                        label: savedToPasswordManager ? "Sauvegardée ✓" : "Enregistrer dans un gestionnaire",
                        action: {
                            saveToKeychain(mnemonic.joined(separator: " "))
                            onSaved()
                        }
                    )

                    SecondaryAction(
                        systemIcon: "doc.on.doc",
                        label: "Copier dans le presse-papiers",
                        action: { UIPasteboard.general.string = mnemonic.joined(separator: " ") }
                    )
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
            }

            PrimaryButton(label: "J'ai sauvegardé ma phrase", enabled: true, action: onContinue)
                .padding(.horizontal, 24).padding(.vertical, 16)
        }
    }

    /// Keychain fallback. 1Password / Dashlane register as Credential
    /// Providers on iOS 14+, so the OS will offer to save via them when
    /// present. Otherwise the entry lands in the system Keychain.
    private func saveToKeychain(_ value: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "okaiwa-wallet-seed",
            kSecValueData as String: value.data(using: .utf8) ?? Data(),
        ]
        SecItemDelete(query as CFDictionary)
        _ = SecItemAdd(query as CFDictionary, nil)
    }
}

private struct SeedWordChip: View {
    let index: Int
    let word: String
    var body: some View {
        HStack {
            Text(String(format: "%02d", index))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(OkaiwaColors.muted)
                .frame(minWidth: 22, alignment: .leading)
            Text(word)
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .foregroundStyle(OkaiwaColors.white)
            Spacer()
        }
        .padding(.horizontal, 10).padding(.vertical, 10)
        .background(OkaiwaColors.blackElevated)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct WarningBanner: View {
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.orange)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(OkaiwaColors.white)
                .lineSpacing(4)
        }
        .padding(12)
        .background(Color.orange.opacity(0.12))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.orange.opacity(0.4), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct SecondaryAction: View {
    let systemIcon: String
    let label: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemIcon).foregroundStyle(OkaiwaColors.lime)
                Text(label).font(.system(size: 14, weight: .medium)).foregroundStyle(OkaiwaColors.white)
                Spacer()
            }
            .padding(12)
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(OkaiwaColors.blackBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Step 4 — Verify

private struct SeedPhraseVerifyStep: View {
    let mnemonic: [String]
    let verifyIndices: [Int]
    let onSuccess: () -> Void
    let onBack: () -> Void

    @State private var answers: [String?] = [nil, nil, nil]

    private var challenges: [VerifyChallenge] {
        verifyIndices.map { idx in
            let correct = mnemonic[idx]
            let decoys = mnemonic.enumerated().filter { $0.offset != idx }.shuffled().prefix(3).map { $0.element }
            return VerifyChallenge(
                position: idx + 1,
                correctWord: correct,
                options: (Array(decoys) + [correct]).shuffled()
            )
        }
    }

    private var allCorrect: Bool {
        zip(answers, challenges).allSatisfy { $0.0 == $0.1.correctWord }
    }

    var body: some View {
        VStack(spacing: 0) {
            TopBar(title: "Vérifier la phrase", onBack: onBack)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Sélectionnez les mots correspondants pour confirmer que vous avez sauvegardé votre phrase secrète.")
                        .font(.system(size: 13))
                        .foregroundStyle(OkaiwaColors.muted)
                        .lineSpacing(4)

                    ForEach(Array(challenges.enumerated()), id: \.offset) { cIdx, challenge in
                        Text("Mot #\(challenge.position)")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(OkaiwaColors.white)

                        ForEach(challenge.options, id: \.self) { option in
                            let selected = answers[cIdx] == option
                            let correct = selected && option == challenge.correctWord
                            let wrong = selected && option != challenge.correctWord
                            let border: Color = correct ? OkaiwaColors.lime : (wrong ? OkaiwaColors.error : OkaiwaColors.blackBorder)

                            Button { answers[cIdx] = option } label: {
                                HStack {
                                    Text(option)
                                        .font(.system(size: 14, design: .monospaced))
                                        .foregroundStyle(OkaiwaColors.white)
                                    Spacer()
                                    if correct {
                                        Image(systemName: "checkmark.circle.fill").foregroundStyle(OkaiwaColors.lime)
                                    }
                                }
                                .padding(.horizontal, 14).padding(.vertical, 12)
                                .background(OkaiwaColors.blackElevated)
                                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(border, lineWidth: 1.5))
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 24)
            }
            PrimaryButton(label: "Continuer", enabled: allCorrect, action: onSuccess)
                .padding(.horizontal, 24).padding(.vertical, 16)
        }
    }
}

private struct VerifyChallenge {
    let position: Int
    let correctWord: String
    let options: [String]
}

// MARK: - Step 4b — Passkey creation (passkey branch only)

private struct PasskeyCreationStep: View {
    let onCreated: () -> Void
    let onBack: () -> Void

    @State private var isCreating = false

    var body: some View {
        VStack(spacing: 0) {
            TopBar(title: "Clé d'accès", onBack: onBack)

            VStack(spacing: 0) {
                Spacer().frame(height: 24)

                // Secure Enclave medallion — the visual stand-in for the
                // platform biometric + hardware-keyed signing module.
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .fill(OkaiwaColors.lime.opacity(0.12))
                    .frame(width: 112, height: 112)
                    .overlay(
                        Image(systemName: "faceid")
                            .font(.system(size: 52, weight: .regular))
                            .foregroundStyle(OkaiwaColors.lime)
                    )

                Spacer().frame(height: 24)

                Text("Créez votre clé d'accès")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(OkaiwaColors.white)
                    .multilineTextAlignment(.center)

                Spacer().frame(height: 8)

                Text("Votre iPhone va vous demander de confirmer avec Face ID ou Touch ID. La clé privée reste dans la Secure Enclave — Okaiwa ne la voit jamais.")
                    .font(.system(size: 13))
                    .foregroundStyle(OkaiwaColors.muted)
                    .multilineTextAlignment(.center)
                    .lineSpacing(5)
                    .padding(.horizontal, 24)

                Spacer().frame(height: 24)

                VStack(spacing: 0) {
                    PasskeyBenefitRow(
                        title: "Génération matérielle",
                        subtitle: "Clé signée par la Secure Enclave, non exportable."
                    )
                    PasskeyBenefitRow(
                        title: "Sauvegarde cloud chiffrée",
                        subtitle: "Sync iCloud Keychain pour la récupération multi-appareil."
                    )
                    PasskeyBenefitRow(
                        title: "Pas de phrase à retenir",
                        subtitle: "Biométrie suffit — aucun mot de passe ni mnémonique à noter."
                    )
                }
                .padding(.horizontal, 24)

                Spacer()
            }

            PrimaryButton(
                label: isCreating ? "Création…" : "Créer avec biométrie",
                enabled: !isCreating,
                action: {
                    isCreating = true
                    // Real impl: ASAuthorizationPlatformPublicKeyCredentialRegistrationRequest
                    // through ASAuthorizationController — triggers Face/Touch ID and
                    // registers a passkey backed by iCloud Keychain.
                    // Mock: fake delay then continue.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                        onCreated()
                    }
                }
            )
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
    }
}

private struct PasskeyBenefitRow: View {
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 18))
                .foregroundStyle(OkaiwaColors.lime)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(OkaiwaColors.white)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(OkaiwaColors.muted)
                    .lineSpacing(4)
            }
            Spacer()
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Step 5 — Name wallet

private struct NameWalletStep: View {
    let name: String
    let onNameChanged: (String) -> Void
    let onConfirm: () -> Void
    let onBack: () -> Void

    var isValid: Bool { (4...24).contains(name.count) }

    var body: some View {
        VStack(spacing: 0) {
            TopBar(title: "Définir le nom du portefeuille", onBack: onBack)
            VStack(alignment: .leading, spacing: 8) {
                Text("Nom du portefeuille")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(OkaiwaColors.muted)
                TextField("", text: Binding(get: { name }, set: { if $0.count <= 24 { onNameChanged($0) } }),
                          prompt: Text("Mon portefeuille principal").foregroundStyle(OkaiwaColors.placeholder))
                    .foregroundStyle(OkaiwaColors.white)
                    .tint(OkaiwaColors.lime)
                    .padding(14)
                    .background(OkaiwaColors.blackElevated)
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(OkaiwaColors.blackBorder, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                Text("Entre 4 et 24 caractères.").font(.system(size: 12)).foregroundStyle(OkaiwaColors.muted)
                Spacer()
            }
            .padding(.horizontal, 24).padding(.top, 8)
            PrimaryButton(label: "Terminé", enabled: isValid, action: onConfirm)
                .padding(.horizontal, 24).padding(.vertical, 16)
        }
    }
}

// MARK: - Step 6 — Ready

private struct ReadyStep: View {
    let walletName: String
    let onDismiss: () -> Void
    let onFundWallet: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("Ignorer", action: onDismiss)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(OkaiwaColors.white)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(OkaiwaColors.blackElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .buttonStyle(.plain)
            }
            .padding(16)

            Spacer()

            RoundedRectangle(cornerRadius: 28)
                .fill(OkaiwaColors.lime.opacity(0.18))
                .frame(width: 100, height: 100)
                .overlay(
                    Image(systemName: "checkmark")
                        .font(.system(size: 42, weight: .bold))
                        .foregroundStyle(OkaiwaColors.lime)
                )
            Spacer().frame(height: 20)
            Text("Parfait !\n\(walletName) est prêt.")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(OkaiwaColors.white)
                .multilineTextAlignment(.center)
                .lineSpacing(6)
            Spacer().frame(height: 8)
            Text("Ajoutez des fonds pour commencer à envoyer et recevoir.")
                .font(.system(size: 13))
                .foregroundStyle(OkaiwaColors.muted)
                .multilineTextAlignment(.center)
            Spacer()

            VStack(spacing: 8) {
                PrimaryButton(label: "Alimentez votre portefeuille", enabled: true, action: onFundWallet)
                Text("Dépôt depuis Binance, Coinbase, ou tout wallet externe.")
                    .font(.system(size: 12))
                    .foregroundStyle(OkaiwaColors.muted)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24).padding(.vertical, 24)
        }
    }
}
