import Foundation

// MARK: - AppLanguage (LAR-35)
// The 8 supported in-app languages. The rawValue is the BCP 47 locale code,
// which doubles as the Wikipedia subdomain (e.g. ja.wikipedia.org).

enum AppLanguage: String, CaseIterable, Identifiable {
    case english    = "en"
    case japanese   = "ja"
    case german     = "de"
    case french     = "fr"
    case spanish    = "es"
    case portuguese = "pt"
    case korean     = "ko"
    case italian    = "it"

    var id: String { rawValue }

    /// The language name as it appears in its own language.
    var nativeName: String {
        switch self {
        case .english:    return "English"
        case .japanese:   return "日本語"
        case .german:     return "Deutsch"
        case .french:     return "Français"
        case .spanish:    return "Español"
        case .portuguese: return "Português"
        case .korean:     return "한국어"
        case .italian:    return "Italiano"
        }
    }

    /// Returns the language matching the device's system locale, or .english if not supported.
    static func systemDefault() -> AppLanguage {
        let tag = Locale.preferredLanguages.first ?? "en"
        let code = String(tag.prefix(2))
        return AppLanguage(rawValue: code) ?? .english
    }
}
