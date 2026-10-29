import Foundation
import SQLite3
import Testing
@testable import KhaiCleanMac

@Suite struct PrivacyTests {
    /// Creates a SQLite file and runs `sql` in it.
    private func database(_ url: URL, _ sql: String) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var db: OpaquePointer?
        defer { sqlite3_close(db) }
        try #require(sqlite3_open(url.path, &db) == SQLITE_OK)
        try #require(sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK)
    }

    private func chromeProfile(_ temp: TempFolder, _ name: String) throws -> URL {
        let profile = try temp.folder("Library/Application Support/Google/Chrome/\(name)")
        try temp.file("Library/Application Support/Google/Chrome/\(name)/Preferences")
        try database(profile.appending(path: "History"), "CREATE TABLE urls(id INTEGER); INSERT INTO urls VALUES (1),(2),(3);")
        try database(profile.appending(path: "Web Data"), """
            CREATE TABLE autofill(name TEXT, value TEXT); INSERT INTO autofill VALUES ('email','a@b.c'),('q','cats');
            CREATE TABLE credit_cards(guid TEXT); INSERT INTO credit_cards VALUES ('card');
            """)
        for file in ["Network/Cookies", "Visited Links", "Login Data", "Bookmarks"] {
            try temp.file("Library/Application Support/Google/Chrome/\(name)/\(file)")
        }
        return profile
    }

    @Test func findsChromiumDataButNeverPasswordsOrBookmarks() throws {
        let temp = try TempFolder()
        _ = try chromeProfile(temp, "Default")
        _ = try chromeProfile(temp, "Profile 1")
        try temp.folder("Library/Application Support/Google/Chrome/Crashpad")   // no Preferences: not a profile

        let items = PrivacyScanner(home: temp.url).items(for: .chrome)
        let byKind = Dictionary(uniqueKeysWithValues: items.map { ($0.kind, $0) })
        #expect(byKind[.history]?.profileCount == 2)
        #expect(byKind[.history]?.entryCount == 6)
        #expect(byKind[.formData]?.entryCount == 4)

        var files: [String] = []
        for item in items { if case .removeFiles(let urls) = item.action { files += urls.map(\.lastPathComponent) } }
        #expect(Set(files) == ["History", "Visited Links", "Cookies"])
        #expect(!files.contains("Login Data") && !files.contains("Bookmarks") && !files.contains("Web Data"))
    }

    @Test func clearingFormDataKeepsCardsAndAddresses() throws {
        let temp = try TempFolder()
        let profile = try chromeProfile(temp, "Default")
        let webData = profile.appending(path: "Web Data")

        #expect(PrivacyCleaner.clearAutofill(in: webData) == 2)
        #expect(PrivacyScanner.count("SELECT COUNT(*) FROM autofill", in: webData) == 0)
        #expect(PrivacyScanner.count("SELECT COUNT(*) FROM credit_cards", in: webData) == 1)
    }

    @Test func firefoxHistoryIsLeftToFirefox() throws {
        let temp = try TempFolder()
        let profile = try temp.folder("Library/Application Support/Firefox/Profiles/abcd.default-release")
        try temp.file("Library/Application Support/Firefox/Profiles/abcd.default-release/prefs.js")
        try temp.file("Library/Application Support/Firefox/Profiles/abcd.default-release/places.sqlite")
        try database(profile.appending(path: "cookies.sqlite"), "CREATE TABLE moz_cookies(id INTEGER); INSERT INTO moz_cookies VALUES (1);")
        try temp.file("Library/Application Support/Firefox/Profiles/abcd.default-release/formhistory.sqlite")

        let firefox = try #require(Browser.all.first { $0.name == "Firefox" })
        let items = PrivacyScanner(home: temp.url).items(for: firefox)
        let history = try #require(items.first { $0.kind == .history })
        #expect(!history.isSupported, "places.sqlite also holds bookmarks")
        #expect(items.first { $0.kind == .cookies }?.entryCount == 1)

        var files: [String] = []
        for item in items { if case .removeFiles(let urls) = item.action { files += urls.map(\.lastPathComponent) } }
        #expect(Set(files) == ["cookies.sqlite", "formhistory.sqlite"])
    }

    @Test func browsersWithoutDataAreLeftOut() throws {
        let temp = try TempFolder()
        #expect(PrivacyScanner(home: temp.url).scan().isEmpty)
    }
}
