import Foundation
import Testing
@testable import KhaiCleanMac

/// Regression tests for docs/CODE_REVIEW.md (29 October 2026).
@Suite struct CodeReviewTests {
    /// Issue 1: an item SafetyGuard refuses stays in place, so screens must not treat it as removed.
    @Test func refusedItemsCountAsUnremoved() throws {
        let temp = try TempFolder()
        let home = try temp.folder("home")
        let documents = try temp.folder("home/Documents")
        let junk = try temp.file("home/Library/Caches/old.bin")

        let report = Trasher.remove([CleanItem(url: documents, size: 1), CleanItem(url: junk, size: 16)],
                                    permanently: true, stagingRoot: temp.url.appending(path: "staging"), home: home)

        #expect(report.failed.isEmpty)
        #expect(report.blocked.map(\.url) == [documents])
        #expect(report.unremoved.map(\.url) == [documents], "Refused items are reported with the failed ones")
        #expect(!report.isComplete)
        #expect(temp.exists("home/Documents"))
        #expect(!temp.exists("home/Library/Caches/old.bin"))
    }

    @Test func aCleanRunIsComplete() {
        #expect(CleanReport().isComplete)
        #expect(CleanReport(failed: [CleanItem(url: URL(filePath: "/tmp/x"), size: 1)]).isComplete == false)
    }

    /// Issue 2: a login item whose path System Events can't read is listed as an orphan, not dropped.
    @Test func aLoginItemWithoutAPathIsAnOrphan() {
        let items = StartupScanner.parseLoginItems("Gone App\t\nFinder\t/System/Library/CoreServices/Finder.app\n")
        #expect(items.map(\.name) == ["Gone App", "Finder"])
        #expect(items[0].isOrphan)
        #expect(items[0].programPath == nil)
        #expect(!items[1].isOrphan)
    }

    /// Issue 5: members spelled through a symlink (/private/var for /var) keep their subfolders,
    /// so two files with the same name don't collide in staging.
    @Test func membersKeepTheirSubfoldersWhateverTheSpelling() throws {
        let temp = try TempFolder()
        let bin = try temp.folder("bin")
        let base = try temp.folder("Cache")
        let first = try temp.file("Cache/subA/cache.db")
        let second = try temp.file("Cache/subB/cache.db")
        // The temporary folder is under /var, which is a symlink to /private/var.
        let resolved = [first, second].map { $0.resolvingSymlinksInPath() }
        #expect(Trasher.relativePath(of: resolved[0], in: base) == "subA/cache.db")

        let report = Trasher.remove([CleanItem(url: base, size: 32, members: resolved)], permanently: false,
                                    stagingRoot: temp.url.appending(path: "staging")) { url in
            let target = bin.appending(path: url.lastPathComponent)
            try FileManager.default.moveItem(at: url, to: target)
            return target
        }
        #expect(report.isComplete)
        #expect(Set(report.removed.first?.memberPaths ?? []) == ["subA/cache.db", "subB/cache.db"])
        #expect(!temp.exists("Cache/subA/cache.db") && !temp.exists("Cache/subB/cache.db"))
    }
}
