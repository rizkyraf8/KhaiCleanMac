import Foundation
import Testing
@testable import KhaiCleanMac

@Suite struct VersionComparatorTests {
    @Test(arguments: [
        ("1.10", "1.9"), ("2.0", "2.0b3"), ("1.0.1", "1.0"), ("1.0.1", "1.0b1"), ("10", "9"),
        ("3.2.0", "3.1.12"), ("1.0", "1.0rc1"), ("2024.10.2", "2024.9.30"), ("1.0b2", "1.0b1"),
    ])
    func newerComesFirst(newer: String, older: String) {
        #expect(VersionComparator.compare(newer, older) == .orderedDescending)
        #expect(VersionComparator.compare(older, newer) == .orderedAscending)
    }

    @Test func sameVersionsAreEqual() {
        #expect(VersionComparator.compare("1.2.3", "1.2.3") == .orderedSame)
        #expect(VersionComparator.compare("456", "456") == .orderedSame)
    }
}

@Suite struct AppcastTests {
    private let modernFeed = """
    <?xml version="1.0" encoding="utf-8"?>
    <rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
      <channel>
        <item>
          <title>2.1</title>
          <pubDate>Tue, 14 Oct 2026 10:00:00 +0000</pubDate>
          <sparkle:version>210</sparkle:version>
          <sparkle:shortVersionString>2.1</sparkle:shortVersionString>
          <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>
          <sparkle:releaseNotesLink>https://example.com/notes/2.1</sparkle:releaseNotesLink>
          <enclosure url="https://example.com/App-2.1.zip" length="1" type="application/octet-stream"/>
        </item>
        <item>
          <title>2.2 beta</title>
          <sparkle:version>220</sparkle:version>
          <sparkle:shortVersionString>2.2b1</sparkle:shortVersionString>
          <sparkle:channel>beta</sparkle:channel>
          <enclosure url="https://example.com/App-2.2b1.zip" length="1"/>
        </item>
        <item>
          <title>3.0</title>
          <sparkle:version>300</sparkle:version>
          <sparkle:minimumSystemVersion>99.0</sparkle:minimumSystemVersion>
          <enclosure url="https://example.com/App-3.0.zip" length="1"/>
        </item>
        <item>
          <title>2.0</title>
          <sparkle:version>200</sparkle:version>
          <enclosure url="https://example.com/App-2.0.zip" length="1"/>
        </item>
      </channel>
    </rss>
    """

    @Test func picksTheNewestReleaseThisMacCanInstall() throws {
        let release = try #require(AppcastParser.newestRelease(in: Data(modernFeed.utf8)))
        #expect(release.version == "210", "Betas and releases needing a newer macOS are skipped")
        #expect(release.displayVersion == "2.1")
        #expect(release.releaseNotes?.absoluteString == "https://example.com/notes/2.1")
        #expect(release.date != nil)
    }

    @Test func readsVersionsFromTheEnclosureInOlderFeeds() throws {
        let feed = """
        <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel>
          <item><title>1.4</title><link>http://insecure.example.com/notes</link>
            <enclosure url="https://example.com/a.dmg" sparkle:version="1.4" sparkle:shortVersionString="1.4"/></item>
          <item><title>Windows</title>
            <enclosure url="https://example.com/a.exe" sparkle:version="9.9" sparkle:os="windows"/></item>
        </channel></rss>
        """
        let release = try #require(AppcastParser.newestRelease(in: Data(feed.utf8)))
        #expect(release.version == "1.4", "Items for other platforms are skipped")
        #expect(release.releaseNotes == nil, "Only https links are offered")
    }

    @Test func garbageIsNotARelease() {
        #expect(AppcastParser.newestRelease(in: Data("<html><body>Not found</body></html>".utf8)) == nil)
    }

    private func app(short: String?, build: String?) -> UpdatableApp {
        UpdatableApp(app: InstalledApp(url: URL(filePath: "/Applications/Example.app"), name: "Example", bundleID: "com.example.app",
                                       version: short, searchNames: []),
                     bundleVersion: build, source: .sparkle(feed: URL(string: "https://example.com/appcast.xml")!))
    }

    @Test func reportsOnlyRealUpdates() {
        let release = AppcastRelease(version: "210", shortVersion: "2.1", releaseNotes: nil, date: nil)
        #expect(AppUpdateScanner.update(for: app(short: "2.0", build: "200"), release: release) != nil)
        #expect(AppUpdateScanner.update(for: app(short: "2.1", build: "210"), release: release) == nil)
        #expect(AppUpdateScanner.update(for: app(short: "2.2", build: "220"), release: release) == nil)
    }

    @Test func doesNotMistakeABuildNumberForAnUpdate() {
        // The feed uses build numbers, the app's CFBundleVersion is the marketing version.
        let release = AppcastRelease(version: "5012", shortVersion: "1.2.3", releaseNotes: nil, date: nil)
        #expect(AppUpdateScanner.update(for: app(short: "1.2.3", build: "1.2.3"), release: release) == nil)
        // Same marketing version but a newer build written the same way is a real update.
        let rebuilt = AppcastRelease(version: "5013", shortVersion: "1.2.3", releaseNotes: nil, date: nil)
        #expect(AppUpdateScanner.update(for: app(short: "1.2.3", build: "5012"), release: rebuilt) != nil)
    }

    @Test func onlyWebFeedsCount() throws {
        let temp = try TempFolder()
        let appURL = try temp.folder("Example.app")
        #expect(AppUpdateScanner.source(of: appURL, info: ["SUFeedURL": "https://example.com/appcast.xml"])
                == .sparkle(feed: URL(string: "https://example.com/appcast.xml")!))
        #expect(AppUpdateScanner.source(of: appURL, info: ["SUFeedURL": "file:///etc/passwd"]) == .unknown)
        #expect(AppUpdateScanner.source(of: appURL, info: [:]) == .unknown)
        try temp.file("Example.app/Contents/_MASReceipt/receipt")
        #expect(AppUpdateScanner.source(of: appURL, info: ["SUFeedURL": "https://example.com/appcast.xml"]) == .appStore)
    }
}
