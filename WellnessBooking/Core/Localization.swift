import SwiftUI

/// Lingua dell'app (come aMule Remote): "Sistema" oppure forzata. La scelta è applicata subito ai testi SwiftUI
/// tramite l'environment `locale` e, al riavvio, a tutto il bundle tramite `AppleLanguages`.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system, it, en, es, fr, de
    static let storageKey = "appLanguage"
    static let supported = ["it", "en", "es", "fr", "de"]
    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return String(localized: "Sistema")
        case .it: return "Italiano"
        case .en: return "English"
        case .es: return "Español"
        case .fr: return "Français"
        case .de: return "Deutsch"
        }
    }

    static var current: AppLanguage {
        AppLanguage(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .system
    }

    /// Locale da usare per date e testi.
    var locale: Locale {
        switch self {
        case .system:
            let code = Bundle.main.preferredLocalizations.first ?? Locale.current.identifier
            return Locale(identifier: code)
        default: return Locale(identifier: rawValue)
        }
    }

    func apply() {
        if self == .system {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.set([rawValue], forKey: "AppleLanguages")
        }
    }
}

/// Applica la lingua scelta all'albero SwiftUI (Text, Picker, DatePicker…).
struct AppLocaleModifier: ViewModifier {
    @AppStorage(AppLanguage.storageKey) private var appLanguage = AppLanguage.system.rawValue
    func body(content: Content) -> some View {
        let lang = AppLanguage(rawValue: appLanguage) ?? .system
        if lang == .system { content } else { content.environment(\.locale, lang.locale) }
    }
}
