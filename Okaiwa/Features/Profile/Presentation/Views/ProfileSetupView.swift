import SwiftUI
import Observation

/// Post-OTP profile setup view — iOS mirror of `ProfileSetupScreen.kt`.
///
/// Asks the user for a username (required, validated against the same
/// `[a-zA-Z0-9_]{3,32}` regex the server enforces) plus optional
/// displayName + bio. Pushes the user to the Main scaffold once either
/// Submit succeeds or Skip is tapped — the SessionStore flag
/// `profileSetupDone` is flipped in both paths so the splash never
/// re-asks on subsequent cold starts.
@MainActor
struct ProfileSetupView: View {
    let sessionStore: SessionStore
    let onDone: () -> Void

    @State private var model: ProfileSetupModel

    init(sessionStore: SessionStore, onDone: @escaping () -> Void) {
        self.sessionStore = sessionStore
        self.onDone = onDone
        _model = State(initialValue: ProfileSetupModel(sessionStore: sessionStore))
    }

    var body: some View {
        ZStack {
            OkaiwaColors.black.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Spacer().frame(height: 32)

                    HStack {
                        Spacer()
                        // Lime-tinted avatar placeholder — same pattern
                        // as the wallet onboarding screens.
                        Image(systemName: "person.crop.circle")
                            .font(.system(size: 64))
                            .foregroundStyle(OkaiwaColors.lime)
                            .frame(width: 96, height: 96)
                            .background(OkaiwaColors.lime.opacity(0.12))
                            .clipShape(Circle())
                        Spacer()
                    }

                    Spacer().frame(height: 20)

                    Text("Choisissez votre nom d'utilisateur")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(OkaiwaColors.white)
                    Spacer().frame(height: 8)
                    Text("Vos contacts pourront vous trouver avec ce nom. Vous pourrez le changer plus tard depuis votre profil.")
                        .font(.system(size: 14))
                        .foregroundStyle(OkaiwaColors.whiteDim)
                        .lineSpacing(4)

                    Spacer().frame(height: 24)

                    UsernameField(value: $model.username, isValid: model.isUsernameValid || model.username.isEmpty)
                    Spacer().frame(height: 12)
                    PlainField(value: $model.displayName, placeholder: "Nom affiché (optionnel)", maxLength: 64)
                    Spacer().frame(height: 12)
                    PlainField(value: $model.bio, placeholder: "Bio (optionnel)", maxLength: 300, multiline: true)

                    if let error = model.error {
                        Spacer().frame(height: 16)
                        Text(error)
                            .font(.system(size: 13))
                            .foregroundStyle(OkaiwaColors.error)
                    }

                    Spacer().frame(height: 24)

                    Button {
                        Task { await model.submit() }
                    } label: {
                        ZStack {
                            if model.isSubmitting {
                                ProgressView()
                                    .tint(OkaiwaColors.black)
                            } else {
                                Text("Enregistrer mon profil")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(OkaiwaColors.black)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(model.isSubmitEnabled ? OkaiwaColors.lime : OkaiwaColors.lime.opacity(0.3))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(!model.isSubmitEnabled)

                    Spacer().frame(height: 8)

                    Button {
                        model.skip()
                    } label: {
                        Text("Passer pour l'instant")
                            .font(.system(size: 14))
                            .foregroundStyle(OkaiwaColors.whiteDim)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 24)
            }
        }
        .onChange(of: model.done) { _, isDone in
            if isDone { onDone() }
        }
    }
}

private struct UsernameField: View {
    @Binding var value: String
    let isValid: Bool

    var body: some View {
        TextField("", text: Binding(
            get: { value },
            set: { newValue in
                // Live-strip non-allowed characters so the regex never
                // sees them; the visible field stays in [a-zA-Z0-9_].
                value = newValue.filter { $0.isLetter || $0.isNumber || $0 == "_" }
            }
        ), prompt: Text("@nomutilisateur").foregroundStyle(OkaiwaColors.placeholder))
            .foregroundStyle(OkaiwaColors.white)
            .tint(OkaiwaColors.lime)
            .padding(14)
            .background(OkaiwaColors.blackElevated)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isValid ? OkaiwaColors.blackBorder : OkaiwaColors.error, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
    }
}

private struct PlainField: View {
    @Binding var value: String
    let placeholder: String
    let maxLength: Int
    var multiline: Bool = false

    var body: some View {
        TextField(
            "",
            text: Binding(
                get: { value },
                set: { value = String($0.prefix(maxLength)) }
            ),
            prompt: Text(placeholder).foregroundStyle(OkaiwaColors.placeholder),
            axis: multiline ? .vertical : .horizontal
        )
            .lineLimit(multiline ? 1...4 : 1)
            .foregroundStyle(OkaiwaColors.white)
            .tint(OkaiwaColors.lime)
            .padding(14)
            .background(OkaiwaColors.blackElevated)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(OkaiwaColors.blackBorder, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

@MainActor
@Observable
final class ProfileSetupModel {
    var username: String = ""
    var displayName: String = ""
    var bio: String = ""
    var isSubmitting: Bool = false
    var error: String? = nil
    var done: Bool = false

    private let sessionStore: SessionStore
    private let client: IdentityProfileClient

    init(sessionStore: SessionStore, client: IdentityProfileClient = IdentityProfileClient()) {
        self.sessionStore = sessionStore
        self.client = client
    }

    var isUsernameValid: Bool {
        username.range(of: "^[a-zA-Z0-9_]{3,32}$", options: .regularExpression) != nil
    }

    var isSubmitEnabled: Bool { !isSubmitting && isUsernameValid }

    func submit() async {
        guard isSubmitEnabled else { return }
        guard let accountId = sessionStore.current?.accountId, !accountId.isEmpty else {
            error = "Session expirée — reconnectez-vous."
            return
        }
        isSubmitting = true
        error = nil
        defer { isSubmitting = false }

        do {
            _ = try await client.updateProfile(
                accountId: accountId,
                body: UpdateProfileRequest(
                    username: username,
                    displayName: displayName.isEmpty ? nil : displayName,
                    bio: bio.isEmpty ? nil : bio,
                    avatarUrl: nil,
                    visibility: nil,
                    exposedWalletAddresses: nil
                )
            )
            sessionStore.markProfileSetupDone()
            done = true
        } catch ProfileClientError.usernameTaken {
            error = "Ce nom d'utilisateur est déjà pris."
        } catch let appError as AppError {
            error = appError.errorDescription ?? "Erreur réseau"
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Skip — no PUT call. The user lands on Main without a username;
    /// the Profile tab CTA will prompt them to complete it later.
    func skip() {
        sessionStore.markProfileSetupDone()
        done = true
    }
}
