import Foundation

/// Every language besides Indonesian and English, keyed by the English text of each `L(…)` call.
///
/// One file per language, `Translations+<code>.swift`, one entry per line as `"English key": "text",`
/// so that `scripts/l10n.py check` can read them. Placeholders like `%1$@` may move or be left out
/// (Japanese, Chinese and Korean have no plural "s"), but never added.
enum Translations {
    private static let tables: [AppLanguage: [String: String]] = [
        .japanese: japanese,
        .chinese: chinese,
        .spanish: spanish,
        .german: german,
        .portuguese: portuguese,
        .french: french,
        .korean: korean,
    ]

    /// The languages looked up here, in the order the picker shows them.
    static var languages: [AppLanguage] { AppLanguage.allCases.filter { tables[$0] != nil } }

    static func text(for englishKey: String, in language: AppLanguage) -> String? {
        tables[language]?[englishKey]
    }

    #if DEBUG
    static func count(in language: AppLanguage) -> Int { tables[language]?.count ?? 0 }
    #endif
}
