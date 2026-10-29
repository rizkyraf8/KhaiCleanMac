import Foundation
import Testing
@testable import KhaiCleanMac

@Suite struct VolumeTests {
    @Test func onlyMountedDisksUnderVolumesCount() {
        let empty = URLResourceValues()
        #expect(VolumeFinder.location(URL(filePath: "/Volumes/Photos"), values: empty)?.name == "Photos")
        #expect(VolumeFinder.location(URL(filePath: "/"), values: empty) == nil)
        #expect(VolumeFinder.location(URL(filePath: "/Library/Developer/CoreSimulator/Volumes/iOS_23F77"), values: empty) == nil)
        #expect(VolumeFinder.location(URL(filePath: "/Volumes/Photos/Folder"), values: empty) == nil)
    }

    @Test func scansStepOverADisksSystemFolders() {
        let root = URL(filePath: "/Volumes/Photos")
        for name in ["System", "Library", ".Spotlight-V100", ".Trashes", "Backups.backupdb"] {
            #expect(ScanLocation.skips(root.appending(path: name), root: root), "\(name) should be skipped")
        }
        #expect(!ScanLocation.skips(root.appending(path: "Movies"), root: root))
        #expect(!ScanLocation.skips(root.appending(path: "Movies/Library"), root: root), "Only the top level counts")
        #expect(ScanLocation.skips(URL.homeDirectory.appending(path: "Library"), root: .homeDirectory))
        #expect(!ScanLocation.skips(URL.homeDirectory.appending(path: "System"), root: .homeDirectory))
    }

    @Test func largeFilesOnADiskSkipTheSystemFolders() throws {
        let temp = try TempFolder()
        try temp.file("Movies/holiday.mov", size: 4_096)
        try temp.file("Library/huge.cache", size: 4_096)
        try temp.file(".Spotlight-V100/index", size: 4_096)

        let found = LargeFileScanner().scan(minSize: 1_000, root: temp.url) { _ in }
        #expect(found.map(\.name) == ["holiday.mov"])
    }

    @Test func duplicatesOnADiskAreFound() throws {
        let temp = try TempFolder()
        let content = Data(repeating: 0x42, count: 2_048)
        try temp.file("A/photo.jpg", contents: content)
        try temp.file("B/photo copy.jpg", contents: content)
        try temp.file("Library/photo.jpg", contents: content)

        let groups = DuplicateScanner().scan(minSize: 1_000, root: temp.url) { _ in }
        #expect(groups.count == 1)
        #expect(groups.first?.files.count == 2, "The disk's Library folder is skipped")
    }

    @Test func aDisksSystemFoldersAreNeverRemoved() {
        let home = URL(filePath: "/Users/someone")
        for path in ["/Volumes/Photos/.Spotlight-V100", "/Volumes/Photos/.Trashes/501/old.mov",
                     "/Volumes/Photos/.fseventsd", "/Volumes/Photos/Backups.backupdb/Mac", "/Volumes/Photos/System/Library"] {
            #expect(!SafetyGuard.isAllowed(URL(filePath: path), home: home), "\(path) must be protected")
        }
        #expect(SafetyGuard.isAllowed(URL(filePath: "/Volumes/Photos/Movies/holiday.mov"), home: home))
    }
}
