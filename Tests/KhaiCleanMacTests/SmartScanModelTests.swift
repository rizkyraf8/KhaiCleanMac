import Foundation
import Testing
@testable import KhaiCleanMac

/// The window and the menu bar share one Smart Scan, so a second start must not begin another one.
@MainActor @Suite struct SmartScanModelTests {
    @Test func aSecondStartWhileScanningIsIgnored() {
        let model = SmartScanModel()
        model.start()
        #expect(model.phase == .scanning)
        #expect(model.isBusy)
        model.start()
        #expect(model.phase == .scanning)
        model.cancel()
    }

    @Test func cancelReturnsToIdleAndTheStoppedScanStaysStopped() async throws {
        let model = SmartScanModel()
        model.start()
        model.cancel()
        #expect(model.phase == .idle)
        #expect(model.categories.isEmpty)
        #expect(!model.hasUnseenResults)
        // The cancelled task still gets to run; it must not bring the scan back.
        try await Task.sleep(for: .milliseconds(300))
        #expect(model.phase == .idle)
        #expect(model.categories.isEmpty)
    }
}
