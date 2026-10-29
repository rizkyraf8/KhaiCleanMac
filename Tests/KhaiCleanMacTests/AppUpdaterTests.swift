import Foundation
import Testing
@testable import KhaiCleanMac

@Suite struct AppUpdaterTests {
    @Test func checksumIsTheLowercaseHexOfTheFile() throws {
        let temp = try TempFolder()
        let file = try temp.file("update.dmg", contents: Data("abc".utf8))
        #expect(try AppUpdater.sha256(of: file) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    @Test func onlyWellFormedChecksumsAreKept() throws {
        let hex = String(repeating: "aB", count: 32)
        #expect(UpdateAPI.checksum(hex) == hex.lowercased())
        #expect(UpdateAPI.checksum(" \(hex) ") == hex.lowercased())
        #expect(UpdateAPI.checksum("abc") == nil)
        #expect(UpdateAPI.checksum(String(repeating: "z", count: 64)) == nil)
        #expect(UpdateAPI.checksum(nil) == nil)

        let json = Data(#"{"latest":{"version":"0.5.0","download_url":"https://rizkyraf.id/d/x","sha256":"\#(hex)"}}"#.utf8)
        #expect(try UpdateAPI.decode(json).sha256 == hex.lowercased())
    }

    @Test func withoutAChecksumTheBrowserDownloadIsUsed() throws {
        let temp = try TempFolder()
        let app = try temp.folder("Applications/KhaiCleanMac.app")
        let release = { (sha: String?) in
            LatestRelease(version: AppVersion("0.5.0")!, notes: nil, fileName: nil, size: nil,
                          downloadURL: URL(string: "https://rizkyraf.id/d/x"), releasedAt: nil, sha256: sha)
        }
        #expect(!AppUpdater.canInstall(release(nil), app: app))
        #expect(AppUpdater.canInstall(release(String(repeating: "a", count: 64)), app: app))
        #expect(!AppUpdater.canInstall(release(String(repeating: "a", count: 64)), app: URL(filePath: "/usr/bin/swift")),
                "A bare executable (like `swift run`) can't be swapped")
    }

    // MARK: Disk images

    /// A minimal, ad-hoc signed app bundle inside a fresh DMG.
    private func makeDMG(in temp: TempFolder, bundleID: String = AppInfo.bundleID, version: String,
                         tamper: Bool = false) throws -> URL {
        let source = try temp.folder("dmg-\(UUID().uuidString)")
        let contents = try temp.folder(source.lastPathComponent + "/KhaiCleanMac.app/Contents")
        let plist: [String: Any] = [
            "CFBundleIdentifier": bundleID, "CFBundleShortVersionString": version, "CFBundleVersion": "1",
            "CFBundleExecutable": "KhaiCleanMac", "CFBundlePackageType": "APPL",
        ]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: contents.appending(path: "Info.plist"))
        try FileManager.default.createDirectory(at: contents.appending(path: "MacOS"), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: URL(filePath: "/usr/bin/true"), to: contents.appending(path: "MacOS/KhaiCleanMac"))
        try FileManager.default.createDirectory(at: contents.appending(path: "Resources"), withIntermediateDirectories: true)
        try Data("v1".utf8).write(to: contents.appending(path: "Resources/notes.txt"))
        let app = contents.deletingLastPathComponent()
        try #require(StartupScanner.run("/usr/bin/codesign", ["--force", "--deep", "--sign", "-", app.path]) != nil)
        if tamper { try Data("changed after signing".utf8).write(to: contents.appending(path: "Resources/notes.txt")) }

        let dmg = temp.url.appending(path: "\(UUID().uuidString).dmg")
        try #require(StartupScanner.run("/usr/bin/hdiutil", ["create", "-quiet", "-fs", "HFS+", "-srcfolder", source.path,
                                                             "-format", "UDZO", dmg.path]) != nil)
        return dmg
    }

    private func stage(_ dmg: URL, expecting version: String, in temp: TempFolder) throws -> URL {
        let installed = try temp.folder("Applications/KhaiCleanMac.app")
        return try AppUpdater.stage(dmg: dmg, expectedVersion: AppVersion(version)!, nextTo: installed)
    }

    @Test func aGenuineUpdateIsStagedNextToTheInstalledApp() throws {
        let temp = try TempFolder()
        let staged = try stage(makeDMG(in: temp, version: "9.9.0"), expecting: "9.9.0", in: temp)
        #expect(staged.deletingLastPathComponent().path == temp.url.appending(path: "Applications").path)
        #expect(Bundle(url: staged)?.bundleIdentifier == AppInfo.bundleID)
        #expect(temp.exists("Applications/KhaiCleanMac.app"), "The installed app is left alone until the swap")
    }

    @Test func refusesAnotherVersionThanAnnounced() throws {
        let temp = try TempFolder()
        let dmg = try makeDMG(in: temp, version: "9.9.0")
        #expect(throws: AppUpdater.Failure.wrongVersion) { try stage(dmg, expecting: "9.9.1", in: temp) }
    }

    @Test func refusesAnotherApp() throws {
        let temp = try TempFolder()
        let dmg = try makeDMG(in: temp, bundleID: "com.example.Other", version: "9.9.0")
        #expect(throws: AppUpdater.Failure.wrongApp) { try stage(dmg, expecting: "9.9.0", in: temp) }
    }

    @Test func refusesAnAppChangedAfterSigning() throws {
        let temp = try TempFolder()
        let dmg = try makeDMG(in: temp, version: "9.9.0", tamper: true)
        #expect(throws: AppUpdater.Failure.badSignature) { try stage(dmg, expecting: "9.9.0", in: temp) }
        #expect(!temp.exists("Applications/.KhaiCleanMac-update.app"))
    }
}
