import Foundation
import Testing
@testable import KhaiCleanMac

@Suite struct LocalizationTests {
    @Test func interpolationsBecomeNumberedPlaceholders() {
        let name = "Docker"
        let size = "1.2 GB"
        let text: LocalizedText = "Move \(name) (\(size)) to the Trash?"
        #expect(text.key == "Move %1$@ (%2$@) to the Trash?")
        #expect(text.values == ["Docker", "1.2 GB"])
        #expect(text.text == "Move Docker (1.2 GB) to the Trash?")
    }

    @Test func valuesRenderLikePlainInterpolation() {
        let count = 3
        let optional: Int? = nil
        let text: LocalizedText = "\(count) items, \(optional as Any)"
        #expect(text.text == "\(count) items, \(optional as Any)")
    }

    @Test func plainTextIsItsOwnKey() {
        let text: LocalizedText = "Comparing file contents… 40%"
        #expect(text.key == "Comparing file contents… 40%")
        #expect(text.text == "Comparing file contents… 40%")
    }

    @Test func templatesCanReorderAndDropValues() {
        #expect(LocalizedText.fill("%2$@ 中 %1$@", with: ["3", "10"]) == "10 中 3")
        #expect(LocalizedText.fill("%1$@ 項目（%3$@）", with: ["3", "items", "1 GB"]) == "3 項目（1 GB）")
        // A value that looks like a placeholder is never filled in again.
        #expect(LocalizedText.fill("%1$@ and %2$@", with: ["%2$@", "x"]) == "%2$@ and x")
        // A lone percent sign or an unknown placeholder stays as written.
        #expect(LocalizedText.fill("%1$@ %", with: ["40"]) == "40 %")
        #expect(LocalizedText.fill("%3$@", with: ["a"]) == "%3$@")
    }

    @Test func translationsAreFoundByTheEnglishKey() {
        let subject = "Docker"
        let english: LocalizedText = "Move \(subject) to the Trash?"
        // The same key scripts/l10n.py extracts from Trasher's wording.
        #expect(english.key == "Move %1$@ to the Trash?")
        let japanese = Translations.text(for: english.key, in: .japanese)
        #expect(japanese.map { LocalizedText.fill($0, with: english.values) } == "Docker をゴミ箱に入れますか？")
        #expect(Translations.text(for: english.key, in: .spanish) == "¿Mover %1$@ a la Papelera?")
        #expect(Translations.text(for: english.key, in: .english) == nil, "English and Indonesian come from the call site")
        #expect(Translations.text(for: "Not a real text", in: .chinese) == nil)
    }

    @Test func everyLanguageHasTheSameTexts() {
        #expect(Translations.languages == [.japanese, .chinese, .spanish, .german, .portuguese, .french, .korean])
        let count = Translations.count(in: .japanese)
        #expect(count > 500)
        for language in Translations.languages {
            #expect(Translations.count(in: language) == count, "\(language) is missing texts")
            #expect(Translations.text(for: "Settings", in: language)?.isEmpty == false)
        }
    }

    @Test func picksTheMacsLanguage() {
        #expect(AppLanguage.preferred(from: ["ja-JP", "en-US"]) == .japanese)
        #expect(AppLanguage.preferred(from: ["zh-Hans-CN"]) == .chinese)
        #expect(AppLanguage.preferred(from: ["zh-Hant-TW", "en-US"]) == .english, "Traditional Chinese isn't offered")
        #expect(AppLanguage.preferred(from: ["es-MX"]) == .spanish)
        #expect(AppLanguage.preferred(from: ["id-ID"]) == .indonesian)
        #expect(AppLanguage.preferred(from: ["it-IT", "es-ES"]) == .spanish, "The first language the app speaks wins")
        #expect(AppLanguage.preferred(from: ["fr-CA"]) == .french)
        #expect(AppLanguage.preferred(from: ["pt-PT"]) == .portuguese)
        #expect(AppLanguage.preferred(from: ["ko-KR"]) == .korean)
        #expect(AppLanguage.preferred(from: ["de-AT"]) == .german)
        #expect(AppLanguage.preferred(from: ["it-IT"]) == .english)
    }
}
