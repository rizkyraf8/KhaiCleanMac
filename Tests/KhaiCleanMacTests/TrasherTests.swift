import Foundation
import Testing
@testable import KhaiCleanMac

/// The fake Trash: moves whatever is "trashed" into a folder the test can inspect, renaming
/// on a clash the way the real Trash does.
private func fakeTrash(into bin: URL) -> Trasher.TrashAction {
    { url in
        var target = bin.appending(path: url.lastPathComponent)
        var copy = 2
        while FileManager.default.fileExists(atPath: target.path) {
            target = bin.appending(path: "\(url.lastPathComponent) \(copy)")
            copy += 1
        }
        try FileManager.default.moveItem(at: url, to: target)
    }
}

@Suite struct TrasherTests {
    @Test func trashesAWholeItem() throws {
        let temp = try TempFolder()
        let bin = try temp.folder("bin")
        let file = try temp.file("cache/thing.dat", size: 100)

        let report = Trasher.remove([CleanItem(url: file, size: 100)], permanently: false,
                                    stagingRoot: temp.url.appending(path: "staging"), trash: fakeTrash(into: bin))

        #expect(report.movedCount == 1)
        #expect(report.movedSize == 100)
        #expect(!temp.exists("cache/thing.dat"))
        #expect(temp.exists("bin/thing.dat"))
    }

    @Test func gathersMembersIntoOneFolderAndKeepsTheRest() throws {
        let temp = try TempFolder()
        let bin = try temp.folder("bin")
        let base = try temp.folder("Cache_Data")
        let old1 = try temp.file("Cache_Data/aaaaaaaaaaaaaaaa_0")
        let old2 = try temp.file("Cache_Data/sub/bbbbbbbbbbbbbbbb_0")
        try temp.file("Cache_Data/index")

        let item = CleanItem(url: base, size: 32, title: "Old web cache", members: [old1, old2])
        let report = Trasher.remove([item], permanently: false,
                                    stagingRoot: temp.url.appending(path: "staging"), trash: fakeTrash(into: bin))

        #expect(report.movedCount == 1)
        #expect(!temp.exists("Cache_Data/aaaaaaaaaaaaaaaa_0"))
        #expect(!temp.exists("Cache_Data/sub/bbbbbbbbbbbbbbbb_0"))
        #expect(temp.exists("Cache_Data/index"), "Files that aren't members must stay")

        // One dated folder reached the Trash, with paths relative to the item's folder.
        let trashed = try FileManager.default.contentsOfDirectory(atPath: bin.path)
        #expect(trashed.count == 1)
        let folder = bin.appending(path: trashed[0])
        #expect(trashed[0].hasPrefix("Old web cache "))
        #expect(FileManager.default.fileExists(atPath: folder.appending(path: "aaaaaaaaaaaaaaaa_0").path))
        #expect(FileManager.default.fileExists(atPath: folder.appending(path: "sub/bbbbbbbbbbbbbbbb_0").path))
    }

    @Test func putsMembersBackWhenTheTrashRefuses() throws {
        let temp = try TempFolder()
        let base = try temp.folder("Cache_Data")
        let entry = try temp.file("Cache_Data/aaaaaaaaaaaaaaaa_0")
        let staging = temp.url.appending(path: "staging")

        struct Refused: Error {}
        let report = Trasher.remove([CleanItem(url: base, size: 16, members: [entry])], permanently: false,
                                    stagingRoot: staging, trash: { _ in throw Refused() })

        #expect(report.movedCount == 0)
        #expect(report.failed.count == 1)
        #expect(temp.exists("Cache_Data/aaaaaaaaaaaaaaaa_0"), "The file must be back where it was")
        let leftovers = (try? FileManager.default.contentsOfDirectory(atPath: staging.path)) ?? []
        #expect(leftovers.isEmpty, "No staging folder may be left behind")
    }

    @Test func permanentModeSkipsTheTrash() throws {
        let temp = try TempFolder()
        let bin = try temp.folder("bin")
        let file = try temp.file("logs/old.log")
        let base = try temp.folder("cache")
        let member = try temp.file("cache/aaaaaaaaaaaaaaaa_0")

        let report = Trasher.remove([CleanItem(url: file, size: 16), CleanItem(url: base, size: 16, members: [member])],
                                    permanently: true, stagingRoot: temp.url.appending(path: "staging"), trash: fakeTrash(into: bin))

        #expect(report.permanent)
        #expect(report.movedCount == 2)
        #expect(!temp.exists("logs/old.log"))
        #expect(!temp.exists("cache/aaaaaaaaaaaaaaaa_0"))
        #expect(temp.exists("cache"), "Only members go, never the folder that holds them")
        #expect(try FileManager.default.contentsOfDirectory(atPath: bin.path).isEmpty)
    }

    @Test func itemsAlreadyInTheTrashAreAlwaysDeleted() throws {
        let temp = try TempFolder()
        let bin = try temp.folder("bin")
        let trashed = try temp.file(".Trash/old.zip")

        let report = Trasher.remove([CleanItem(url: trashed, size: 16, removesPermanently: true)], permanently: false,
                                    stagingRoot: temp.url.appending(path: "staging"), trash: fakeTrash(into: bin))

        #expect(report.movedCount == 1)
        #expect(!temp.exists(".Trash/old.zip"))
        #expect(try FileManager.default.contentsOfDirectory(atPath: bin.path).isEmpty)
    }

    @Test func twoItemsWithTheSameNameDoNotShareAStagingFolder() throws {
        let temp = try TempFolder()
        let bin = try temp.folder("bin")
        let first = try temp.folder("a")
        let second = try temp.folder("b")
        let one = try temp.file("a/aaaaaaaaaaaaaaaa_0")
        let two = try temp.file("b/aaaaaaaaaaaaaaaa_0")

        let report = Trasher.remove([
            CleanItem(url: first, size: 16, title: "Same", members: [one]),
            CleanItem(url: second, size: 16, title: "Same", members: [two]),
        ], permanently: false, stagingRoot: temp.url.appending(path: "staging"), trash: fakeTrash(into: bin))

        #expect(report.movedCount == 2)
        #expect(try FileManager.default.contentsOfDirectory(atPath: bin.path).count == 2)
    }
}
