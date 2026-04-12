import Foundation

/// Development-only conveniences. Mirrors `DevConfig.kt` on Android.
///
/// Every flag here is gated on `DEBUG` so it is never compiled into a
/// release build. Release builds strip these checks at compile time.
///
/// Add a flag here only if it meaningfully accelerates tester iteration
/// AND it cannot cause harm if accidentally exposed. The magic OTP below
/// only short-circuits the SMS round-trip — in production the server
/// rejects any OTP that doesn't match a real SMS challenge, regardless
/// of what the client sends.
public enum DevConfig {

    /// Magic OTP code that auto-passes the verification screen during
    /// development, so testers don't have to wait for (or pay for) a
    /// real SMS while iterating on the onboarding UX.
    private static let devMagicOtp = "000000"

    /// Returns `true` if the given OTP should be accepted locally without
    /// a server round-trip. Only ever `true` in debug builds.
    public static func isDevOtpAccepted(_ otp: String) -> Bool {
        #if DEBUG
        return otp == devMagicOtp
        #else
        return false
        #endif
    }

    public static var isDebug: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }
}
