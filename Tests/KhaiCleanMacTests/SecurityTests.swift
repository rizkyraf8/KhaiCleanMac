import Foundation
import Testing
@testable import KhaiCleanMac

/// Regression tests for the security review of 29 October 2026: nothing outside real leftovers may be
/// picked or removed, whatever an installed app writes in its Info.plist.
@Suite struct SafetyGuardTests {
    private let home = URL(filePath: "/Users/someone")

    @Test func refusesProtectedFoldersThemselves() {
        for path in ["/", "/Applications", "/System", "/Library", "/Users", "/Users/someone", "/Users/someone/Library",
                     "/Users/someone/Documents", "/Users/someone/Desktop", "/Users/someone/Downloads",
                     "/Users/someone/Library/Caches", "/Users/someone/Library/Application Support",
                     "/Users/someone/Library/Group Containers", "/Users/someone/.Trash", "/Volumes/Backup"] {
            #expect(!SafetyGuard.isAllowed(URL(filePath: path), home: home), "\(path) must be protected")
        }
    }

    @Test func refusesEverythingInsideSystemAndPersonalVaults() {
        for path in ["/System/Library/CoreServices", "/usr/local/bin/tool", "/Library/LaunchDaemons/x.plist",
                     "/Users/someone/Library/Keychains/login.keychain-db",
                     "/Users/someone/Library/Mobile Documents/com~apple~CloudDocs/file.txt"] {
            #expect(!SafetyGuard.isAllowed(URL(filePath: path), home: home), "\(path) must be protected")
        }
    }

    @Test func allowsRealJunkInsideThoseFolders() {
        for path in ["/Users/someone/Library/Caches/com.example.App", "/Users/someone/.Trash/old.zip",
                     "/Users/someone/Library/Application Support/com.example.App", "/Applications/Example.app",
                     "/Users/someone/Downloads/setup.dmg", "/Volumes/Backup/old-movie.mov"] {
            #expect(SafetyGuard.isAllowed(URL(filePath: path), home: home), "\(path) should be allowed")
        }
    }

    @Test func refusesDotDotPaths() {
        let sneaky = URL(filePath: "/Users/someone/Library/Application Support/../../Documents")
        #expect(!SafetyGuard.isAllowed(sneaky, home: home))
    }

    @Test func refusesASymlinkThatLeadsToAProtectedFolder() throws {
        let temp = try TempFolder()
        let fakeHome = try temp.folder("home")
        try temp.folder("home/Documents")
        let caches = try temp.folder("home/Library/Caches")
        // A "cache" folder that is really a link to the user's home.
        try FileManager.default.createSymbolicLink(at: caches.appending(path: "Evil"), withDestinationURL: fakeHome)

        #expect(!SafetyGuard.isAllowed(caches.appending(path: "Evil/Documents"), home: fakeHome))
        #expect(SafetyGuard.isAllowed(caches.appending(path: "Evil"), home: fakeHome),
                "Removing the link itself only removes the link")
    }

    @Test func trasherSkipsProtectedItemsAndReportsThem() throws {
        let temp = try TempFolder()
        let fakeHome = try temp.folder("home")
        let documents = try temp.folder("home/Documents")
        try temp.file("home/Documents/thesis.pages")
        let junk = try temp.file("home/Library/Caches/com.example.App/blob")
        let bin = try temp.folder("bin")

        let report = Trasher.remove(
            [CleanItem(url: documents, size: 1), CleanItem(url: junk.deletingLastPathComponent(), size: 1)],
            permanently: true, stagingRoot: temp.url.appending(path: "staging"), home: fakeHome,
            trash: { url in
                let target = bin.appending(path: url.lastPathComponent)
                try FileManager.default.moveItem(at: url, to: target)
                return target
            }
        )

        #expect(report.blocked.map(\.url) == [documents])
        #expect(report.movedCount == 1)
        #expect(temp.exists("home/Documents/thesis.pages"), "Documents must survive even in permanent mode")
        #expect(!temp.exists("home/Library/Caches/com.example.App"))
    }
}

@Suite struct UninstallerLeftoverTests {
    /// Builds a fake app bundle whose Info.plist says whatever the test wants.
    private func fakeApp(in temp: TempFolder, file: String, id: String, name: String) throws -> InstalledApp {
        let app = try temp.folder("Applications/\(file).app/Contents")
        let info: NSDictionary = ["CFBundleIdentifier": id, "CFBundleName": name, "CFBundlePackageType": "APPL"]
        try info.write(to: app.appending(path: "Info.plist"))
        return try #require(AppScanner().makeApp(temp.url.appending(path: "Applications/\(file).app")))
    }

    @Test func aNameThatClimbsOutOfLibraryIsIgnored() throws {
        let temp = try TempFolder()
        let home = try temp.folder("home")
        try temp.file("home/Documents/thesis.pages")
        try temp.file("home/Library/Application Support/com.evil.App/settings.json")
        let app = try fakeApp(in: temp, file: "Evil", id: "com.evil.App", name: "../../Documents")

        let leftovers = AppScanner().leftovers(for: app, home: home)
        let paths = leftovers.map { $0.url.standardizedFileURL.path }

        #expect(!paths.contains { $0.hasSuffix("/home/Documents") }, "~/Documents must never be a leftover")
        #expect(paths.contains { $0.hasSuffix("Application Support/com.evil.App") }, "Its real leftover is still found")
    }

    @Test func anEmptyOrTinyBundleIDMatchesNothing() throws {
        let temp = try TempFolder()
        let home = try temp.folder("home")
        try temp.file("home/Library/LaunchAgents/com.other.agent.plist")
        try temp.file("home/Library/Group Containers/group.com.whatsapp/data")
        try temp.file("home/Library/Group Containers/UBF8T346G9.Office/data")

        for id in ["", "co", "a.b", "../../x", "com..x", ".com.x"] {
            let app = try fakeApp(in: temp, file: "Odd\(id.count)", id: id.isEmpty ? "placeholder" : id, name: "Odd")
            let probe = InstalledApp(url: app.url, name: app.name, bundleID: id, version: nil, searchNames: app.searchNames)
            #expect(AppScanner().leftovers(for: probe, home: home).isEmpty, "id \"\(id)\" must match nothing")
        }
    }

    @Test func bundleIDsMatchExactlyNotBySubstring() throws {
        let temp = try TempFolder()
        let home = try temp.folder("home")
        try temp.file("home/Library/LaunchAgents/com.foo.bar.plist")
        try temp.file("home/Library/LaunchAgents/com.foo.bar.helper.plist")
        try temp.file("home/Library/LaunchAgents/com.foo.barista.plist")
        try temp.file("home/Library/Group Containers/ABCDE12345.com.foo.bar/data")
        try temp.file("home/Library/Group Containers/group.com.foo.bar/data")
        try temp.file("home/Library/Group Containers/group.com.foo.barista/data")
        let app = try fakeApp(in: temp, file: "Bar", id: "com.foo.bar", name: "Bar")

        let names = Set(AppScanner().leftovers(for: app, home: home).map(\.url.lastPathComponent))
        #expect(names == ["com.foo.bar.plist", "com.foo.bar.helper.plist", "ABCDE12345.com.foo.bar", "group.com.foo.bar"])
    }

    @Test func nameMatchesAreMarkedAsGuesses() throws {
        let temp = try TempFolder()
        let home = try temp.folder("home")
        try temp.file("home/Library/Application Support/com.notes.Pro/db")
        try temp.file("home/Library/Application Support/Notes Pro/db")
        try temp.file("home/Library/Application Support/Google/Chrome/Local State")
        let app = try fakeApp(in: temp, file: "Notes Pro", id: "com.notes.Pro", name: "Google")

        let leftovers = AppScanner().leftovers(for: app, home: home)
        let byName = Dictionary(uniqueKeysWithValues: leftovers.map { ($0.url.lastPathComponent, $0) })
        #expect(byName["com.notes.Pro"]?.isGuess == false)
        #expect(byName["Notes Pro"]?.isGuess == true)
        #expect(byName["Google"] == nil, "Generic vendor names are never matched")
    }

    @Test func validatesBundleIDsAndNames() {
        #expect(AppScanner.isValidBundleID("com.example.App"))
        #expect(AppScanner.isValidBundleID("io.my-company.app_2"))
        #expect(!AppScanner.isValidBundleID("com"))
        #expect(!AppScanner.isValidBundleID("com/../x.y"))
        #expect(!AppScanner.isValidBundleID("com..example"))
        #expect(AppScanner.isSafeName("Visual Studio Code"))
        #expect(!AppScanner.isSafeName(".."))
        #expect(!AppScanner.isSafeName("../../Documents"))
        #expect(!AppScanner.isSafeName(".hidden"))
        #expect(!AppScanner.isSafeName("Library"))
        #expect(!AppScanner.isSafeName(" Spaced "))
    }
}

@Suite struct ProtectedCacheTests {
    @Test func activeSystemCachesAreNeverOffered() throws {
        let temp = try TempFolder()
        try temp.file("Library/Caches/com.apple.nsurlsessiond/download.tmp")
        try temp.file("Library/Caches/CloudKit/db")
        try temp.file("Library/Caches/com.example.App/blob")

        let names = Set(JunkScanner(home: temp.url).scan(.userCache).map(\.name))
        #expect(names == ["com.example.App"])
    }
}

@Suite struct UpdateLinkTests {
    @Test func onlyHttpsLinksOnTheOwnDomainAreTrusted() {
        #expect(UpdateAPI.trustedURL("https://rizkyraf.id/d/khaicleanmac-0340") != nil)
        #expect(UpdateAPI.trustedURL("https://cdn.rizkyraf.id/KhaiCleanMac.dmg") != nil)
        #expect(UpdateAPI.trustedURL("http://rizkyraf.id/d/x") == nil, "No plain http")
        #expect(UpdateAPI.trustedURL("file:///Applications/Terminal.app") == nil, "Never a local file")
        #expect(UpdateAPI.trustedURL("https://rizkyraf.id.evil.com/x.dmg") == nil, "Look-alike host")
        #expect(UpdateAPI.trustedURL("https://evilrizkyraf.id/x.dmg") == nil, "Look-alike host")
        #expect(UpdateAPI.trustedURL("https://user:pass@rizkyraf.id/x") == nil, "No credentials in links")
        #expect(UpdateAPI.trustedURL("x-apple.systempreferences:com.apple.preference.security") == nil)
    }

    @Test func untrustedLinksFromTheAPIAreDropped() throws {
        let json = Data(#"{"project":{"url":"http://example.com"},"latest":{"version":"9.9.9","download_url":"file:///Applications/Terminal.app"}}"#.utf8)
        let release = try UpdateAPI.decode(json)
        #expect(release.downloadURL == nil)
        #expect(release.pageURL == nil, "The built-in project page is used instead")
    }
}
