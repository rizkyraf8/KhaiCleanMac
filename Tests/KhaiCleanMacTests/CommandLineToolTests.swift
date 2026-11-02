import Foundation
import Testing
@testable import KhaiCleanMac

@MainActor
@Suite struct CommandLineToolTests {
    @Test func theAppStartsWithoutACommand() {
        #expect(CommandLineTool.runIfRequested(["KhaiCleanMac"]) == nil)
        // Finder and Xcode pass their own flags; those must still open the app.
        #expect(CommandLineTool.runIfRequested(["KhaiCleanMac", "-NSDocumentRevisionsDebugMode", "YES"]) == nil)
        #expect(CommandLineTool.runIfRequested(["KhaiCleanMac", "--snapshot", "/tmp/x"]) == nil)
    }

    @Test func categoriesByIDOrShortName() {
        #expect(CommandLineTool.kinds([]) == JunkKind.allCases)
        #expect(CommandLineTool.kinds(["--category", "xcode", "-c", "userLogs", "--dry-run"]) == [.developer, .userLogs])
        #expect(CommandLineTool.kinds(["--category", "nope"]) == nil)
        #expect(CommandLineTool.kinds(["--category"]) == nil)
    }

    @Test func versionAndUnknownCategory() {
        var lines: [String] = []
        #expect(CommandLineTool.runIfRequested(["khaiclean", "version"]) { lines.append($0) } == 0)
        #expect(lines.first?.hasPrefix(AppInfo.name) == true)
        #expect(CommandLineTool.runIfRequested(["khaiclean", "scan", "-c", "nope"]) { _ in } == 64)
    }
}
