import Foundation
import Testing
@testable import KhaiCleanMac

@Suite struct JunkScannerTests {
    @Test func vendorFoldersAreSplitPerAppAndBrowsersAreLeftOut() throws {
        let temp = try TempFolder()
        try temp.file("Library/Caches/Google/AndroidStudio2026.1/cache.bin")
        try temp.file("Library/Caches/Google/Chrome/Default/Cache/Cache_Data/aaaaaaaaaaaaaaaa_0")
        try temp.file("Library/Caches/com.example.App/data")
        try temp.file("Library/Caches/Firefox/Profiles/p/cache2/entries/AB")

        let items = JunkScanner(home: temp.url).scan(.userCache)
        let names = Set(items.map(\.name))
        #expect(names == ["Google/AndroidStudio2026.1", "com.example.App"])
    }

    @Test func trashItemsAreAlwaysPermanent() throws {
        let temp = try TempFolder()
        try temp.file(".Trash/old.zip", size: 64)

        let items = JunkScanner(home: temp.url).scan(.trash)
        #expect(items.count == 1)
        #expect(items.allSatisfy { $0.removesPermanently })
    }

    @Test func iosBackupsUseTheDeviceName() throws {
        let temp = try TempFolder()
        let backup = try temp.folder("Library/Application Support/MobileSync/Backup/00008110-ABC")
        let info: NSDictionary = ["Device Name": "iPhone Khai", "Last Backup Date": Date()]
        try info.write(to: backup.appending(path: "Info.plist"))
        try temp.file("Library/iTunes/iPhone Software Updates/iPhone_18.0_Restore.ipsw", size: 128)

        let items = JunkScanner(home: temp.url).scan(.iosBackups)
        #expect(items.count == 2)
        #expect(items.contains { $0.name.contains("iPhone Khai") })
        #expect(items.contains { $0.url.pathExtension == "ipsw" })
    }

    @Test func mailAttachmentCopiesAreListed() throws {
        let temp = try TempFolder()
        try temp.file("Library/Containers/com.apple.mail/Data/Library/Mail Downloads/1A2B/invoice.pdf", size: 64)

        let items = JunkScanner(home: temp.url).scan(.mailDownloads)
        #expect(items.map(\.name) == ["1A2B"])
        #expect(!JunkKind.mailDownloads.selectedByDefault, "Attachments are personal, so they are opt-in")
    }

    @Test func recentDownloadsAndInstallersAreNotOld() throws {
        let temp = try TempFolder()
        try temp.file("Downloads/new.pdf")
        try temp.file("Downloads/setup.dmg")

        // A file that just arrived is recent no matter what its other dates say.
        let items = JunkScanner(downloadsMaxAgeDays: 30, home: temp.url).scan(.oldDownloads)
        #expect(items.isEmpty)
    }
}

@Suite struct RunningAppMatcherTests {
    private let matcher = RunningAppMatcher(apps: [
        .init(bundleID: "com.google.android.studio", name: "Android Studio", isUserApp: true),
        .init(bundleID: "com.google.Chrome", name: "Google Chrome", isUserApp: true),
    ])

    @Test func matchesAnAppInsideAVendorFolder() {
        let item = CleanItem(url: URL(filePath: "/tmp/Google/AndroidStudio2026.1"), size: 1, title: "Google/AndroidStudio2026.1")
        #expect(matcher.owner(of: item, kind: .userCache)?.name == "Android Studio")
    }

    @Test func locksOnlyTheBrowserThatIsOpen() {
        let chrome = CleanItem(url: URL.homeDirectory.appending(path: "Library/Caches/Google/Chrome/Default/Cache/Cache_Data"), size: 1)
        let firefox = CleanItem(url: URL.homeDirectory.appending(path: "Library/Caches/Firefox/Profiles/p/cache2/entries"), size: 1)
        #expect(matcher.owner(of: chrome, kind: .browsers)?.name == "Google Chrome")
        #expect(matcher.owner(of: firefox, kind: .browsers) == nil)
    }
}

@Suite struct DuplicateScannerTests {
    @Test func findsTrueCopiesButNotLinks() throws {
        let temp = try TempFolder()
        let content = Data((0..<200_000).map { UInt8($0 % 251) })
        let original = try temp.file("Documents/photo.raw", contents: content)
        try temp.file("Desktop/photo copy.raw", contents: content)
        try FileManager.default.linkItem(at: original, to: temp.url.appending(path: "Documents/hardlink.raw"))
        try FileManager.default.createSymbolicLink(at: temp.url.appending(path: "Documents/symlink.raw"), withDestinationURL: original)
        var different = content
        different[199_999] ^= 0xFF
        try temp.file("Documents/almost.raw", contents: different)
        try temp.file("Projects/app/node_modules/photo.raw", contents: content)

        let groups = DuplicateScanner().scan(minSize: 1, root: temp.url) { _ in }

        #expect(groups.count == 1)
        let names = Set(try #require(groups.first).files.map(\.name))
        #expect(names.count == 2, "A hard link is the same file, and a symlink isn't a copy")
        #expect(names.contains("photo copy.raw"))
        #expect(!names.contains("almost.raw"), "One different byte means it isn't a duplicate")
    }
}

@Suite struct StartupScannerTests {
    @Test func readsDisabledLabels() {
        let output = """
        disabled services = {
            "com.example.off" => disabled
            "com.example.on" => enabled
            "com.example.legacy" => true
        }
        """
        #expect(StartupScanner.parseDisabled(output) == ["com.example.off", "com.example.legacy"])
    }

    @Test func flagsAgentsWhoseProgramOrAppIsGone() throws {
        let temp = try TempFolder()
        let missingProgram: NSDictionary = ["Label": "com.gone.agent", "ProgramArguments": ["/nonexistent/bin/agent"], "RunAtLoad": true]
        let missingApp: NSDictionary = ["Label": "com.vendor.helper", "Program": "/bin/sh", "AssociatedBundleIdentifiers": ["com.vendor.App"]]
        let healthy: NSDictionary = ["Label": "com.ok.agent", "Program": "/bin/sh", "KeepAlive": true]
        for (name, plist) in [("a", missingProgram), ("b", missingApp), ("c", healthy)] {
            try plist.write(to: temp.url.appending(path: "\(name).plist"))
        }

        let items = StartupScanner.launchdItems(in: temp.url, kind: .userAgent, disabled: ["com.ok.agent"])
        let byLabel = Dictionary(uniqueKeysWithValues: items.map { ($0.label, $0) })
        #expect(byLabel["com.gone.agent"]?.isOrphan == true)
        #expect(byLabel["com.vendor.helper"]?.isOrphan == true)
        #expect(byLabel["com.ok.agent"]?.isOrphan == false)
        #expect(byLabel["com.ok.agent"]?.isDisabled == true)
        #expect(byLabel["com.ok.agent"]?.keepsAlive == true)
    }
}

@Suite struct TreemapTests {
    @Test func tilesFillTheBoundsInProportion() {
        let bounds = CGRect(x: 0, y: 0, width: 400, height: 300)
        let values: [Double] = [50, 25, 15, 10]
        let rects = Treemap.layout(values, in: bounds)

        #expect(rects.count == values.count)
        let total = rects.reduce(0) { $0 + $1.width * $1.height }
        #expect(abs(total - bounds.width * bounds.height) < 0.5)
        for (value, rect) in zip(values, rects) {
            #expect(abs(rect.width * rect.height - bounds.width * bounds.height * value / 100) < 0.5)
            #expect(bounds.insetBy(dx: -0.01, dy: -0.01).contains(rect))
        }
    }
}
