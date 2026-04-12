import SwiftUI
import UIKit

/// Screen security — opt-in FLAG_SECURE-equivalent for iOS.
///
/// The iOS equivalent of Android's FLAG_SECURE is to route UI through
/// a hidden `UITextField` whose `.isSecureTextEntry = true` — the system
/// then suppresses screenshots and screen recording of the containing
/// view hierarchy.
///
/// Like on Android, this is NOT applied globally. Use the `SecureScreen`
/// view modifier only on screens that display sensitive material:
///   - Secret conversations with screenshot protection enabled
///   - Seed phrase reveal
///   - Private key / mnemonic export
///   - Safety number / QR verification screen
///
/// Usage:
///
///     SeedPhraseView()
///         .secureScreen()
///
public extension View {
    func secureScreen(_ enabled: Bool = true) -> some View {
        modifier(SecureScreenModifier(enabled: enabled))
    }
}

private struct SecureScreenModifier: ViewModifier {
    let enabled: Bool

    func body(content: Content) -> some View {
        content
            .background(SecureFieldOverlay(enabled: enabled))
    }
}

/// Hidden UITextField whose secure-entry state covers the host view and
/// suppresses system screenshot/recording while `enabled` is true.
private struct SecureFieldOverlay: UIViewRepresentable {
    let enabled: Bool

    func makeUIView(context: Context) -> UIView {
        UIView()
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        guard let parent = uiView.superview else { return }
        // Find or install the UITextField on the parent.
        let field: UITextField
        if let existing = parent.subviews.compactMap({ $0 as? SecureShadowField }).first {
            field = existing
        } else {
            let newField = SecureShadowField()
            newField.translatesAutoresizingMaskIntoConstraints = false
            newField.isUserInteractionEnabled = false
            parent.addSubview(newField)
            parent.sendSubviewToBack(newField)
            NSLayoutConstraint.activate([
                newField.leadingAnchor.constraint(equalTo: parent.leadingAnchor),
                newField.trailingAnchor.constraint(equalTo: parent.trailingAnchor),
                newField.topAnchor.constraint(equalTo: parent.topAnchor),
                newField.bottomAnchor.constraint(equalTo: parent.bottomAnchor),
            ])
            field = newField
        }
        field.isSecureTextEntry = enabled
    }
}

/// Marker class so we can find our own injected field without mistaking
/// it for a legitimate text field in the host view hierarchy.
private final class SecureShadowField: UITextField {}
