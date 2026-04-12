import Foundation

/// Phone country metadata — ISO code, display name, dial code, flag emoji.
///
/// Mirrors the Android `Country` domain entity so the authentication flow
/// behaves identically on both platforms. The flag emoji is derived from
/// the ISO-3166-1 alpha-2 code via regional indicator symbols.
public struct Country: Identifiable, Hashable, Equatable {
    public let isoCode: String
    public let name: String
    public let dialCode: String

    public var id: String { isoCode }

    public var flagEmoji: String {
        // Regional Indicator Symbols live at U+1F1E6..U+1F1FF, offset
        // from the latin uppercase 'A' by 0x1F1A5.
        isoCode.uppercased().unicodeScalars
            .compactMap { UnicodeScalar(0x1F1A5 + $0.value) }
            .map(String.init)
            .joined()
    }

    public init(isoCode: String, name: String, dialCode: String) {
        self.isoCode = isoCode
        self.name = name
        self.dialCode = dialCode
    }
}

/// Static catalog of countries for the phone number picker.
/// Ordered alphabetically by display name. The picker UI lets the
/// user search by name, dial code, or ISO.
public enum Countries {
    public static let all: [Country] = [
        Country(isoCode: "AF", name: "Afghanistan", dialCode: "+93"),
        Country(isoCode: "AL", name: "Albanie", dialCode: "+355"),
        Country(isoCode: "DZ", name: "Algérie", dialCode: "+213"),
        Country(isoCode: "DE", name: "Allemagne", dialCode: "+49"),
        Country(isoCode: "AD", name: "Andorre", dialCode: "+376"),
        Country(isoCode: "AO", name: "Angola", dialCode: "+244"),
        Country(isoCode: "AR", name: "Argentine", dialCode: "+54"),
        Country(isoCode: "AM", name: "Arménie", dialCode: "+374"),
        Country(isoCode: "AU", name: "Australie", dialCode: "+61"),
        Country(isoCode: "AT", name: "Autriche", dialCode: "+43"),
        Country(isoCode: "AZ", name: "Azerbaïdjan", dialCode: "+994"),
        Country(isoCode: "BH", name: "Bahreïn", dialCode: "+973"),
        Country(isoCode: "BD", name: "Bangladesh", dialCode: "+880"),
        Country(isoCode: "BE", name: "Belgique", dialCode: "+32"),
        Country(isoCode: "BJ", name: "Bénin", dialCode: "+229"),
        Country(isoCode: "BY", name: "Biélorussie", dialCode: "+375"),
        Country(isoCode: "BO", name: "Bolivie", dialCode: "+591"),
        Country(isoCode: "BA", name: "Bosnie-Herzégovine", dialCode: "+387"),
        Country(isoCode: "BR", name: "Brésil", dialCode: "+55"),
        Country(isoCode: "BG", name: "Bulgarie", dialCode: "+359"),
        Country(isoCode: "BF", name: "Burkina Faso", dialCode: "+226"),
        Country(isoCode: "KH", name: "Cambodge", dialCode: "+855"),
        Country(isoCode: "CM", name: "Cameroun", dialCode: "+237"),
        Country(isoCode: "CA", name: "Canada", dialCode: "+1"),
        Country(isoCode: "CL", name: "Chili", dialCode: "+56"),
        Country(isoCode: "CN", name: "Chine", dialCode: "+86"),
        Country(isoCode: "CY", name: "Chypre", dialCode: "+357"),
        Country(isoCode: "CO", name: "Colombie", dialCode: "+57"),
        Country(isoCode: "CG", name: "Congo", dialCode: "+242"),
        Country(isoCode: "CD", name: "Congo (RDC)", dialCode: "+243"),
        Country(isoCode: "KR", name: "Corée du Sud", dialCode: "+82"),
        Country(isoCode: "CI", name: "Côte d'Ivoire", dialCode: "+225"),
        Country(isoCode: "HR", name: "Croatie", dialCode: "+385"),
        Country(isoCode: "CU", name: "Cuba", dialCode: "+53"),
        Country(isoCode: "DK", name: "Danemark", dialCode: "+45"),
        Country(isoCode: "EG", name: "Égypte", dialCode: "+20"),
        Country(isoCode: "AE", name: "Émirats arabes unis", dialCode: "+971"),
        Country(isoCode: "EC", name: "Équateur", dialCode: "+593"),
        Country(isoCode: "ES", name: "Espagne", dialCode: "+34"),
        Country(isoCode: "EE", name: "Estonie", dialCode: "+372"),
        Country(isoCode: "US", name: "États-Unis", dialCode: "+1"),
        Country(isoCode: "ET", name: "Éthiopie", dialCode: "+251"),
        Country(isoCode: "FI", name: "Finlande", dialCode: "+358"),
        Country(isoCode: "FR", name: "France", dialCode: "+33"),
        Country(isoCode: "GA", name: "Gabon", dialCode: "+241"),
        Country(isoCode: "GE", name: "Géorgie", dialCode: "+995"),
        Country(isoCode: "GH", name: "Ghana", dialCode: "+233"),
        Country(isoCode: "GR", name: "Grèce", dialCode: "+30"),
        Country(isoCode: "GT", name: "Guatemala", dialCode: "+502"),
        Country(isoCode: "GN", name: "Guinée", dialCode: "+224"),
        Country(isoCode: "HT", name: "Haïti", dialCode: "+509"),
        Country(isoCode: "HN", name: "Honduras", dialCode: "+504"),
        Country(isoCode: "HK", name: "Hong Kong", dialCode: "+852"),
        Country(isoCode: "HU", name: "Hongrie", dialCode: "+36"),
        Country(isoCode: "IN", name: "Inde", dialCode: "+91"),
        Country(isoCode: "ID", name: "Indonésie", dialCode: "+62"),
        Country(isoCode: "IQ", name: "Iraq", dialCode: "+964"),
        Country(isoCode: "IR", name: "Iran", dialCode: "+98"),
        Country(isoCode: "IE", name: "Irlande", dialCode: "+353"),
        Country(isoCode: "IS", name: "Islande", dialCode: "+354"),
        Country(isoCode: "IL", name: "Israël", dialCode: "+972"),
        Country(isoCode: "IT", name: "Italie", dialCode: "+39"),
        Country(isoCode: "JM", name: "Jamaïque", dialCode: "+1"),
        Country(isoCode: "JP", name: "Japon", dialCode: "+81"),
        Country(isoCode: "JO", name: "Jordanie", dialCode: "+962"),
        Country(isoCode: "KZ", name: "Kazakhstan", dialCode: "+7"),
        Country(isoCode: "KE", name: "Kenya", dialCode: "+254"),
        Country(isoCode: "KW", name: "Koweït", dialCode: "+965"),
        Country(isoCode: "LA", name: "Laos", dialCode: "+856"),
        Country(isoCode: "LV", name: "Lettonie", dialCode: "+371"),
        Country(isoCode: "LB", name: "Liban", dialCode: "+961"),
        Country(isoCode: "LY", name: "Libye", dialCode: "+218"),
        Country(isoCode: "LT", name: "Lituanie", dialCode: "+370"),
        Country(isoCode: "LU", name: "Luxembourg", dialCode: "+352"),
        Country(isoCode: "MK", name: "Macédoine du Nord", dialCode: "+389"),
        Country(isoCode: "MG", name: "Madagascar", dialCode: "+261"),
        Country(isoCode: "MY", name: "Malaisie", dialCode: "+60"),
        Country(isoCode: "ML", name: "Mali", dialCode: "+223"),
        Country(isoCode: "MT", name: "Malte", dialCode: "+356"),
        Country(isoCode: "MA", name: "Maroc", dialCode: "+212"),
        Country(isoCode: "MU", name: "Maurice", dialCode: "+230"),
        Country(isoCode: "MR", name: "Mauritanie", dialCode: "+222"),
        Country(isoCode: "MX", name: "Mexique", dialCode: "+52"),
        Country(isoCode: "MD", name: "Moldavie", dialCode: "+373"),
        Country(isoCode: "MC", name: "Monaco", dialCode: "+377"),
        Country(isoCode: "MN", name: "Mongolie", dialCode: "+976"),
        Country(isoCode: "ME", name: "Monténégro", dialCode: "+382"),
        Country(isoCode: "MZ", name: "Mozambique", dialCode: "+258"),
        Country(isoCode: "NA", name: "Namibie", dialCode: "+264"),
        Country(isoCode: "NP", name: "Népal", dialCode: "+977"),
        Country(isoCode: "NI", name: "Nicaragua", dialCode: "+505"),
        Country(isoCode: "NE", name: "Niger", dialCode: "+227"),
        Country(isoCode: "NG", name: "Nigeria", dialCode: "+234"),
        Country(isoCode: "NO", name: "Norvège", dialCode: "+47"),
        Country(isoCode: "NZ", name: "Nouvelle-Zélande", dialCode: "+64"),
        Country(isoCode: "OM", name: "Oman", dialCode: "+968"),
        Country(isoCode: "UG", name: "Ouganda", dialCode: "+256"),
        Country(isoCode: "UZ", name: "Ouzbékistan", dialCode: "+998"),
        Country(isoCode: "PK", name: "Pakistan", dialCode: "+92"),
        Country(isoCode: "PA", name: "Panama", dialCode: "+507"),
        Country(isoCode: "PY", name: "Paraguay", dialCode: "+595"),
        Country(isoCode: "NL", name: "Pays-Bas", dialCode: "+31"),
        Country(isoCode: "PE", name: "Pérou", dialCode: "+51"),
        Country(isoCode: "PH", name: "Philippines", dialCode: "+63"),
        Country(isoCode: "PL", name: "Pologne", dialCode: "+48"),
        Country(isoCode: "PT", name: "Portugal", dialCode: "+351"),
        Country(isoCode: "QA", name: "Qatar", dialCode: "+974"),
        Country(isoCode: "RO", name: "Roumanie", dialCode: "+40"),
        Country(isoCode: "GB", name: "Royaume-Uni", dialCode: "+44"),
        Country(isoCode: "RU", name: "Russie", dialCode: "+7"),
        Country(isoCode: "RW", name: "Rwanda", dialCode: "+250"),
        Country(isoCode: "SV", name: "Salvador", dialCode: "+503"),
        Country(isoCode: "SA", name: "Arabie saoudite", dialCode: "+966"),
        Country(isoCode: "SN", name: "Sénégal", dialCode: "+221"),
        Country(isoCode: "RS", name: "Serbie", dialCode: "+381"),
        Country(isoCode: "SG", name: "Singapour", dialCode: "+65"),
        Country(isoCode: "SK", name: "Slovaquie", dialCode: "+421"),
        Country(isoCode: "SI", name: "Slovénie", dialCode: "+386"),
        Country(isoCode: "SO", name: "Somalie", dialCode: "+252"),
        Country(isoCode: "SD", name: "Soudan", dialCode: "+249"),
        Country(isoCode: "LK", name: "Sri Lanka", dialCode: "+94"),
        Country(isoCode: "SE", name: "Suède", dialCode: "+46"),
        Country(isoCode: "CH", name: "Suisse", dialCode: "+41"),
        Country(isoCode: "SR", name: "Suriname", dialCode: "+597"),
        Country(isoCode: "SY", name: "Syrie", dialCode: "+963"),
        Country(isoCode: "TJ", name: "Tadjikistan", dialCode: "+992"),
        Country(isoCode: "TW", name: "Taïwan", dialCode: "+886"),
        Country(isoCode: "TZ", name: "Tanzanie", dialCode: "+255"),
        Country(isoCode: "TD", name: "Tchad", dialCode: "+235"),
        Country(isoCode: "CZ", name: "Tchéquie", dialCode: "+420"),
        Country(isoCode: "TH", name: "Thaïlande", dialCode: "+66"),
        Country(isoCode: "TG", name: "Togo", dialCode: "+228"),
        Country(isoCode: "TN", name: "Tunisie", dialCode: "+216"),
        Country(isoCode: "TM", name: "Turkménistan", dialCode: "+993"),
        Country(isoCode: "TR", name: "Turquie", dialCode: "+90"),
        Country(isoCode: "UA", name: "Ukraine", dialCode: "+380"),
        Country(isoCode: "UY", name: "Uruguay", dialCode: "+598"),
        Country(isoCode: "VE", name: "Venezuela", dialCode: "+58"),
        Country(isoCode: "VN", name: "Viêt Nam", dialCode: "+84"),
        Country(isoCode: "YE", name: "Yémen", dialCode: "+967"),
        Country(isoCode: "ZM", name: "Zambie", dialCode: "+260"),
        Country(isoCode: "ZW", name: "Zimbabwe", dialCode: "+263"),
    ].sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

    public static func findByIso(_ iso: String) -> Country? {
        all.first { $0.isoCode.caseInsensitiveCompare(iso) == .orderedSame }
    }

    public static let `default`: Country = findByIso("FR") ?? all[0]
}
