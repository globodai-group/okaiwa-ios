import SwiftUI

/// Country picker — mirrors `CountryPickerScreen.kt` on Android.
///
/// Search matches country name, dial code, or ISO. Selection dismisses
/// the view via `onSelect`.
public struct CountryPickerView: View {
    let onBack: () -> Void
    let onSelect: (Country) -> Void

    @State private var query: String = ""

    public init(onBack: @escaping () -> Void, onSelect: @escaping (Country) -> Void) {
        self.onBack = onBack
        self.onSelect = onSelect
    }

    private var filtered: [Country] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return Countries.all }
        return Countries.all.filter { country in
            country.name.lowercased().contains(trimmed) ||
                country.dialCode.contains(trimmed) ||
                country.isoCode.lowercased().contains(trimmed)
        }
    }

    public var body: some View {
        ZStack {
            OkaiwaColors.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // Top bar
                HStack(spacing: 8) {
                    Button(action: onBack) {
                        Image(systemName: "arrow.backward")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(OkaiwaColors.white)
                            .padding(12)
                    }
                    Text("Choisir un pays")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(OkaiwaColors.white)
                    Spacer()
                }

                // Search bar
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(OkaiwaColors.muted)
                    TextField("", text: $query, prompt: Text("Rechercher un pays").foregroundStyle(OkaiwaColors.placeholder))
                        .foregroundStyle(OkaiwaColors.white)
                        .tint(OkaiwaColors.lime)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    if !query.isEmpty {
                        Button {
                            query = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(OkaiwaColors.muted)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .frame(height: 44)
                .background(OkaiwaColors.blackElevated)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 16)

                // Country list
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filtered) { country in
                            Button {
                                onSelect(country)
                            } label: {
                                HStack(spacing: 16) {
                                    Text(country.flagEmoji)
                                        .font(.system(size: 24))
                                    Text(country.name)
                                        .font(.system(size: 16))
                                        .foregroundStyle(OkaiwaColors.white)
                                    Spacer()
                                    Text(country.dialCode)
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundStyle(OkaiwaColors.muted)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                            }
                            .buttonStyle(.plain)
                            Divider()
                                .background(OkaiwaColors.blackBorder)
                        }
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 16)
                }
            }
        }
    }
}
