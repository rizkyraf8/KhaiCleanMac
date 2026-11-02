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

@Suite struct MenuBarStatusTests {
    @Test func showsTheScanThenItsResultsThenTheCPUAgain() {
        let scanning = MenuBarStatus(phase: .scanning, hasUnseenResults: false, progress: 1, found: 0, cpu: 0.07)
        #expect(scanning.value == "100%")
        #expect(scanning.symbol != nil)
        let unseen = MenuBarStatus(phase: .results, hasUnseenResults: true, progress: 1, found: 2_000_000, cpu: 0.07)
        #expect(unseen.symbol == "checkmark.circle.fill")
        // Once the results are opened, the CPU reading comes back.
        #expect(MenuBarStatus(phase: .results, hasUnseenResults: false, progress: 1, found: 2_000_000, cpu: 0.07)
                == MenuBarStatus(phase: .idle, hasUnseenResults: false, progress: 0, found: 0, cpu: 0.07))
        #expect(MenuBarStatus(phase: .done, hasUnseenResults: false, progress: 1, found: 0, cpu: 0.07).value == "7%")
    }
}
