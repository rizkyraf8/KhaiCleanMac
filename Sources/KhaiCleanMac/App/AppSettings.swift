import AppKit
import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case indonesian = "id"
    case english = "en"

    var id: String { rawValue }

    /// Always shown in its own language so people can find theirs.
    var nativeName: String {
        switch self {
        case .indonesian: "Bahasa Indonesia"
        case .english: "English"
        }
    }

    var flag: String {
        switch self {
        case .indonesian: "🇮🇩"
        case .english: "🇬🇧"
        }
    }

    var locale: Locale {
        Locale(identifier: self == .indonesian ? "id_ID" : "en_US")
    }
}

enum AppAppearance: String, CaseIterable, Identifiable, Sendable {
    case system, light, dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: L("Ikuti Sistem", "Match System")
        case .light: L("Terang", "Light")
        case .dark: L("Gelap", "Dark")
        }
    }

    /// `nil` hands control back to the system setting.
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

/// User preferences, saved in UserDefaults. Views re-render automatically when they change.
@Observable
final class AppSettings: @unchecked Sendable {
    static let shared = AppSettings()

    private enum Keys {
        static let language = "language"
        static let appearance = "appearance"
    }

    var language: AppLanguage {
        didSet { save(language.rawValue, forKey: Keys.language) }
    }

    var appearance: AppAppearance {
        didSet { save(appearance.rawValue, forKey: Keys.appearance) }
    }

    /// Debug snapshots switch language without touching the user's saved choice.
    @ObservationIgnored var persists = true

    var locale: Locale { language.locale }

    private init() {
        let defaults = UserDefaults.standard
        language = defaults.string(forKey: Keys.language).flatMap(AppLanguage.init) ?? .indonesian
        appearance = defaults.string(forKey: Keys.appearance).flatMap(AppAppearance.init) ?? .system
    }

    private func save(_ value: String, forKey key: String) {
        guard persists else { return }
        UserDefaults.standard.set(value, forKey: key)
    }
}

/// Gives a window's content the locale of the chosen language (dates, numbers, sizes).
struct LocalizedRoot<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content.environment(\.locale, AppSettings.shared.locale)
    }
}

/// Picks the Indonesian or English text for the current language.
func L(_ indonesian: String, _ english: String) -> String {
    AppSettings.shared.language == .english ? english : indonesian
}
