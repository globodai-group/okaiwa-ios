import SwiftUI

public enum PhoneEntryMode {
    case register
    case login
}

/// Phone number entry screen — mirrors `PhoneNumberScreen.kt` on Android.
///
/// Telegram-style layout with Okaiwa branding: title + subtitle centered,
/// tappable country row, phone input with dial code prefix, contacts-sync
/// toggle, lime FAB to submit.
public struct PhoneNumberView: View {
    let mode: PhoneEntryMode
    @Binding var selectedCountry: Country
    let onBack: () -> Void
    let onPickCountry: () -> Void
    let onContinue: (Country, String, Bool) -> Void
    let isLoading: Bool
    let errorMessage: String?

    @State private var phoneDigits: String = ""
    @State private var syncContacts: Bool = true
    @FocusState private var phoneFocused: Bool

    public init(
        mode: PhoneEntryMode,
        selectedCountry: Binding<Country>,
        onBack: @escaping () -> Void,
        onPickCountry: @escaping () -> Void,
        onContinue: @escaping (Country, String, Bool) -> Void,
        isLoading: Bool = false,
        errorMessage: String? = nil
    ) {
        self.mode = mode
        self._selectedCountry = selectedCountry
        self.onBack = onBack
        self.onPickCountry = onPickCountry
        self.onContinue = onContinue
        self.isLoading = isLoading
        self.errorMessage = errorMessage
    }

    private var isSubmittable: Bool { phoneDigits.count >= 6 && !isLoading }

    public var body: some View {
        ZStack {
            OkaiwaColors.black.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                // Back button
                HStack {
                    Button(action: onBack) {
                        Image(systemName: "arrow.backward")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(OkaiwaColors.white)
                            .padding(12)
                    }
                    Spacer()
                }
                .padding(.top, 4)

                Spacer().frame(height: 32)

                // Title block
                VStack(spacing: 12) {
                    Text(mode == .register ? "Votre numéro de téléphone" : "Connexion")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(OkaiwaColors.white)
                        .multilineTextAlignment(.center)

                    Text("Confirmez votre indicatif national\net entrez votre numéro de téléphone.")
                        .font(.system(size: 15))
                        .foregroundStyle(OkaiwaColors.whiteDim)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 32)

                Spacer().frame(height: 32)

                // Form
                VStack(spacing: 16) {
                    CountryField(country: selectedCountry, onTap: onPickCountry)
                    PhoneField(
                        dialCode: selectedCountry.dialCode,
                        digits: $phoneDigits,
                        isFocused: $phoneFocused
                    )
                    SyncContactsToggle(checked: $syncContacts)

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 13))
                            .foregroundStyle(OkaiwaColors.error)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 24)

                Spacer()
            }

            // Submit FAB
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Button {
                        guard isSubmittable else { return }
                        phoneFocused = false
                        onContinue(selectedCountry, phoneDigits, syncContacts)
                    } label: {
                        ZStack {
                            Circle()
                                .fill(isSubmittable ? OkaiwaColors.lime : OkaiwaColors.limeDim)
                                .frame(width: 64, height: 64)
                            if isLoading {
                                ProgressView()
                                    .tint(OkaiwaColors.black)
                            } else {
                                Image(systemName: "arrow.forward")
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundStyle(OkaiwaColors.black)
                            }
                        }
                    }
                    .disabled(!isSubmittable)
                    .padding(.trailing, 24)
                    .padding(.bottom, 24)
                }
            }
        }
        .onAppear { phoneFocused = true }
    }
}

// MARK: - Subviews

private struct CountryField: View {
    let country: Country
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Text(country.flagEmoji)
                    .font(.system(size: 22))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Pays")
                        .font(.system(size: 11))
                        .foregroundStyle(OkaiwaColors.muted)
                    Text(country.name)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(OkaiwaColors.white)
                }
                Spacer()
                Text(country.dialCode)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(OkaiwaColors.whiteDim)
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(OkaiwaColors.muted)
            }
            .padding(.horizontal, 16)
            .frame(height: 56)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(OkaiwaColors.blackBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct PhoneField: View {
    let dialCode: String
    @Binding var digits: String
    var isFocused: FocusState<Bool>.Binding

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Numéro de téléphone")
                .font(.system(size: 12))
                .foregroundStyle(OkaiwaColors.lime)

            HStack(spacing: 8) {
                Text(dialCode)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(OkaiwaColors.white)

                TextField("", text: $digits)
                    .keyboardType(.numberPad)
                    .textContentType(.telephoneNumber)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(OkaiwaColors.white)
                    .tint(OkaiwaColors.lime)
                    .focused(isFocused)
                    .onChange(of: digits) { _, newValue in
                        digits = newValue.filter { $0.isNumber }
                    }
            }
            .padding(.horizontal, 16)
            .frame(height: 48)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        isFocused.wrappedValue ? OkaiwaColors.lime : OkaiwaColors.blackBorder,
                        lineWidth: isFocused.wrappedValue ? 1.5 : 1
                    )
            )
        }
    }
}

private struct SyncContactsToggle: View {
    @Binding var checked: Bool

    var body: some View {
        Button {
            checked.toggle()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: checked ? "checkmark.square.fill" : "square")
                    .font(.system(size: 20))
                    .foregroundStyle(checked ? OkaiwaColors.lime : OkaiwaColors.blackBorder)
                Text("Synchroniser les contacts")
                    .font(.system(size: 15))
                    .foregroundStyle(OkaiwaColors.white)
                Spacer()
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }
}
