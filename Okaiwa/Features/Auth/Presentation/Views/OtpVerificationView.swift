import SwiftUI

/// OTP verification screen — mirrors `OtpVerificationScreen.kt` on Android.
///
/// Six digit slots backed by a single hidden TextField. Auto-submits
/// as soon as 6 digits are entered. 60-second resend countdown.
public struct OtpVerificationView: View {
    let phoneNumberDisplay: String
    let onBack: () -> Void
    let onSubmit: (String) -> Void
    let onResend: () -> Void
    let isLoading: Bool
    let errorMessage: String?

    @State private var otp: String = ""
    @State private var secondsRemaining: Int = 60
    @State private var resendTimer: Timer?
    @FocusState private var otpFocused: Bool

    public init(
        phoneNumberDisplay: String,
        onBack: @escaping () -> Void,
        onSubmit: @escaping (String) -> Void,
        onResend: @escaping () -> Void,
        isLoading: Bool = false,
        errorMessage: String? = nil
    ) {
        self.phoneNumberDisplay = phoneNumberDisplay
        self.onBack = onBack
        self.onSubmit = onSubmit
        self.onResend = onResend
        self.isLoading = isLoading
        self.errorMessage = errorMessage
    }

    public var body: some View {
        ZStack {
            OkaiwaColors.black.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
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

                Spacer().frame(height: 40)

                // Title block
                VStack(spacing: 12) {
                    Text("Code à 6 chiffres")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(OkaiwaColors.white)
                        .multilineTextAlignment(.center)

                    Text("Nous venons d'envoyer un code par SMS au\n\(phoneNumberDisplay)")
                        .font(.system(size: 15))
                        .foregroundStyle(OkaiwaColors.whiteDim)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 32)

                Spacer().frame(height: 40)

                // Slots
                OtpSlotsRow(otp: otp, hasError: errorMessage != nil)
                    .padding(.horizontal, 24)

                // Hidden capture field
                TextField("", text: $otp)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .foregroundStyle(.clear)
                    .tint(.clear)
                    .frame(width: 1, height: 1)
                    .opacity(0.01)
                    .focused($otpFocused)
                    .onChange(of: otp) { _, newValue in
                        otp = String(newValue.filter(\.isNumber).prefix(6))
                        if otp.count == 6 && !isLoading {
                            onSubmit(otp)
                        }
                    }

                Spacer().frame(height: 24)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 13))
                        .foregroundStyle(OkaiwaColors.error)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 24)
                    Spacer().frame(height: 16)
                }

                // Resend
                HStack {
                    Spacer()
                    if secondsRemaining > 0 {
                        Text("Renvoyer le code dans \(secondsRemaining)s")
                            .font(.system(size: 13))
                            .foregroundStyle(OkaiwaColors.muted)
                    } else {
                        Button {
                            secondsRemaining = 60
                            startTimer()
                            onResend()
                        } label: {
                            Text("Renvoyer le code")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(OkaiwaColors.lime)
                        }
                    }
                    Spacer()
                }

                // Dev hint — debug builds only.
                if DevConfig.isDebug {
                    Spacer().frame(height: 16)
                    Text("DEV — utilisez 000000 pour passer")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(OkaiwaColors.lime)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 24)
                }

                Spacer()

                // Submit
                Button {
                    guard otp.count == 6 else { return }
                    onSubmit(otp)
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(otp.count == 6 ? OkaiwaColors.lime : OkaiwaColors.limeDim)
                            .frame(height: 56)
                        if isLoading {
                            ProgressView()
                                .tint(OkaiwaColors.black)
                        } else {
                            Text("Continuer")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(OkaiwaColors.black)
                        }
                    }
                }
                .disabled(otp.count != 6 || isLoading)
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
        .onAppear {
            otpFocused = true
            startTimer()
        }
        .onDisappear {
            resendTimer?.invalidate()
            resendTimer = nil
        }
    }

    private func startTimer() {
        resendTimer?.invalidate()
        resendTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            if secondsRemaining > 0 {
                secondsRemaining -= 1
            } else {
                resendTimer?.invalidate()
                resendTimer = nil
            }
        }
    }
}

private struct OtpSlotsRow: View {
    let otp: String
    let hasError: Bool

    var body: some View {
        HStack(spacing: 10) {
            ForEach(0..<6, id: \.self) { index in
                let digit: String = {
                    let idx = otp.index(otp.startIndex, offsetBy: index, limitedBy: otp.endIndex) ?? otp.endIndex
                    return idx < otp.endIndex ? String(otp[idx]) : ""
                }()
                let isFilled = !digit.isEmpty
                let isFocused = index == otp.count && !hasError
                let borderColor: Color = {
                    if hasError { return OkaiwaColors.error }
                    if isFocused || isFilled { return OkaiwaColors.lime }
                    return OkaiwaColors.blackBorder
                }()

                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(OkaiwaColors.blackElevated)
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(borderColor, lineWidth: 1.5)
                    Text(digit)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(OkaiwaColors.white)
                }
                .frame(width: 48, height: 56)
            }
        }
        .frame(maxWidth: .infinity)
    }
}
