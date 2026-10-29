import Foundation
import Testing
@testable import KhaiCleanMac

@Suite struct AppVersionTests {
    @Test func parsesTagsAndPlainVersions() throws {
        #expect(try #require(AppVersion("v0.4.0")).numbers == [0, 4, 0])
        #expect(try #require(AppVersion("0.4")).numbers == [0, 4])
        #expect(try #require(AppVersion("V1.2.3-beta.1")).numbers == [1, 2, 3])
        #expect(AppVersion("dev") == nil)
        #expect(AppVersion("") == nil)
        #expect(AppVersion("1.x") == nil)
    }

    @Test func comparesNumberByNumber() throws {
        let v = { (text: String) in try #require(AppVersion(text)) }
        #expect(try v("0.4.0") < v("0.5.0"))
        #expect(try v("0.9.0") < v("0.10.0"), "10 is more than 9, not less as text")
        #expect(try v("0.4") == v("0.4.0"), "A missing part counts as zero")
        #expect(try !(v("1.0.0") < v("0.9.9")))
    }
}

@Suite struct UpdateAPITests {
    /// The shape rizkyraf.id returns today.
    private let sample = Data("""
    {"project":{"slug":"khaicleanmac","title":"KhaiCleanMac","url":"https:\\/\\/rizkyraf.id\\/projects\\/khaicleanmac"},
     "latest":{"version":"v0.4.0","title":"KhaiCleanMac","notes":null,"file_name":"KhaiCleanMac-0.4.0.dmg",
               "size":2307136,"sha256":null,"download_url":"https:\\/\\/rizkyraf.id\\/d\\/khaicleanmac-0340",
               "released_at":"2026-10-28T15:50:50+00:00"}}
    """.utf8)

    @Test func readsTheLatestRelease() throws {
        let release = try UpdateAPI.decode(sample)
        #expect(release.version == AppVersion("0.4.0"))
        #expect(release.fileName == "KhaiCleanMac-0.4.0.dmg")
        #expect(release.size == 2_307_136)
        #expect(release.downloadURL?.absoluteString == "https://rizkyraf.id/d/khaicleanmac-0340")
        #expect(release.pageURL?.absoluteString == "https://rizkyraf.id/projects/khaicleanmac")
        #expect(release.notes == nil)
        #expect(release.sha256 == nil, "No checksum yet: the button opens the browser download")
        let released = try #require(release.releasedAt)
        #expect(abs(released.timeIntervalSince1970 - 1_793_202_650) < 1)
    }

    @Test func blankNotesCountAsNone() throws {
        let json = Data(#"{"latest":{"version":"0.5.0","notes":"   "}}"#.utf8)
        let release = try UpdateAPI.decode(json)
        #expect(release.notes == nil)
        #expect(release.downloadURL == nil, "Missing fields are fine; the project page is the fallback")
    }

    @Test func rejectsAnUnreadableVersion() {
        let json = Data(#"{"latest":{"version":"latest"}}"#.utf8)
        #expect(throws: UpdateAPI.Failure.self) { try UpdateAPI.decode(json) }
    }
}
