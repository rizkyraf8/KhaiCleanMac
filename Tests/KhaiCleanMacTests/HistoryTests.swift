import Foundation
import Testing
@testable import KhaiCleanMac

@Suite struct HistoryTests {
    private func fakeTrash(_ bin: URL) -> Trasher.TrashAction {
        { url in
            let target = bin.appending(path: url.lastPathComponent)
            try FileManager.default.moveItem(at: url, to: target)
            return target
        }
    }

    @Test func aTrashedItemCanBePutBack() throws {
        let temp = try TempFolder()
        let bin = try temp.folder("home/.Trash")
        let file = try temp.file("home/Library/Caches/com.example.App/blob", size: 32)
        let folder = file.deletingLastPathComponent()

        let report = Trasher.remove([CleanItem(url: folder, size: 32)], permanently: false,
                                    stagingRoot: temp.url.appending(path: "staging"), home: temp.url.appending(path: "home"),
                                    trash: fakeTrash(bin))
        let removed = try #require(report.removed.first)
        #expect(removed.trashedPath == bin.appending(path: "com.example.App").path)
        #expect(!temp.exists("home/Library/Caches/com.example.App"))

        #expect(Restorer.restore(removed) == .restored)
        #expect(temp.exists("home/Library/Caches/com.example.App/blob"))
    }

    @Test func manyFileItemsGoBackFileByFile() throws {
        let temp = try TempFolder()
        let bin = try temp.folder("home/.Trash")
        let base = try temp.folder("home/Library/Caches/Google/Chrome/Default/Cache/Cache_Data")
        let one = try temp.file("home/Library/Caches/Google/Chrome/Default/Cache/Cache_Data/aaaaaaaaaaaaaaaa_0")
        let two = try temp.file("home/Library/Caches/Google/Chrome/Default/Cache/Cache_Data/bbbbbbbbbbbbbbbb_0")
        try temp.file("home/Library/Caches/Google/Chrome/Default/Cache/Cache_Data/index")

        let report = Trasher.remove([CleanItem(url: base, size: 32, title: "Old web cache", members: [one, two])],
                                    permanently: false, stagingRoot: temp.url.appending(path: "staging"),
                                    home: temp.url.appending(path: "home"), trash: fakeTrash(bin))
        let removed = try #require(report.removed.first)
        #expect(Set(removed.memberPaths) == ["aaaaaaaaaaaaaaaa_0", "bbbbbbbbbbbbbbbb_0"])

        #expect(Restorer.restore(removed) == .restored)
        #expect(FileManager.default.fileExists(atPath: one.path))
        #expect(FileManager.default.fileExists(atPath: two.path))
        #expect(!FileManager.default.fileExists(atPath: try #require(removed.trashedPath)), "The emptied Trash folder is tidied")
    }

    @Test func neverOverwritesSomethingNewAtTheOriginalPlace() throws {
        let temp = try TempFolder()
        let bin = try temp.folder("home/.Trash")
        let file = try temp.file("home/Downloads/report.pdf", contents: Data("old".utf8))

        let report = Trasher.remove([CleanItem(url: file, size: 3)], permanently: false,
                                    stagingRoot: temp.url.appending(path: "staging"), home: temp.url.appending(path: "home"),
                                    trash: fakeTrash(bin))
        try temp.file("home/Downloads/report.pdf", contents: Data("new".utf8))

        #expect(Restorer.restore(try #require(report.removed.first)) == .conflict)
        #expect(try String(contentsOf: file, encoding: .utf8) == "new")
    }

    @Test func permanentRemovalsAreRecordedButNotRestorable() throws {
        let temp = try TempFolder()
        let file = try temp.file("home/Library/Logs/old.log")

        let report = Trasher.remove([CleanItem(url: file, size: 16)], permanently: true,
                                    stagingRoot: temp.url.appending(path: "staging"), home: temp.url.appending(path: "home"))
        let removed = try #require(report.removed.first)
        #expect(removed.trashedPath == nil)
        #expect(!removed.canRestore)
    }

    @MainActor @Test func historyIsSavedAndReloaded() throws {
        let temp = try TempFolder()
        let store = temp.url.appending(path: "history.json")
        let history = CleanHistory(fileURL: store)
        var report = CleanReport()
        report.removed = [RemovedItem(CleanItem(url: URL(filePath: "/tmp/x"), size: 10), trashedTo: nil, memberPaths: [])]
        history.record(report, source: "Smart Scan")

        let reloaded = CleanHistory(fileURL: store)
        #expect(reloaded.records.count == 1)
        #expect(reloaded.records.first?.source == "Smart Scan")
        #expect(reloaded.records.first?.totalSize == 10)
    }
}
