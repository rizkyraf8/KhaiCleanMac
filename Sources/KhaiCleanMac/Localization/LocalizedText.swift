import Foundation

/// A text written at an `L(…)` call, kept as a key plus its values instead of one finished string.
///
/// `"Delete \(name)?"` becomes the key `"Delete %1$@?"` with `name` as its first value, so another
/// language can look the sentence up and put the values where its grammar needs them (`"%1$@を削除しますか?"`).
/// `scripts/l10n.py` builds the same keys from the source code to check that every text is translated.
struct LocalizedText: ExpressibleByStringInterpolation, Sendable {
    let key: String
    let values: [String]

    init(stringLiteral value: String) {
        key = value
        values = []
    }

    init(stringInterpolation: Interpolation) {
        key = stringInterpolation.key
        values = stringInterpolation.values
    }

    struct Interpolation: StringInterpolationProtocol {
        var key = ""
        var values: [String] = []

        init(literalCapacity: Int, interpolationCount: Int) {
            key.reserveCapacity(literalCapacity + interpolationCount * 4)
        }

        mutating func appendLiteral(_ literal: String) {
            key += literal
        }

        /// Renders the value exactly as plain string interpolation would.
        mutating func appendInterpolation<T>(_ value: T) {
            values.append(String(describing: value))
            key += "%\(values.count)$@"
        }
    }

    /// The text as written.
    var text: String { Self.fill(key, with: values) }

    /// Puts the values into a template's `%1$@`, `%2$@`… in one pass, so a value that happens to
    /// contain a placeholder is never filled in again. A template may leave values out.
    static func fill(_ template: String, with values: [String]) -> String {
        guard !values.isEmpty, template.contains("$@") else { return template }
        var result = ""
        var rest = template[...]
        while let percent = rest.firstIndex(of: "%") {
            result += rest[..<percent]
            let afterPercent = rest[rest.index(after: percent)...]
            let digits = afterPercent.prefix { $0.isASCII && $0.isNumber }
            if !digits.isEmpty, afterPercent.dropFirst(digits.count).hasPrefix("$@"),
               let number = Int(digits), (1...values.count).contains(number) {
                result += values[number - 1]
                rest = afterPercent.dropFirst(digits.count + 2)
            } else {
                result += "%"
                rest = afterPercent
            }
        }
        return result + rest
    }
}

/// Picks the text for the current language: Indonesian and English are written at the call site,
/// the others are looked up by the English text and fall back to English while a text is untranslated.
func L(_ indonesian: LocalizedText, _ english: LocalizedText) -> String {
    let language = AppSettings.shared.language
    switch language {
    case .indonesian: return indonesian.text
    case .english: return english.text
    default:
        guard let template = Translations.text(for: english.key, in: language) else { return english.text }
        return LocalizedText.fill(template, with: english.values)
    }
}
