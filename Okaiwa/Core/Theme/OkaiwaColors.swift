import SwiftUI

/// Okaiwa brand palette — mirrors the Android `OkaiwaColors` object.
///
/// The visual identity is dark-first: a near-black background punctuated
/// by the lime yellow whale/wave mark (#E5F240). Keep this file in
/// lock-step with `okaiwa-android/app/src/main/kotlin/io/okaiwa/core/theme/OkaiwaTheme.kt`.
public enum OkaiwaColors {
    // Brand
    public static let lime = Color(red: 0xE5 / 255, green: 0xF2 / 255, blue: 0x40 / 255)
    public static let limePressed = Color(red: 0xC8 / 255, green: 0xD9 / 255, blue: 0x35 / 255)
    public static let limeDim = Color(red: 0x7A / 255, green: 0x82 / 255, blue: 0x21 / 255)

    // Dark canvas — `black` matches #242424 from the Figma logo kit
    // (the rectangle behind the whale). The rest of the scale steps up
    // to preserve the elevation hierarchy for inputs, cards, borders.
    public static let black = Color(red: 0x24 / 255, green: 0x24 / 255, blue: 0x24 / 255)
    public static let blackElevated = Color(red: 0x2D / 255, green: 0x2D / 255, blue: 0x2D / 255)
    public static let blackCard = Color(red: 0x36 / 255, green: 0x36 / 255, blue: 0x36 / 255)
    public static let blackBorder = Color(red: 0x40 / 255, green: 0x40 / 255, blue: 0x40 / 255)

    // Text
    public static let white = Color.white
    public static let whiteDim = Color(red: 0xCF / 255, green: 0xCF / 255, blue: 0xCF / 255)
    public static let muted = Color(red: 0x8A / 255, green: 0x8A / 255, blue: 0x8A / 255)
    public static let placeholder = Color(red: 0x5C / 255, green: 0x5C / 255, blue: 0x5C / 255)

    // Semantic
    public static let error = Color(red: 0xE5 / 255, green: 0x39 / 255, blue: 0x35 / 255)
    public static let success = Color(red: 0x4C / 255, green: 0xAF / 255, blue: 0x50 / 255)
    public static let warning = Color(red: 0xFF / 255, green: 0xB3 / 255, blue: 0x00 / 255)
}
