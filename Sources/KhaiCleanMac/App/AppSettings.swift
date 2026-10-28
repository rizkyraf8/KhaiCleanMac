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
        static let keepInMenuBar = "keepInMenuBar"
        static let remindersEnabled = "remindersEnabled"
        static let reminderFrequency = "reminderFrequency"
        static let reminderThreshold = "reminderThreshold"
        static let lastReminderCheck = "lastReminderCheck"
        static let chromeCacheAge = "chromeCacheAge"
        static let deletesPermanently = "deletesPermanently"
        static let downloadsAge = "downloadsAge"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
        static let legacyMigrated = "legacyPreferencesMigrated"

        static let all = [language, appearance, keepInMenuBar, remindersEnabled,
                          reminderFrequency, reminderThreshold, lastReminderCheck, chromeCacheAge]
    }

    /// The bundle ID used before 0.3.0. Preferences saved under it are copied over once.
    private static let legacyBundleID = "com.khai.KhaiCleanMac"

    var language: AppLanguage {
        didSet { save(language.rawValue, forKey: Keys.language) }
    }

    var appearance: AppAppearance {
        didSet { save(appearance.rawValue, forKey: Keys.appearance) }
    }

    /// Closing the window leaves the app running in the menu bar instead of quitting.
    var keepInMenuBar: Bool {
        didSet { save(keepInMenuBar, forKey: Keys.keepInMenuBar) }
    }

    var remindersEnabled: Bool {
        didSet { save(remindersEnabled, forKey: Keys.remindersEnabled) }
    }

    var reminderFrequency: ReminderFrequency {
        didSet { save(reminderFrequency.rawValue, forKey: Keys.reminderFrequency) }
    }

    var reminderThreshold: ReminderThreshold {
        didSet { save(reminderThreshold.rawValue, forKey: Keys.reminderThreshold) }
    }

    var lastReminderCheck: Date? {
        didSet { save(lastReminderCheck, forKey: Keys.lastReminderCheck) }
    }

    /// How long Chrome's web cache may go unused before Smart Scan offers to remove it.
    var chromeCacheAge: ChromeCacheAge {
        didSet { save(chromeCacheAge.rawValue, forKey: Keys.chromeCacheAge) }
    }

    var hasCompletedOnboarding: Bool {
        didSet { save(hasCompletedOnboarding, forKey: Keys.hasCompletedOnboarding) }
    }

    /// How long a download may go unopened before Smart Scan lists it.
    var downloadsAge: DownloadsAge {
        didSet { save(downloadsAge.rawValue, forKey: Keys.downloadsAge) }
    }

    /// Off by default. When on, cleaning deletes files for good instead of using the Trash.
    /// Settings only turns it on after the user confirms.
    var deletesPermanently: Bool {
        didSet { save(deletesPermanently, forKey: Keys.deletesPermanently) }
    }

    /// Debug snapshots switch language without touching the user's saved choice.
    @ObservationIgnored var persists = true

    var locale: Locale { language.locale }

    private init() {
        let defaults = UserDefaults.standard
        Self.migrateLegacyPreferences(into: defaults)
        language = defaults.string(forKey: Keys.language).flatMap(AppLanguage.init) ?? .indonesian
        appearance = defaults.string(forKey: Keys.appearance).flatMap(AppAppearance.init) ?? .system
        keepInMenuBar = defaults.object(forKey: Keys.keepInMenuBar) as? Bool ?? true
        remindersEnabled = defaults.bool(forKey: Keys.remindersEnabled)
        reminderFrequency = defaults.string(forKey: Keys.reminderFrequency).flatMap(ReminderFrequency.init) ?? .weekly
        reminderThreshold = ReminderThreshold(rawValue: Int64(defaults.integer(forKey: Keys.reminderThreshold))) ?? .gb5
        lastReminderCheck = defaults.object(forKey: Keys.lastReminderCheck) as? Date
        chromeCacheAge = ChromeCacheAge(rawValue: defaults.integer(forKey: Keys.chromeCacheAge)) ?? .days30
        deletesPermanently = defaults.bool(forKey: Keys.deletesPermanently)
        downloadsAge = DownloadsAge(rawValue: defaults.integer(forKey: Keys.downloadsAge)) ?? .days90
        hasCompletedOnboarding = defaults.bool(forKey: Keys.hasCompletedOnboarding)
    }

    private static func migrateLegacyPreferences(into defaults: UserDefaults) {
        guard Bundle.main.bundleIdentifier != legacyBundleID,
              !defaults.bool(forKey: Keys.legacyMigrated) else { return }
        defaults.set(true, forKey: Keys.legacyMigrated)
        guard let legacy = defaults.persistentDomain(forName: legacyBundleID) else { return }
        for key in Keys.all where defaults.object(forKey: key) == nil {
            if let value = legacy[key] { defaults.set(value, forKey: key) }
        }
    }

    private func save(_ value: Any?, forKey key: String) {
        guard persists else { return }
        UserDefaults.standard.set(value, forKey: key)
    }
}

enum ReminderFrequency: String, CaseIterable, Identifiable, Sendable {
    case daily, weekly, monthly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .daily: L("Harian", "Daily")
        case .weekly: L("Mingguan", "Weekly")
        case .monthly: L("Bulanan", "Monthly")
        }
    }

    var interval: TimeInterval {
        switch self {
        case .daily: 24 * 60 * 60
        case .weekly: 7 * 24 * 60 * 60
        case .monthly: 30 * 24 * 60 * 60
        }
    }
}

enum ReminderThreshold: Int64, CaseIterable, Identifiable, Sendable {
    case gb1 = 1_000_000_000
    case gb5 = 5_000_000_000
    case gb10 = 10_000_000_000

    var id: Int64 { rawValue }
    var label: String { rawValue.formattedBytes }
}

enum ChromeCacheAge: Int, CaseIterable, Identifiable, Sendable {
    case days7 = 7
    case days30 = 30
    case days90 = 90

    var id: Int { rawValue }
    var title: String { L("\(rawValue) hari", "\(rawValue) days") }
}

enum DownloadsAge: Int, CaseIterable, Identifiable, Sendable {
    case days30 = 30
    case days90 = 90
    case days180 = 180

    var id: Int { rawValue }
    var title: String { L("\(rawValue) hari", "\(rawValue) days") }
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
