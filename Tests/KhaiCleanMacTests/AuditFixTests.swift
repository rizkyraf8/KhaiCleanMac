import Foundation
import Testing
@testable import KhaiCleanMac

/// Regression tests for the October 2026 audit: what the Uninstaller may match, what SafetyGuard
/// refuses, how partial removals are reported, and the smaller fixes around them.
@Suite struct AuditFixTests {
    private func fakeApp(in temp: TempFolder, file: String, id: String, name: String) throws -> InstalledApp {
        let app = try temp.folder("Applications/\(file).app/Contents")
        let info: NSDictionary = ["CFBundleIdentifier": id, "CFBundleName": name, "CFBundlePackageType": "APPL"]
        try info.write(to: app.appending(path: "Info.plist"))
        let url = temp.url.appending(path: "Applications/\(file).app")
        return InstalledApp(url: url, name: file, bundleID: id, version: nil, searchNames: [file, name])
    }

    // MARK: Uninstaller

    @Test func anAppleIDInOtherLetterCaseIsNotAnApp() throws {
        #expect(AppScanner.isAppleID("Com.Apple.mail"))
        #expect(AppScanner.isAppleID("COM.APPLE.Notes"))
        #expect(!AppScanner.isAppleID("com.applesoft.Tool"))
        let temp = try TempFolder()
        let app = try temp.folder("Fake.app/Contents")
        try (["CFBundleIdentifier": "Com.Apple.mail", "CFBundlePackageType": "APPL"] as NSDictionary)
            .write(to: app.appending(path: "Info.plist"))
        #expect(AppScanner().makeApp(temp.url.appending(path: "Fake.app")) == nil)
    }

    /// The disk ignores letter case, so a folder spelled differently from the ID is another app's.
    @Test func foldersMustBeSpelledExactlyLikeTheID() throws {
        let temp = try TempFolder()
        let home = try temp.folder("home")
        try temp.file("home/Library/Containers/com.vendor.mail/Data/db")
        try temp.file("home/Library/Preferences/com.vendor.mail.plist")
        try temp.file("home/Library/Caches/com.vendor.Mail/cache")
        let app = try fakeApp(in: temp, file: "Mail Clone", id: "com.vendor.Mail", name: "Mail Clone")

        let leftovers = AppScanner().leftovers(for: app, home: home, ownGroups: [], otherAppsGroups: [], otherAppIDs: [])
        #expect(leftovers.map(\.url.lastPathComponent) == ["com.vendor.Mail"], "Only the cache spelled like the ID")
    }

    @Test func anIDAnotherInstalledAppAlsoUsesMatchesNothing() throws {
        let temp = try TempFolder()
        let home = try temp.folder("home")
        try temp.file("home/Library/Containers/com.tinyspeck.slackmacgap/Data/db")
        let app = try fakeApp(in: temp, file: "Slack Copy", id: "com.tinyspeck.slackmacgap", name: "Slack")

        let shared = AppScanner().leftovers(for: app, home: home, ownGroups: [], otherAppsGroups: [],
                                            otherAppIDs: ["com.tinyspeck.slackmacgap"])
        #expect(shared.isEmpty, "The other copy still uses that data")
        let own = AppScanner().leftovers(for: app, home: home, ownGroups: [], otherAppsGroups: [], otherAppIDs: [])
        #expect(own.count == 1)
    }

    @Test func aContainerThatNamesAnotherOwnerIsSkipped() throws {
        let temp = try TempFolder()
        let home = try temp.folder("home")
        let container = try temp.folder("home/Library/Containers/com.foo.App")
        try (["MCMMetadataIdentifier": "com.someone.Else"] as NSDictionary)
            .write(to: container.appending(path: ".com.apple.containermanagerd.metadata.plist"))
        let app = try fakeApp(in: temp, file: "Foo", id: "com.foo.App", name: "Foo")
        #expect(AppScanner().leftovers(for: app, home: home, ownGroups: [], otherAppsGroups: [], otherAppIDs: []).isEmpty)

        try (["MCMMetadataIdentifier": "com.foo.App"] as NSDictionary)
            .write(to: container.appending(path: ".com.apple.containermanagerd.metadata.plist"))
        #expect(AppScanner().leftovers(for: app, home: home, ownGroups: [], otherAppsGroups: [], otherAppIDs: []).count == 1)
    }

    @Test func appsNamedLikeSystemDataAreNeverMatchedByName() {
        for name in ["AddressBook", "MobileSync", "CallHistoryDB", "Knowledge", "com.apple.TCC"] {
            #expect(!AppScanner.isSafeName(name), "\(name)")
        }
        #expect(AppScanner.isSafeName("Notes Pro"))
        #expect(!AppScanner.isValidBundleID("com.vendör.app"), "IDs are ASCII")
    }

    // MARK: SafetyGuard

    @Test func letterCaseDoesNotGetPastTheGuard() {
        let home = URL(filePath: "/Users/someone")
        for path in ["/Users/someone/documents", "/users/someone/Library", "/USERS/SOMEONE/DESKTOP",
                     "/LIBRARY/Preferences/x.plist", "/system/Library/x", "/volumes/Backup",
                     "/Users/someone/library/keychains/login.keychain-db"] {
            #expect(!SafetyGuard.isAllowed(URL(filePath: path), home: home), "\(path)")
        }
        #expect(SafetyGuard.isAllowed(URL(filePath: "/Users/someone/Documents/old.zip"), home: home))
    }

    // MARK: Partial removals

    @Test func aPartlyDeletedItemCountsOnlyWhatWent() throws {
        let temp = try TempFolder()
        let gone = try temp.file("cache/a", size: 4096)
        let stuck = try temp.file("cache/locked/b", size: 4096)
        let locked = temp.url.appending(path: "cache/locked")
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: locked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path) }

        let item = CleanItem(url: temp.url.appending(path: "cache"), size: 1_000_000, members: [gone, stuck])
        let report = Trasher.remove([item], permanently: true, stagingRoot: temp.url.appending(path: "staging"))

        #expect(report.movedCount == 0, "Not everything went, so it isn't counted as removed")
        #expect(report.failed.map(\.url) == [item.url], "It stays listed")
        #expect(report.movedSize > 0 && report.movedSize < 1_000_000, "Only the deleted file's size")
        #expect(report.removed.count == 1, "History still shows what was deleted")
        #expect(!temp.exists("cache/a") && temp.exists("cache/locked/b"))
    }

    // MARK: Smart Scan

    @Test func poetryEnvironmentsAndAppUpdatesStay() throws {
        let temp = try TempFolder()
        try temp.file("Library/Caches/pypoetry/virtualenvs/proj-py3.12/bin/python", size: 4096)
        try temp.file("Library/Caches/pypoetry/cache/repositories/pypi/x", size: 4096)
        try temp.file("Library/Caches/com.vendor.app.ShipIt/update.zip", size: 4096)
        try temp.file("Library/Caches/com.vendor.app/data", size: 4096)

        let names = Set(JunkScanner(home: temp.url).scan(.userCache).map(\.name))
        #expect(names.contains("pypoetry/cache"))
        #expect(names.contains("com.vendor.app"))
        #expect(!names.contains { $0.contains("virtualenvs") || $0.hasSuffix(".ShipIt") })
    }

    // MARK: History

    @Test func anUnrelatedFileWithTheSameNameInTheTrashIsNotRestored() throws {
        let temp = try TempFolder()
        let bin = try temp.folder("bin")
        let file = try temp.file("docs/report.txt")
        let report = Trasher.remove([CleanItem(url: file, size: 16)], permanently: false,
                                    stagingRoot: temp.url.appending(path: "staging")) { url in
            let target = bin.appending(path: url.lastPathComponent)
            try FileManager.default.moveItem(at: url, to: target)
            return target
        }
        let removed = try #require(report.removed.first)
        #expect(removed.trashedFileNumber != nil)
        // The Trash was emptied and something else landed under the same name.
        try FileManager.default.removeItem(at: bin.appending(path: "report.txt"))
        try temp.file("bin/report.txt", size: 64)

        #expect(Restorer.restore(removed) == .notInTrash)
        #expect(!temp.exists("docs/report.txt"))
    }

    @Test func olderHistoryWithoutFileNumbersStillLoads() throws {
        let json = #"[{"id":"\#(UUID())","date":"2026-10-01T00:00:00Z","source":"Smart Scan","permanent":false,"items":[{"id":"\#(UUID())","name":"x","originalPath":"/tmp/x","size":1,"trashedPath":"/tmp/t","memberPaths":[]}]}]"#
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let records = try decoder.decode([CleanRecord].self, from: Data(json.utf8))
        #expect(records.first?.items.first?.trashedFileNumber == nil)
    }

    // MARK: Disks

    @Test func apfsTimeMachineDisksAndBootableClonesAreRecognized() throws {
        let temp = try TempFolder()
        #expect(!ScanLocation.isTimeMachineBackup(temp.url))
        try temp.folder("old.backup")
        #expect(!ScanLocation.isTimeMachineBackup(temp.url), "Only Time Machine's dated folders count")
        try temp.folder("2026-10-29-101500.backup")
        #expect(ScanLocation.isTimeMachineBackup(temp.url))

        let clone = try temp.folder("clone")
        #expect(!ScanLocation.skips(clone.appending(path: "Applications"), root: clone))
        try temp.file("clone/System/Library/CoreServices/SystemVersion.plist")
        #expect(ScanLocation.skips(clone.appending(path: "Applications"), root: clone))
        #expect(ScanLocation.skips(clone.appending(path: "Users"), root: clone))
        #expect(!ScanLocation.skips(clone.appending(path: "Projects"), root: clone))
    }

    // MARK: Memory

    @Test func appsInsideAnotherAppsApplicationsFolderAreTheirOwn() {
        let simulator = "/Applications/Xcode.app/Contents/Developer/Applications/Simulator.app/Contents/MacOS/Simulator"
        #expect(AppMemoryScanner.enclosingApp(of: simulator)?.lastPathComponent == "Simulator.app")
        let helper = "/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Helpers/Google Chrome Helper.app/Contents/MacOS/Google Chrome Helper"
        #expect(AppMemoryScanner.enclosingApp(of: helper)?.lastPathComponent == "Google Chrome.app")
        #expect(AppMemoryScanner.enclosingApp(of: "/usr/libexec/thing") == nil)
    }

    // MARK: Commands

    @Test func aToolThatHangsIsStopped() {
        let start = Date()
        #expect(StartupScanner.run("/bin/sleep", ["30"], timeout: 1) == nil)
        #expect(Date().timeIntervalSince(start) < 10)
        #expect(StartupScanner.run("/bin/echo", ["hi"]) == "hi\n")
    }
}
