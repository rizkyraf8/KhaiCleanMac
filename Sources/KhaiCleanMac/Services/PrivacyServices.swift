import Foundation
import SQLite3

enum PrivacyKind: String, CaseIterable, Sendable {
    case history, cookies, formData

    var title: String {
        switch self {
        case .history: L("Riwayat penelusuran", "Browsing history")
        case .cookies: L("Cookie", "Cookies")
        case .formData: L("Isian formulir", "Form data")
        }
    }

    var symbol: String {
        switch self {
        case .history: "clock.fill"
        case .cookies: "circle.hexagongrid.fill"
        case .formData: "text.cursor"
        }
    }

    /// What the user gives up, said before anything is picked.
    var consequence: String {
        switch self {
        case .history: L("Situs yang pernah dibuka, unduhan, dan saran di bilah alamat hilang. Bookmark tetap aman.",
                         "Visited sites, the download list and address bar suggestions are cleared. Bookmarks stay.")
        case .cookies: L("Kamu akan keluar dari semua situs dan harus login lagi.",
                         "You'll be signed out of every site and have to sign in again.")
        case .formData: L("Saran isian yang tersimpan (nama, email, pencarian) hilang. Password, alamat, dan kartu tidak disentuh.",
                          "Saved suggestions for form fields (names, emails, searches) are cleared. Passwords, addresses and cards aren't touched.")
        }
    }
}

/// One kind of data in one browser, across all its profiles.
struct PrivacyItem: Identifiable, Hashable, Sendable {
    enum Action: Hashable, Sendable {
        /// Files the browser recreates empty: moved the way the user chose (the Trash by default).
        case removeFiles([URL])
        /// Rows inside a database that holds other things too, deleted for good.
        case clearAutofill(databases: [URL])
        /// Not something this app can clear safely; the note says how.
        case unsupported(note: String)
    }

    let browserName: String
    let kind: PrivacyKind
    let action: Action
    let size: Int64
    /// History entries or saved form values, when the database could be read.
    let entryCount: Int?
    let profileCount: Int

    var id: String { "\(browserName)|\(kind.rawValue)" }
    var isSupported: Bool { if case .unsupported = action { false } else { true } }
}

struct BrowserPrivacy: Identifiable, Sendable {
    let browser: Browser
    let items: [PrivacyItem]
    var id: String { browser.name }
}

/// Finds history, cookies and form data per browser. Only reads; nothing is changed here.
struct PrivacyScanner: Sendable {
    var home = URL.homeDirectory

    /// Where each browser keeps its profiles, relative to the home folder.
    static let profileRoots: [String: String] = [
        "Chrome": "Library/Application Support/Google/Chrome",
        "Brave": "Library/Application Support/BraveSoftware/Brave-Browser",
        "Edge": "Library/Application Support/Microsoft Edge",
        "Arc": "Library/Application Support/Arc/User Data",
        "Vivaldi": "Library/Application Support/Vivaldi",
        "Firefox": "Library/Application Support/Firefox/Profiles",
    ]

    /// Chromium recreates these when they're missing. "Login Data", "Bookmarks" and "Web Data"
    /// (passwords, bookmarks, addresses and cards) are deliberately not in any list.
    static let chromiumHistoryFiles = [
        "History", "History-journal", "Visited Links", "Top Sites", "Top Sites-journal",
        "Shortcuts", "Shortcuts-journal", "Network Action Predictor", "Network Action Predictor-journal",
    ]
    static let chromiumCookieFiles = ["Cookies", "Cookies-journal", "Network/Cookies", "Network/Cookies-journal"]
    static let firefoxCookieFiles = ["cookies.sqlite", "cookies.sqlite-wal", "cookies.sqlite-shm"]
    static let firefoxFormFiles = ["formhistory.sqlite", "formhistory.sqlite-wal", "formhistory.sqlite-shm"]
    static let safariHistoryFiles = ["History.db", "History.db-wal", "History.db-shm", "History.db-lock"]

    func scan() -> [BrowserPrivacy] {
        Browser.all.compactMap { browser in
            let items = items(for: browser)
            return items.isEmpty ? nil : BrowserPrivacy(browser: browser, items: items)
        }
    }

    func items(for browser: Browser) -> [PrivacyItem] {
        switch browser.layout {
        case .chromium: chromium(browser)
        case .firefox: firefox(browser)
        case .safari: safari(browser)
        }
    }

    // MARK: Chromium

    /// "Default", "Profile 1", … : every folder with a Preferences file.
    func chromiumProfiles(_ browser: Browser) -> [URL] {
        guard let root = Self.profileRoots[browser.name].map({ home.appending(path: $0) }) else { return [] }
        return Self.subfolders(of: root).filter { FileManager.default.fileExists(atPath: $0.appending(path: "Preferences").path) }
    }

    private func chromium(_ browser: Browser) -> [PrivacyItem] {
        let profiles = chromiumProfiles(browser)
        guard !profiles.isEmpty else { return [] }
        let history = Self.existing(Self.chromiumHistoryFiles, in: profiles)
        let cookies = Self.existing(Self.chromiumCookieFiles, in: profiles)
        let webData = profiles.map { $0.appending(path: "Web Data") }.filter { FileManager.default.fileExists(atPath: $0.path) }
        return [
            item(browser, .history, files: history, profiles: profiles.count,
                 count: Self.sum(profiles.map { Self.count("SELECT COUNT(*) FROM urls", in: $0.appending(path: "History")) })),
            item(browser, .cookies, files: cookies, profiles: profiles.count,
                 count: nil),
            webData.isEmpty ? nil : PrivacyItem(
                browserName: browser.name, kind: .formData, action: .clearAutofill(databases: webData), size: 0,
                entryCount: Self.sum(webData.map { Self.count("SELECT COUNT(*) FROM autofill", in: $0) }), profileCount: profiles.count),
        ].compactMap { $0 }
    }

    // MARK: Firefox

    private func firefox(_ browser: Browser) -> [PrivacyItem] {
        guard let root = Self.profileRoots[browser.name].map({ home.appending(path: $0) }) else { return [] }
        let profiles = Self.subfolders(of: root).filter { FileManager.default.fileExists(atPath: $0.appending(path: "prefs.js").path) }
        guard !profiles.isEmpty else { return [] }
        return [
            // History shares places.sqlite with bookmarks, so removing the file would take bookmarks too.
            PrivacyItem(browserName: browser.name, kind: .history,
                        action: .unsupported(note: L("Riwayat Firefox satu file dengan bookmark. Hapus lewat Firefox: Riwayat › Hapus Riwayat Terkini (⌘⇧⌫).",
                                                     "Firefox keeps history in the same file as bookmarks. Clear it in Firefox: History › Clear Recent History (⌘⇧⌫).")),
                        size: 0, entryCount: nil, profileCount: profiles.count),
            item(browser, .cookies, files: Self.existing(Self.firefoxCookieFiles, in: profiles), profiles: profiles.count,
                 count: Self.sum(profiles.map { Self.count("SELECT COUNT(*) FROM moz_cookies", in: $0.appending(path: "cookies.sqlite")) })),
            item(browser, .formData, files: Self.existing(Self.firefoxFormFiles, in: profiles), profiles: profiles.count,
                 count: Self.sum(profiles.map { Self.count("SELECT COUNT(*) FROM moz_formhistory", in: $0.appending(path: "formhistory.sqlite")) })),
        ].compactMap { $0 }
    }

    // MARK: Safari

    private func safari(_ browser: Browser) -> [PrivacyItem] {
        let safariFolder = home.appending(path: "Library/Safari")
        let history = Self.existing(Self.safariHistoryFiles, in: [safariFolder])
        let cookies = Self.existing(["Library/Containers/com.apple.Safari/Data/Library/Cookies/Cookies.binarycookies"], in: [home])
        guard !history.isEmpty || !cookies.isEmpty else { return [] }
        return [
            item(browser, .history, files: history, profiles: 1,
                 count: Self.count("SELECT COUNT(*) FROM history_items", in: safariFolder.appending(path: "History.db"))),
            item(browser, .cookies, files: cookies, profiles: 1, count: nil),
            PrivacyItem(browserName: browser.name, kind: .formData,
                        action: .unsupported(note: L("Safari menyimpan isian formulir di Keychain. Hapus lewat Safari › Pengaturan › IsiOtomatis.",
                                                     "Safari keeps form data in the Keychain. Clear it in Safari › Settings › AutoFill.")),
                        size: 0, entryCount: nil, profileCount: 1),
        ].compactMap { $0 }
    }

    // MARK: Helpers

    private func item(_ browser: Browser, _ kind: PrivacyKind, files: [URL], profiles: Int, count: Int?) -> PrivacyItem? {
        guard !files.isEmpty else { return nil }
        return PrivacyItem(browserName: browser.name, kind: kind, action: .removeFiles(files),
                           size: files.reduce(0) { $0 + FileSizer.allocatedSize(of: $1) }, entryCount: count, profileCount: profiles)
    }

    private static func existing(_ names: [String], in folders: [URL]) -> [URL] {
        folders.flatMap { folder in
            names.map { folder.appending(path: $0) }.filter { FileManager.default.fileExists(atPath: $0.path) }
        }
    }

    private static func subfolders(of folder: URL) -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? [])
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private static func sum(_ counts: [Int?]) -> Int? {
        let known = counts.compactMap { $0 }
        return known.isEmpty ? nil : known.reduce(0, +)
    }

    /// Reads a count without touching the file: an open browser locks its databases, so this may be nil.
    static func count(_ query: String, in database: URL) -> Int? {
        guard FileManager.default.fileExists(atPath: database.path) else { return nil }
        var db: OpaquePointer?
        defer { sqlite3_close(db) }
        guard sqlite3_open_v2(database.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return nil }
        sqlite3_busy_timeout(db, 200)
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK,
              sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return Int(sqlite3_column_int64(statement, 0))
    }
}

enum PrivacyCleaner {
    /// Removes the picked data. Callers make sure the browser is closed first.
    static func clean(_ items: [PrivacyItem], source: String) async -> (report: CleanReport, clearedEntries: Int, failedDatabases: Int) {
        var files: [CleanItem] = []
        var cleared = 0
        var failed = 0
        for item in items {
            switch item.action {
            case .removeFiles(let urls):
                files += urls.map { url in
                    CleanItem(url: url, size: FileSizer.allocatedSize(of: url),
                              title: "\(item.browserName) · \(item.kind.title) · \(url.lastPathComponent)")
                }
            case .clearAutofill(let databases):
                for database in databases {
                    if let count = clearAutofill(in: database) { cleared += count } else { failed += 1 }
                }
            case .unsupported:
                continue
            }
        }
        let report = files.isEmpty ? CleanReport() : await Trasher.removeRecorded(files, source: source)
        return (report, cleared, failed)
    }

    /// Empties Chromium's list of remembered form values. The same database holds addresses, cards
    /// and search engines, so only the `autofill` table is touched. Returns how many rows went, or nil.
    static func clearAutofill(in database: URL) -> Int? {
        guard SafetyGuard.isAllowed(database) else { return nil }
        var db: OpaquePointer?
        defer { sqlite3_close(db) }
        guard sqlite3_open_v2(database.path, &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else { return nil }
        sqlite3_busy_timeout(db, 1000)
        guard sqlite3_exec(db, "BEGIN IMMEDIATE; DELETE FROM autofill; COMMIT;", nil, nil, nil) == SQLITE_OK else {
            sqlite3_exec(db, "ROLLBACK;", nil, nil, nil)
            return nil
        }
        return Int(sqlite3_changes(db))
    }
}
