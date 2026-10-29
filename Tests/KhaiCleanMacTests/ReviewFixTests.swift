import Foundation
import Testing
@testable import KhaiCleanMac

/// Regression tests for the source review in GitHub issues #2–#5 (29 October 2026),
/// built from the fixture scenarios in those reports.

/// #3: when the Trash refuses a staging folder, files that can't go back must survive.
@Suite struct TrashRollbackTests {
    @Test func aFileThatCantGoBackStaysInStaging() throws {
        let temp = try TempFolder()
        let base = try temp.folder("Cache_Data")
        let entry = try temp.file("Cache_Data/aaaaaaaaaaaaaaaa_0", contents: Data("original".utf8))
        let staging = temp.url.appending(path: "staging")

        struct Refused: Error {}
        // Something recreates the original path, then the Trash refuses the staged folder.
        let report = Trasher.remove([CleanItem(url: base, size: 8, members: [entry])], permanently: false, stagingRoot: staging) { _ in
            try Data("replacement".utf8).write(to: entry)
            throw Refused()
        }

        #expect(report.failed.count == 1)
        #expect(try Data(contentsOf: entry) == Data("replacement".utf8), "The new file is left alone")
        let kept = try #require(report.keptInStaging.first, "The staging folder must be kept and reported")
        #expect(try Data(contentsOf: kept.appending(path: "aaaaaaaaaaaaaaaa_0")) == Data("original".utf8),
                "The original bytes must survive")
    }

    @Test func aFullRollbackStillLeavesNoStagingBehind() throws {
        let temp = try TempFolder()
        let base = try temp.folder("Cache_Data")
        let entry = try temp.file("Cache_Data/aaaaaaaaaaaaaaaa_0")
        let staging = temp.url.appending(path: "staging")

        struct Refused: Error {}
        let report = Trasher.remove([CleanItem(url: base, size: 16, members: [entry])], permanently: false,
                                    stagingRoot: staging, trash: { _ -> URL? in throw Refused() })

        #expect(report.keptInStaging.isEmpty)
        #expect(((try? FileManager.default.contentsOfDirectory(atPath: staging.path)) ?? []).isEmpty)
    }
}

/// #2: an entry-only cache must never turn into a whole-folder removal.
@Suite struct EntryOnlyCacheTests {
    private func gradleItem(_ temp: TempFolder) throws -> DevItem {
        let root = try temp.folder(".gradle/caches")
        try temp.file(".gradle/caches/gradle.properties", contents: Data("token=secret".utf8))
        let entry = try temp.file(".gradle/caches/modules-2/old-lib.jar", size: 100)
        let old = Date().addingTimeInterval(-400 * 24 * 60 * 60)
        return DevItem(url: root, size: 100, title: "Gradle", tool: "~/.gradle", lastUsed: old,
                       entries: [CacheEntry(url: entry, size: 100, lastUsed: old)], isSmart: true)
    }

    @Test func onlyStaleEntriesAreHandedOver() throws {
        let temp = try TempFolder()
        let item = try gradleItem(temp)
        let clean = try #require(DeveloperModel.cleanItem(for: item, cutoff: Date()))
        #expect(clean.members.map(\.lastPathComponent) == ["old-lib.jar"])

        let report = Trasher.remove([clean], permanently: true, stagingRoot: temp.url.appending(path: "staging"))
        #expect(report.movedCount == 1)
        #expect(temp.exists(".gradle/caches/gradle.properties"), "Files outside the entries stay")
    }

    @Test func anExhaustedCacheOffersNothing() throws {
        let temp = try TempFolder()
        let item = try gradleItem(temp)
        let exhausted = item.removing(Set(item.entries.map(\.url)))

        #expect(exhausted.isSmart, "Still entry-only after its last entry is gone")
        #expect(exhausted.size == 0)
        // Any age limit, any number of cleanups: never the whole folder.
        #expect(DeveloperModel.cleanItem(for: exhausted, cutoff: Date()) == nil)
        #expect(DeveloperModel.cleanItem(for: exhausted, cutoff: .distantFuture) == nil)
        #expect(DeveloperModel.cleanItem(for: item, cutoff: .distantPast) == nil, "Nothing stale, nothing to do")
    }
}

/// #4: duplicates are checked again right before removal, and read errors fail closed.
@Suite struct DuplicateRevalidationTests {
    private func group(_ files: URL..., size: Int64) -> DuplicateGroup {
        DuplicateGroup(id: "g", size: size, files: files.map { DuplicateFile(url: $0, modified: nil) })
    }

    @Test func aStillMatchingCopyIsRemoved() throws {
        let temp = try TempFolder()
        let a = try temp.file("a.bin", contents: Data(repeating: 1, count: 2_048))
        let b = try temp.file("b.bin", contents: Data(repeating: 1, count: 2_048))
        let check = DuplicateScanner.verifiedRemovals(in: group(a, b, size: 2_048), selected: [b])
        #expect(check.remove.map(\.url) == [b])
    }

    @Test func theLastCopyIsKeptWhenTheOtherIsGone() throws {
        let temp = try TempFolder()
        let a = try temp.file("a.bin", contents: Data(repeating: 1, count: 2_048))
        let b = try temp.file("b.bin", contents: Data(repeating: 1, count: 2_048))
        try FileManager.default.removeItem(at: a)
        let check = DuplicateScanner.verifiedRemovals(in: group(a, b, size: 2_048), selected: [b])
        #expect(check.remove.isEmpty)
        #expect(check.skipped.map(\.url) == [b])
    }

    @Test func aChangedFileIsSkipped() throws {
        let temp = try TempFolder()
        let a = try temp.file("a.bin", contents: Data(repeating: 1, count: 2_048))
        let b = try temp.file("b.bin", contents: Data(repeating: 1, count: 2_048))
        try Data(repeating: 2, count: 2_048).write(to: b)
        #expect(DuplicateScanner.verifiedRemovals(in: group(a, b, size: 2_048), selected: [b]).remove.isEmpty,
                "Same size, different content: now unique")
    }

    @Test func aHardLinkToTheKeptCopyIsNotACopy() throws {
        let temp = try TempFolder()
        let a = try temp.file("a.bin", contents: Data(repeating: 1, count: 2_048))
        let b = temp.url.appending(path: "b.bin")
        try FileManager.default.linkItem(at: a, to: b)
        #expect(DuplicateScanner.verifiedRemovals(in: group(a, b, size: 2_048), selected: [b]).remove.isEmpty)
    }

    @Test func anUnreadableFileFailsClosed() throws {
        let temp = try TempFolder()
        let a = try temp.file("a.bin", contents: Data(repeating: 1, count: 2_048))
        let b = try temp.file("b.bin", contents: Data(repeating: 1, count: 2_048))
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: b.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: b.path) }
        #expect(DuplicateScanner.hash(b, limit: nil) == nil)
        #expect(DuplicateScanner.verifiedRemovals(in: group(a, b, size: 2_048), selected: [b]).remove.isEmpty)
    }
}

/// #5: look-alike IDs and shared containers are never preselected by the Uninstaller.
@Suite struct LeftoverOwnershipTests {
    private let uuid = "0A1B2C3D-4E5F-6071-8293-A4B5C6D7E8F9"

    private func app(_ temp: TempFolder) -> InstalledApp {
        InstalledApp(url: temp.url.appending(path: "Applications/Editor.app"), name: "Editor", bundleID: "com.vendor.editor",
                     version: nil, searchNames: ["Editor"])
    }

    @Test func aBetaWithALongerIDIsOnlyAGuess() throws {
        let temp = try TempFolder()
        let home = try temp.folder("home")
        for path in ["Group Containers/ABCDE12345.com.vendor.editor/db", "Group Containers/ABCDE12345.com.vendor.editor.beta/db",
                     "LaunchAgents/com.vendor.editor.plist", "LaunchAgents/com.vendor.editor.beta.plist",
                     "Preferences/ByHost/com.vendor.editor.\(uuid).plist", "Preferences/ByHost/com.vendor.editor.beta.\(uuid).plist"] {
            try temp.file("home/Library/\(path)")
        }

        let leftovers = AppScanner().leftovers(for: app(temp), home: home, ownGroups: [], otherAppsGroups: [])
        let guess = Dictionary(uniqueKeysWithValues: leftovers.map { ($0.url.lastPathComponent, $0.isGuess) })
        #expect(guess["ABCDE12345.com.vendor.editor"] == false)
        #expect(guess["com.vendor.editor.plist"] == false)
        #expect(guess["com.vendor.editor.\(uuid).plist"] == false)
        #expect(guess["ABCDE12345.com.vendor.editor.beta"] == true)
        #expect(guess["com.vendor.editor.beta.plist"] == true)
        #expect(guess["com.vendor.editor.beta.\(uuid).plist"] == true)
    }

    @Test func aContainerAnotherAppStillUsesIsOnlyAGuess() throws {
        let temp = try TempFolder()
        let home = try temp.folder("home")
        try temp.file("home/Library/Group Containers/UBF8T346G9.Office/db")
        try temp.file("home/Library/Group Containers/UBF8T346G9.EditorOnly/db")

        let leftovers = AppScanner().leftovers(for: app(temp), home: home,
                                               ownGroups: ["UBF8T346G9.Office", "UBF8T346G9.EditorOnly"],
                                               otherAppsGroups: ["UBF8T346G9.Office"])
        let guess = Dictionary(uniqueKeysWithValues: leftovers.map { ($0.url.lastPathComponent, $0.isGuess) })
        #expect(guess["UBF8T346G9.Office"] == true, "Shared with another installed app")
        #expect(guess["UBF8T346G9.EditorOnly"] == false, "Declared by this app alone")
    }

    @Test func groupNamesFollowTheTeamIDConvention() {
        #expect(AppScanner.isOwnGroupName("group.com.vendor.editor", id: "com.vendor.editor"))
        #expect(AppScanner.isOwnGroupName("ABCDE12345.com.vendor.editor", id: "com.vendor.editor"))
        #expect(!AppScanner.isOwnGroupName("ABCDE12345.com.vendor.editor.beta", id: "com.vendor.editor"))
        #expect(!AppScanner.isOwnGroupName("group.com.other.com.vendor.editor", id: "com.vendor.editor"))
        #expect(!AppScanner.isOwnGroupName("abcde12345.com.vendor.editor", id: "com.vendor.editor"))
    }
}
