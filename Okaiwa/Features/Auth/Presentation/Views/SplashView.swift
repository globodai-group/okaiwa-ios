import SwiftUI

/// Splash screen — mirrors `SplashScreen.kt` on Android.
///
/// Fade + scale reveal of the Okaiwa mark, followed by the wordmark,
/// then hands off to `onFinished` after ~1.2s total.
public struct SplashView: View {
    let onFinished: () -> Void

    @State private var logoScale: CGFloat = 0.85
    @State private var logoOpacity: Double = 0
    @State private var wordmarkOpacity: Double = 0

    public init(onFinished: @escaping () -> Void) {
        self.onFinished = onFinished
    }

    public var body: some View {
        ZStack {
            OkaiwaColors.black.ignoresSafeArea()

            VStack(spacing: 12) {
                Image("OkaiwaLogoForeground")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 160, height: 160)
                    .scaleEffect(logoScale)
                    .opacity(logoOpacity)

                Text(L10n.key("app_wordmark"))
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(OkaiwaColors.white)
                    .tracking(4)
                    .opacity(wordmarkOpacity)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.4)) {
                logoOpacity = 1
            }
            withAnimation(.easeInOut(duration: 0.5)) {
                logoScale = 1
            }
            withAnimation(.easeInOut(duration: 0.4).delay(0.3)) {
                wordmarkOpacity = 1
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                onFinished()
            }
        }
    }
}
