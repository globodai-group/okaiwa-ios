import SwiftUI

/// Contact picker — mirrors `ContactPickerScreen.kt`.
///
/// Asks the user for Contacts authorization on first entry. On denial
/// we show a dedicated empty state with a second-chance CTA. On grant
/// we read the address book via `CNContactStore` and split the list
/// into "Sur Okaiwa" (ready to message) and "Inviter" sections, the
/// latter opening the system share sheet with an install link.
public struct ContactPickerView: View {
    let onBack: () -> Void
    let onStartConversation: (DeviceContact) -> Void

    @State private var viewModel = ContactsViewModel()
    @State private var inviteTarget: DeviceContact?

    public init(
        onBack: @escaping () -> Void,
        onStartConversation: @escaping (DeviceContact) -> Void
    ) {
        self.onBack = onBack
        self.onStartConversation = onStartConversation
    }

    public var body: some View {
        VStack(spacing: 0) {
            topBar

            switch viewModel.permissionState {
            case .denied:
                permissionDeniedState
            case .unknown:
                Color.clear
            case .granted:
                searchField
                if viewModel.isLoading {
                    Spacer()
                    ProgressView().tint(OkaiwaColors.lime)
                    Spacer()
                } else {
                    contactList
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(OkaiwaColors.black)
        .onAppear { viewModel.requestAccess() }
        .sheet(item: $inviteTarget) { contact in
            ShareSheet(
                text: "Rejoins-moi sur Okaiwa — messagerie chiffrée + wallet crypto. https://okaiwa.io/install",
                subject: "Inviter \(contact.displayName)"
            )
        }
    }

    private var topBar: some View {
        HStack(spacing: 0) {
            Button(action: onBack) {
                Image(systemName: "arrow.backward")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(OkaiwaColors.white)
                    .padding(12)
            }
            Text("Nouvelle conversation")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(OkaiwaColors.white)
            Spacer()
        }
        .padding(.vertical, 8)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(OkaiwaColors.muted)
            TextField("", text: $viewModel.query, prompt: Text("Rechercher un contact").foregroundStyle(OkaiwaColors.placeholder))
                .foregroundStyle(OkaiwaColors.white)
                .tint(OkaiwaColors.lime)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(OkaiwaColors.blackElevated)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(OkaiwaColors.blackBorder, lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var contactList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if !viewModel.okaiwaContacts.isEmpty {
                    sectionHeader("Sur Okaiwa", count: viewModel.okaiwaContacts.count)
                    ForEach(viewModel.okaiwaContacts) { contact in
                        okaiwaRow(contact)
                    }
                }
                if !viewModel.inviteContacts.isEmpty {
                    sectionHeader("Inviter", count: viewModel.inviteContacts.count)
                    ForEach(viewModel.inviteContacts) { contact in
                        inviteRow(contact)
                    }
                }
            }
        }
    }

    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack(spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(OkaiwaColors.muted)
            Text("· \(count)")
                .font(.system(size: 11))
                .foregroundStyle(OkaiwaColors.muted)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private func okaiwaRow(_ contact: DeviceContact) -> some View {
        Button {
            onStartConversation(contact)
        } label: {
            HStack(spacing: 12) {
                avatar(contact.initial, muted: false)
                VStack(alignment: .leading, spacing: 2) {
                    Text(contact.displayName)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(OkaiwaColors.white)
                    Text(contact.okaiwaUsername ?? contact.phoneNumberE164)
                        .font(.system(size: 12))
                        .foregroundStyle(OkaiwaColors.muted)
                }
                Spacer()
                Text("Message")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(OkaiwaColors.lime)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
    }

    private func inviteRow(_ contact: DeviceContact) -> some View {
        Button {
            inviteTarget = contact
        } label: {
            HStack(spacing: 12) {
                avatar(contact.initial, muted: true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(contact.displayName)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(OkaiwaColors.white)
                    Text(contact.phoneNumberE164)
                        .font(.system(size: 12))
                        .foregroundStyle(OkaiwaColors.muted)
                }
                Spacer()
                Text("Inviter")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(OkaiwaColors.lime)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(OkaiwaColors.lime, lineWidth: 1)
                    )
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
    }

    private func avatar(_ initial: String, muted: Bool) -> some View {
        Circle()
            .fill(muted ? OkaiwaColors.blackElevated : OkaiwaColors.lime.opacity(0.15))
            .frame(width: 44, height: 44)
            .overlay(
                Text(initial)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(muted ? OkaiwaColors.muted : OkaiwaColors.lime)
            )
    }

    private var permissionDeniedState: some View {
        VStack(spacing: 16) {
            Spacer()
            Circle()
                .fill(OkaiwaColors.lime.opacity(0.15))
                .frame(width: 72, height: 72)
                .overlay(
                    Image(systemName: "person.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(OkaiwaColors.lime)
                )
            Text("Accès aux contacts refusé")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(OkaiwaColors.white)
            Text("Okaiwa a besoin de lire vos contacts pour trouver qui est déjà sur la plateforme. Nous hashons les numéros localement — ils ne sont jamais envoyés en clair.")
                .font(.system(size: 13))
                .foregroundStyle(OkaiwaColors.whiteDim)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .lineSpacing(3)

            Button {
                // iOS only allows re-prompting via Settings once denied
                // — bounce the user into the system app.
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Text("Autoriser l'accès aux contacts")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(OkaiwaColors.black)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(OkaiwaColors.lime)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .padding(.horizontal, 32)
    }
}

/// UIActivityViewController bridge so we can present the system share
/// sheet (SMS, WhatsApp, Mail…) from SwiftUI without pulling in a full
/// `ShareLink` redesign.
private struct ShareSheet: UIViewControllerRepresentable {
    let text: String
    let subject: String

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        controller.setValue(subject, forKey: "subject")
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
