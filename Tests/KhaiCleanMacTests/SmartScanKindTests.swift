import Foundation
import Testing
@testable import KhaiCleanMac

@Suite struct SmartScanKindTests {
    @Test func crashReportsHaveTheirOwnCategory() throws {
        let temp = try TempFolder()
        try temp.file("Library/Logs/DiagnosticReports/Xcode-2026-10-01-101500.ips", size: 900)
        try temp.file("Library/Logs/DiagnosticReports/Xcode-2026-10-02-101500.ips", size: 900)
        try temp.file("Library/Logs/DiagnosticReports/Retired/Safari_2026-09-01-090000_Mac.hang", size: 900)
        try temp.file("Library/Logs/com.vendor.app/app.log", size: 900)
        let scanner = JunkScanner(home: temp.url)

        let crashes = scanner.scan(.crashReports)
        #expect(crashes.count == 1)
        #expect(crashes.first?.members.count == 3)
        #expect(crashes.first?.detail?.contains("Xcode, Safari") == true)
        // App logs no longer include the crash reports.
        #expect(scanner.scan(.userLogs).map(\.url.lastPathComponent) == ["com.vendor.app"])
    }

    @Test func logAgeKeepsRecentFiles() throws {
        let temp = try TempFolder()
        try temp.file("Library/Logs/com.vendor.app/old.log", size: 900, daysOld: 40)
        try temp.file("Library/Logs/com.vendor.app/new.log", size: 900, daysOld: 1)
        try temp.file("Library/Logs/fresh.log", size: 900, daysOld: 1)
        try temp.file("Library/Logs/DiagnosticReports/App-2026-01-01-000000.ips", size: 900, daysOld: 3)
        let scanner = JunkScanner(logsMaxAgeDays: 30, home: temp.url)

        let logs = scanner.scan(.userLogs)
        #expect(logs.count == 1)
        #expect(logs.first?.members.map(\.lastPathComponent) == ["old.log"])
        #expect(scanner.scan(.crashReports).isEmpty)
        // Without an age limit, every log goes as before.
        #expect(JunkScanner(home: temp.url).scan(.userLogs).count == 2)
    }

    @Test func crashingAppComesFromTheFileName() {
        #expect(JunkScanner.crashingApp("Xcode-2026-10-01-101500.ips") == "Xcode")
        #expect(JunkScanner.crashingApp("Safari_2026-09-01-090000_Mac.hang") == "Safari")
        #expect(JunkScanner.crashingApp("Code Helper (Renderer)-2026-10-01-101500.ips") == "Code Helper (Renderer)")
        #expect(JunkScanner.crashingApp("panic-full.panic") == "panic-full")
    }

    @Test func oldFilesSkipRecentFoldersAndRepositories() throws {
        let temp = try TempFolder()
        try temp.file("Desktop/old-notes.txt", size: 900, daysOld: 200)
        try temp.file("Desktop/today.txt", size: 900, daysOld: 1)
        try temp.file("Documents/Taxes 2019/form.pdf", size: 900, daysOld: 300)
        try temp.age(temp.url.appending(path: "Documents/Taxes 2019"), days: 300)
        try temp.file("Documents/Active/plan.txt", size: 900, daysOld: 2)
        try temp.age(temp.url.appending(path: "Documents/Active"), days: 300)
        try temp.file("Documents/repo/.git/HEAD", daysOld: 300)
        try temp.file("Documents/repo/main.swift", size: 900, daysOld: 300)
        try temp.age(temp.url.appending(path: "Documents/repo"), days: 300)

        var scanner = JunkScanner(downloadsMaxAgeDays: 90, home: temp.url)
        // Everything here was just added, which counts as use.
        #expect(scanner.scan(.oldFiles).isEmpty)
        scanner.countsAddedDate = false
        #expect(Set(scanner.scan(.oldFiles).map(\.url.lastPathComponent)) == ["old-notes.txt", "Taxes 2019"])
    }

    @Test func newKindsKeepTheSafetyDefaults() {
        #expect(!JunkKind.oldFiles.selectedByDefault)
        #expect(JunkKind.oldFiles.needsFullDiskAccess)
        #expect(JunkKind.crashReports.selectedByDefault)
    }
}

@Suite struct OwnCacheTests {
    @Test func neitherBuildOffersTheOthersCache() throws {
        let temp = try TempFolder()
        try temp.file("Library/Caches/\(AppInfo.productionBundleID)/Trash staging/x", size: 900)
        try temp.file("Library/Caches/\(AppInfo.productionBundleID).dev/Update/y", size: 900)
        try temp.file("Library/Caches/com.vendor.app/z", size: 900)
        #expect(JunkScanner(home: temp.url).scan(.userCache).map(\.url.lastPathComponent) == ["com.vendor.app"])
    }
}
