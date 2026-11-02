import Foundation
import Testing
@testable import KhaiCleanMac

@Suite struct OrphanLeftoverTests {
    @Test func findsQuietEntriesOfAppsThatAreGone() throws {
        let temp = try TempFolder()
        try temp.file("Library/Caches/com.gone.Editor/cache.db", size: 4096, daysOld: 60)
        try temp.file("Library/Preferences/com.gone.Editor.plist", daysOld: 60)
        try temp.file("Library/Saved Application State/com.gone.Editor.savedState/data", daysOld: 60)
        try temp.file("Library/Group Containers/ABCDE12345.com.gone.Editor/shared.db", daysOld: 60)
        // Installed, a helper of an installed app, recently used, Apple's, a tool, and a plain name.
        try temp.file("Library/Caches/com.here.App/cache.db", daysOld: 60)
        try temp.file("Library/Caches/com.here.App.helper/cache.db", daysOld: 60)
        try temp.file("Library/Caches/com.busy.Tool/cache.db", daysOld: 1)
        try temp.file("Library/Caches/com.apple.Safari/cache.db", daysOld: 60)
        try temp.file("Library/Caches/org.swift.swiftpm/cache.db", daysOld: 60)
        try temp.file("Library/Application Support/Slack/data", daysOld: 60)

        for path in ["Library/Caches/com.gone.Editor", "Library/Saved Application State/com.gone.Editor.savedState",
                     "Library/Group Containers/ABCDE12345.com.gone.Editor", "Library/Caches/com.here.App",
                     "Library/Caches/com.here.App.helper", "Library/Caches/com.apple.Safari", "Library/Caches/org.swift.swiftpm"] {
            try temp.age(temp.url.appending(path: path), days: 60)
        }

        // Apple's own containers that don't start with com.apple, and a group an installed app declares.
        try temp.file("Library/Group Containers/group.is.workflow.shortcuts/Shortcuts.sqlite", daysOld: 60)
        try temp.file("Library/Group Containers/243LU875E5.groups.com.apple.podcasts/data", daysOld: 60)
        try temp.file("Library/Group Containers/ABCDE12345.com.shared.Suite/data", daysOld: 60)
        try temp.file("Library/Preferences/org.cups.PrintingPrefs.plist", daysOld: 60)
        for path in ["Library/Group Containers/group.is.workflow.shortcuts", "Library/Group Containers/243LU875E5.groups.com.apple.podcasts",
                     "Library/Group Containers/ABCDE12345.com.shared.Suite"] {
            try temp.age(temp.url.appending(path: path), days: 60)
        }

        let found = OrphanScanner(home: temp.url).scan(known: { $0 == "com.here.app" }, declaredGroups: ["ABCDE12345.com.shared.Suite"])
        #expect(Set(found.map(\.bundleID)) == ["com.gone.Editor"])
        #expect(Set(found.map(\.location)) == ["Caches", "Preferences", "Saved Application State", "Group Containers"])
        #expect(found.allSatisfy { $0.item.isGuess })
    }

    @Test func groupContainerNamesGiveTheAppID() {
        #expect(OrphanScanner.groupOwner("ABCDE12345.com.vendor.app") == "com.vendor.app")
        #expect(OrphanScanner.groupOwner("group.com.vendor.app") == "com.vendor.app")
        #expect(OrphanScanner.groupOwner("ABCDE12345.group.com.vendor.app") == "com.vendor.app")
        #expect(OrphanScanner.groupOwner("Office") == "Office")
    }

    @Test func onlyAppLikeIDsCount() {
        #expect(OrphanScanner.looksLikeAppID("com.vendor.App"))
        #expect(!OrphanScanner.looksLikeAppID("vendor.App"))
        #expect(!OrphanScanner.looksLikeAppID("com.apple.mail"))
        #expect(!OrphanScanner.looksLikeAppID("Com.Apple.mail"))
        #expect(!OrphanScanner.looksLikeAppID("../../Documents"))
        #expect(!OrphanScanner.looksLikeAppID(AppInfo.bundleID))
        #expect(!OrphanScanner.looksLikeAppID(AppInfo.productionBundleID + ".dev"))
        #expect(!OrphanScanner.looksLikeAppID("groups.com.apple.podcasts"))
        #expect(!OrphanScanner.looksLikeAppID("is.workflow.shortcuts"))
    }
}

@Suite struct LanguageReportTests {
    @Test func languageCodesFromFolderNames() {
        #expect(LanguageReport.language("pt-BR.lproj") == "pt")
        #expect(LanguageReport.language("zh_Hans.lproj") == "zh")
        #expect(LanguageReport.language("Japanese.lproj") == "ja")
        #expect(LanguageReport.usedLanguages(preferred: ["id-ID", "ja-JP"]) == ["id", "ja", "en"])
    }

    @Test func reportsOnlyUnusedLanguages() throws {
        let temp = try TempFolder()
        for language in ["Base", "en", "id", "de", "fr", "ja"] {
            try temp.file("Editor.app/Contents/Resources/\(language).lproj/Localizable.strings", size: 2048)
        }
        let app = InstalledApp(url: temp.url.appending(path: "Editor.app"), name: "Editor", bundleID: "com.vendor.editor", version: nil, searchNames: [])
        let report = try #require(LanguageReport.report(for: app, used: ["id", "en"]))
        #expect(report.unusedCount == 3)
        #expect(report.totalCount == 6)
        #expect(LanguageReport.report(for: app, used: ["id", "en", "de", "fr", "ja"]) == nil)
    }
}
