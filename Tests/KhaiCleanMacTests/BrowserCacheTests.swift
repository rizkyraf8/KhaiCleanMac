import Foundation
import Testing
@testable import KhaiCleanMac

@Suite struct BrowserCacheTests {
    @Test func recognizesSimpleCacheEntryNames() {
        #expect(BrowserCacheScanner.entryKey("0123456789abcdef_0") == "0123456789abcdef")
        #expect(BrowserCacheScanner.entryKey("0123456789abcdef_1") == "0123456789abcdef")
        #expect(BrowserCacheScanner.entryKey("0123456789abcdef_s") == "0123456789abcdef")
        #expect(BrowserCacheScanner.entryKey("index") == nil)
        #expect(BrowserCacheScanner.entryKey("the-real-index") == nil)
        #expect(BrowserCacheScanner.entryKey("0123456789abcdeg_0") == nil, "Not hex")
        #expect(BrowserCacheScanner.entryKey("0123456789abcdef_2") == nil, "Unknown stream")
        #expect(BrowserCacheScanner.entryKey("0123456789abcde_0") == nil, "Too short")
    }

    @Test func picksOnlyStaleWebCacheEntriesAsWholeSets() throws {
        let temp = try TempFolder()
        let cache = "Library/Caches/Google/Chrome/Default/Cache/Cache_Data"
        try temp.file("\(cache)/aaaaaaaaaaaaaaaa_0", daysOld: 60)
        try temp.file("\(cache)/aaaaaaaaaaaaaaaa_s", daysOld: 60)
        // One file of this entry was used yesterday, so the whole entry stays.
        try temp.file("\(cache)/bbbbbbbbbbbbbbbb_0", daysOld: 60)
        try temp.file("\(cache)/bbbbbbbbbbbbbbbb_1", daysOld: 1)
        try temp.file("\(cache)/index", daysOld: 60)

        let scanner = BrowserCacheScanner(maxAgeDays: 30, home: temp.url, applicationFolders: [])
        let items = scanner.scan(.chrome)
        let web = try #require(items.first { $0.url.path.hasSuffix("Cache_Data") })
        let names = Set(web.members.map(\.lastPathComponent))

        #expect(names == ["aaaaaaaaaaaaaaaa_0", "aaaaaaaaaaaaaaaa_s"])
        #expect(web.title?.contains("Chrome") == true)
    }

    @Test func codeCacheFromBeforeTheInstalledVersionIsObsolete() throws {
        let temp = try TempFolder()
        let apps = try temp.folder("Applications")
        let versions = try temp.folder("Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Versions")
        let installed = try temp.folder("Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Versions/200.0.1.2")
        try FileManager.default.createSymbolicLink(at: versions.appending(path: "Current"), withDestinationURL: installed)

        let js = "Library/Caches/Google/Chrome/Default/Code Cache/js"
        try temp.file("\(js)/aaaaaaaaaaaaaaaa_0", daysOld: 3)
        // Written after the install date: made by the current version, so it must stay.
        try temp.file("\(js)/bbbbbbbbbbbbbbbb_0", daysOld: -1)

        let scanner = BrowserCacheScanner(maxAgeDays: 30, home: temp.url, applicationFolders: [apps])
        #expect(scanner.installDate(of: .chrome) != nil)
        let code = try #require(scanner.scan(.chrome).first { $0.url.lastPathComponent == "Code Cache" })
        #expect(code.members.map(\.lastPathComponent) == ["aaaaaaaaaaaaaaaa_0"])
    }

    @Test func firefoxEntriesAgeOutPerFile() throws {
        let temp = try TempFolder()
        let entries = "Library/Caches/Firefox/Profiles/x1y2.default-release/cache2/entries"
        try temp.file("\(entries)/0A1B2C3D", daysOld: 45)
        try temp.file("\(entries)/4E5F6A7B", daysOld: 2)

        let scanner = BrowserCacheScanner(maxAgeDays: 30, home: temp.url, applicationFolders: [])
        let browser = try #require(Browser.all.first { $0.name == "Firefox" })
        let item = try #require(scanner.scan(browser).first)
        #expect(item.members.map(\.lastPathComponent) == ["0A1B2C3D"])
        #expect(item.title?.contains("default-release") == true)
    }

    @Test func safariKeepsItsSaltFile() throws {
        let temp = try TempFolder()
        let root = "Library/Containers/com.apple.Safari/Data/Library/Caches/com.apple.Safari/WebKitCache/Version 17"
        try temp.file("\(root)/salt", daysOld: 400)
        try temp.file("\(root)/Records/abc/Resource/old", daysOld: 90)

        let scanner = BrowserCacheScanner(maxAgeDays: 30, home: temp.url, applicationFolders: [])
        let browser = try #require(Browser.all.first { $0.name == "Safari" })
        let item = try #require(scanner.scan(browser).first)
        #expect(item.members.map(\.lastPathComponent) == ["old"])
    }

    @Test func onlyOldHeadlessFoldersAreLeftovers() throws {
        let temp = try TempFolder()
        let old = try temp.folder("Library/Caches/Google/Chrome-headless/scoped_dir_old")
        let fresh = try temp.folder("Library/Caches/Google/Chrome-headless/scoped_dir_new")
        try temp.age(old, days: 3)
        try temp.age(fresh, days: 0)

        let scanner = BrowserCacheScanner(maxAgeDays: 30, home: temp.url, applicationFolders: [])
        let item = try #require(scanner.headlessLeftovers())
        #expect(item.members.map(\.lastPathComponent) == ["scoped_dir_old"])
    }

    @Test func mapsCacheFoldersToTheirBrowser() {
        let home = URL(filePath: "/Users/someone")
        let chrome = home.appending(path: "Library/Caches/Google/Chrome/Default/Cache/Cache_Data")
        let brave = home.appending(path: "Library/Caches/BraveSoftware/Brave-Browser/Default/Code Cache")
        let headless = home.appending(path: "Library/Caches/Google/Chrome-headless")
        #expect(Browser.owning(chrome, home: home)?.name == "Chrome")
        #expect(Browser.owning(brave, home: home)?.name == "Brave")
        #expect(Browser.owning(headless, home: home) == nil, "Headless leftovers don't belong to the open browser")
    }
}
