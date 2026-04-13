import SwiftUI

/// OTP verification screen — mirrors `OtpVerificationScreen.kt`.
///
/// A full-width invisible `TextField` captures input behind the slot row;
/// `.allowsHitTesting(false)` on the slot overlay lets taps, long-press,
/// and paste gestures fall through to the field. Because the field is
/// full width:
///   - iOS paste from clipboard populates all six slots at once.
///   - `.textContentType(.oneTimeCode)` triggers SMS autofill.
///   - The paste menu appears anywhere over the slot row, not just in
///     a 1-pixel hit target.
///
/// Each slot uses `.frame(maxWidth: .infinity).aspectRatio(...)` so the
/// six boxes distribute the available width equally — no more "5 uniform
/// + 1 squeezed" layout on narrow devices.
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

                VStack(spacing: 12) {
                    Text(L10n.key("otp_title"))
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(OkaiwaColors.white)
                        .multilineTextAlignment(.center)

                    // `%@` is the recipient phone; the format string
                    // already embeds the newline so both locales keep
                    // the phone number on its own line.
                    Text(L10n.string("otp_subtitle_format", phoneNumberDisplay))
                        .font(.system(size: 15))
                        .foregroundStyle(OkaiwaColors.whiteDim)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 32)

                Spacer().frame(height: 40)

                // Capture field + visual slots overlay.
                ZStack {
                    // Invisible full-width capture field. foregroundStyle
                    // .clear + tint .clear hide the text + cursor; opacity
                    // is left at 1 so the system still routes taps,
                    // long-press, paste menu, and SMS autofill here.
                    TextField("", text: $otp)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                        .foregroundStyle(.clear)
                        .tint(.clear)
                        .multilineTextAlignment(.center)
                        .focused($otpFocused)
                        .onChange(of: otp) { _, newValue in
                            let digits = String(newValue.filter(\.isNumber).prefix(6))
                            if digits != otp {
                                otp = digits
                            }
                            if otp.count == 6 && !isLoading {
                                onSubmit(otp)
                            }
                        }

                    // Visual slots sit on top, non-interactive so the
                    // TextField below still receives gestures.
                    OtpSlotsRow(otp: otp, hasError: errorMessage != nil)
                        .allowsHitTesting(false)
                }
                .padding(.horizontal, 24)

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

                HStack {
                    Spacer()
                    if secondsRemaining > 0 {
                        // `%d` expands to the raw seconds — the format
                        // string carries the unit suffix ("s") so the
                        // English/French copy can reshape independently.
                        Text(L10n.string("otp_resend_countdown_format", secondsRemaining))
                            .font(.system(size: 13))
                            .foregroundStyle(OkaiwaColors.muted)
                    } else {
                        Button {
                            secondsRemaining = 60
                            startTimer()
                            onResend()
                        } label: {
                            Text(L10n.key("otp_resend_cta"))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(OkaiwaColors.lime)
                        }
                    }
                    Spacer()
                }

                if DevConfig.isDebug {
                    Spacer().frame(height: 16)
                    Text(L10n.key("otp_dev_hint"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(OkaiwaColors.lime)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 24)
                }

                Spacer()

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
                            Text(L10n.key("otp_submit_cta"))
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
            // Slight delay so the view is fully laid out before we request
            // focus, otherwise the keyboard sometimes refuses to show on
            // first appearance.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                otpFocused = true
            }
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
                let isCursor = index == otp.count && !hasError
                let borderColor: Color = {
                    if hasError { return OkaiwaColors.error }
                    if isCursor || isFilled { return OkaiwaColors.lime }
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
                // frame + aspectRatio gives every slot the same share of
                // the available width, mirroring Android's weight(1f).
                .frame(maxWidth: .infinity)
                .aspectRatio(48.0 / 56.0, contentMode: .fit)
            }
        }
        .frame(maxWidth: .infinity)
    }
}
