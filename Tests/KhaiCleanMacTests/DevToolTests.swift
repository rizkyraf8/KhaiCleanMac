import Foundation
import Testing
@testable import KhaiCleanMac

@Suite struct DevToolTests {
    // MARK: Python

    @Test func venvNextToManifestIsPreselectedWhenStale() throws {
        let temp = try TempFolder()
        try temp.file("app/requirements.txt")
        try temp.file("app/.venv/pyvenv.cfg")
        try temp.file("app/.venv/lib/site.py", size: 4096, daysOld: 200)
        try temp.age(temp.url.appending(path: "app/.venv/pyvenv.cfg"), days: 200)
        let venv = temp.url.appending(path: "app/.venv")

        #expect(PythonEnvironments.isEnvironment(venv))
        let item = try #require(PythonEnvironments.projectItem(venv, cutoff: Date().addingTimeInterval(-90 * 86_400)))
        #expect(item.selectedByDefault)
        #expect(item.note == nil)
        #expect(item.title == "app")
    }

    @Test func venvWithoutManifestIsNeverPreselected() throws {
        let temp = try TempFolder()
        try temp.file("scratch/venv/pyvenv.cfg", daysOld: 400)
        try temp.file("scratch/venv/bin/python", size: 4096, daysOld: 400)
        let item = try #require(PythonEnvironments.projectItem(temp.url.appending(path: "scratch/venv"), cutoff: Date()))
        #expect(!item.selectedByDefault)
        #expect(item.note != nil)
    }

    @Test func folderWithoutMarkerIsNotAnEnvironment() throws {
        let temp = try TempFolder()
        try temp.file("site/env/settings.json")
        #expect(!PythonEnvironments.isEnvironment(temp.url.appending(path: "site/env")))
    }

    @Test func sharedEnvironmentsAreFoundButNotPreselected() throws {
        let temp = try TempFolder()
        try temp.file("Library/Caches/pypoetry/virtualenvs/app-x1y2-py3.12/pyvenv.cfg")
        try temp.file("miniconda3/envs/ml/conda-meta/history", size: 2048)
        try temp.file(".virtualenvs/notes.txt")
        let items = PythonEnvironments.sharedItems(home: temp.url)
        #expect(Set(items.map(\.title)) == ["app-x1y2-py3.12", "ml"])
        #expect(items.allSatisfy { !$0.selectedByDefault && $0.note != nil })
    }

    // MARK: Android

    @Test func emulatorsAndTheirSystemImages() throws {
        let temp = try TempFolder()
        let sdk = try temp.folder("sdk")
        try temp.file("sdk/system-images/android-34/google_apis/arm64-v8a/system.img", size: 8192)
        try temp.file("sdk/system-images/android-33/google_apis_playstore/arm64-v8a/system.img", size: 8192)
        try temp.folder("sdk/system-images/android-33/google_apis/arm64-v8a")
        let avd = temp.url.appending(path: ".android/avd/Pixel_7.avd").path
        try temp.file(".android/avd/Pixel_7.ini", contents: Data("avd.ini.encoding=UTF-8\npath=\(avd)\npath.rel=avd/Pixel_7.avd\n".utf8))
        try temp.file(".android/avd/Pixel_7.avd/config.ini",
                      contents: Data("avd.ini.displayname=Pixel 7\nimage.sysdir.1=system-images/android-34/google_apis/arm64-v8a/\n".utf8))
        try temp.file(".android/avd/Pixel_7.avd/userdata-qemu.img", size: 8192)

        let items = AndroidSDK.items(home: temp.url, sdk: sdk)
        let emulator = try #require(items.first { $0.title == "Pixel 7" })
        #expect(!emulator.selectedByDefault)
        #expect(emulator.companions.map(\.lastPathComponent) == ["Pixel_7.ini"])

        let used = try #require(items.first { $0.title == "API 34 · Google APIs · arm64-v8a" })
        #expect(!used.selectedByDefault)
        #expect(used.note != nil)
        let unused = try #require(items.first { $0.title == "API 33 · Google Play · arm64-v8a" })
        #expect(unused.selectedByDefault)
        // The empty image folder takes no space and isn't listed.
        #expect(items.count == 3)
    }

    @Test func emulatorOutsideTheAVDFolderIsIgnored() throws {
        let temp = try TempFolder()
        try temp.file("Documents/Work.avd/config.ini")
        try temp.file(".android/avd/Work.ini", contents: Data("path=\(temp.url.appending(path: "Documents/Work.avd").path)\n".utf8))
        #expect(AndroidSDK.emulators(home: temp.url).isEmpty)
    }

    @Test func runningEmulatorIsDetectedByItsLockFiles() throws {
        let temp = try TempFolder()
        let folder = try temp.folder("Pixel.avd")
        #expect(!AndroidSDK.isRunning(folder))
        try temp.file("Pixel.avd/hardware-qemu.ini.lock")
        #expect(AndroidSDK.isRunning(folder))
    }

    @Test func emulatorIniGoesWithItsFolder() {
        var item = DevItem(url: URL(filePath: "/Users/me/.android/avd/Pixel.avd"), size: 10, title: "Pixel", tool: "Android", lastUsed: nil)
        item.companions = [URL(filePath: "/Users/me/.android/avd/Pixel.ini")]
        let clean = DeveloperModel.cleanItem(for: item, cutoff: Date())
        #expect(clean?.url == item.url)
        #expect(clean?.members.isEmpty == true)
    }

    // MARK: Homebrew

    @Test func parsesDryRunCleanup() {
        let output = """
        Warning: Skipping aom: most recent version 3.15.3 not installed
        Would remove: /opt/homebrew/Cellar/python@3.11/3.11.5 (3,255 files, 63.4MB)
        Would remove: /Users/me/Library/Caches/Homebrew/node--21.1.0.arm64_sonoma.bottle.tar.gz (12.3MB)
        Would remove: /opt/homebrew/Library/Homebrew/vendor/portable-ruby/3.3.1 (2,382 files, 43.1MB)
        ==> This operation would free approximately 118.8MB of disk space.
        """
        let report = Homebrew.parseDryRun(output)
        #expect(report.removals.count == 3)
        #expect(report.oldVersions.map(\.path) == ["/opt/homebrew/Cellar/python@3.11/3.11.5"])
        #expect(report.downloads.count == 1)
        #expect(report.removals.first?.size == Int64(63.4 * 1024 * 1024))
        #expect(report.reclaimable == Int64(118.8 * 1024 * 1024))
    }

    @Test func sizesUsePowersOf1024() {
        #expect(Homebrew.bytes("512B") == 512)
        #expect(Homebrew.bytes("2KB") == 2048)
        #expect(Homebrew.bytes("1.5GB") == Int64(1.5 * 1_073_741_824))
        #expect(Homebrew.bytes("nothing") == nil)
    }

    @Test func parsesOutdatedAndBuildsTheUpgradeCommand() {
        let json = """
        {"formulae":[{"name":"cmake","installed_versions":["3.29.3"],"current_version":"4.4.5","pinned":false},
                     {"name":"node@20","installed_versions":["20.1"],"current_version":"20.9","pinned":true}],
         "casks":[{"name":"claude-code","installed_versions":["2.1.236"],"current_version":"2.1.309"}]}
        """
        let outdated = Homebrew.parseOutdated(Data(json.utf8))
        #expect(outdated.map(\.name) == ["claude-code", "cmake", "node@20"])
        #expect(outdated.first { $0.name == "cmake" }?.installed == "3.29.3")
        // Pinned formulae stay out of the upgrade.
        #expect(Homebrew.upgradeCommand(outdated) == "brew upgrade --formula cmake && brew upgrade --cask claude-code")
    }

    @Test func brewHistoryIsPermanentAndListsEveryRemoval() {
        let report = BrewReport(removals: [.init(path: "/opt/homebrew/Cellar/a/1", size: 10), .init(path: "/opt/homebrew/Cellar/b/2", size: 5)],
                                reclaimable: 15)
        let history = DeveloperModel.brewHistory(report)
        #expect(history.permanent)
        #expect(history.movedSize == 15)
        #expect(history.removed.allSatisfy { $0.trashedPath == nil })
    }
}

@Suite struct EmulatorCompanionTests {
    @Test func iniOnlyFollowsAFolderThatWent() {
        var gone = DevItem(url: URL(filePath: "/Users/me/.android/avd/A.avd"), size: 1, title: "A", tool: "Android", lastUsed: nil)
        gone.companions = [URL(filePath: "/Users/me/.android/avd/A.ini")]
        var stayed = DevItem(url: URL(filePath: "/Users/me/.android/avd/B.avd"), size: 1, title: "B", tool: "Android", lastUsed: nil)
        stayed.companions = [URL(filePath: "/Users/me/.android/avd/B.ini")]
        let companions = DeveloperModel.companions(of: [gone, stayed], unremoved: [stayed.url])
        #expect(companions.map(\.url.lastPathComponent) == ["A.ini"])
    }
}
