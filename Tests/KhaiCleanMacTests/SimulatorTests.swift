import Foundation
import Testing
@testable import KhaiCleanMac

@Suite struct SimulatorTests {
    /// Trimmed from `simctl runtime list -j` with two iOS runtimes and one visionOS runtime.
    private let runtimes = Data("""
    {
      "A": {"identifier": "A", "version": "26.5", "build": "23F77", "deletable": true, "sizeBytes": 8494282293,
            "platformIdentifier": "com.apple.platform.iphonesimulator", "lastUsedAt": "2026-09-08T06:35:59Z",
            "path": "/Library/Developer/CoreSimulator/Images/A.dmg"},
      "B": {"identifier": "B", "version": "18.4", "build": "22E238", "deletable": true, "sizeBytes": 9100000000,
            "platformIdentifier": "com.apple.platform.iphonesimulator", "lastUsedAt": "2025-04-01T10:00:00Z",
            "path": "/Library/Developer/CoreSimulator/Images/B.dmg"},
      "C": {"identifier": "C", "version": "2.4", "deletable": true, "sizeBytes": 7000000000,
            "platformIdentifier": "com.apple.platform.xrsimulator", "path": "/Library/Developer/CoreSimulator/Images/C.dmg"},
      "D": {"identifier": "D", "version": "17.0", "deletable": false, "sizeBytes": 1,
            "platformIdentifier": "com.apple.platform.iphonesimulator", "path": "/Library/Developer/CoreSimulator/Images/D.dmg"}
    }
    """.utf8)

    @Test func olderRuntimesArePreselectedButNeverTheNewest() throws {
        let items = Simulators.parseRuntimes(runtimes)
        #expect(items.count == 3, "Runtimes Xcode marks as not deletable are left out")
        let old = try #require(items.first { $0.simulator == .runtime(identifier: "B") })
        #expect(old.selectedByDefault)
        #expect(old.title.contains("iOS 18.4"))
        #expect(old.size == 9_100_000_000)
        #expect(items.first { $0.simulator == .runtime(identifier: "A") }?.selectedByDefault == false)
        #expect(items.first { $0.simulator == .runtime(identifier: "C") }?.selectedByDefault == false,
                "The only visionOS runtime is the newest of its platform")
    }

    @Test func devicesWithoutTheirRuntimeArePreselectedAndBootedOnesSkipped() throws {
        let json = Data("""
        {"devices": {
          "com.apple.CoreSimulator.SimRuntime.iOS-26-5": [
            {"udid": "U1", "name": "iPhone 17 Pro", "state": "Shutdown", "isAvailable": true, "dataPathSize": 2574086144,
             "dataPath": "/Users/me/Library/Developer/CoreSimulator/Devices/U1/data", "lastUsedAt": "2026-09-08T06:35:47Z"},
            {"udid": "U2", "name": "iPhone 17", "state": "Booted", "isAvailable": true, "dataPathSize": 100,
             "dataPath": "/Users/me/Library/Developer/CoreSimulator/Devices/U2/data"}
          ],
          "com.apple.CoreSimulator.SimRuntime.iOS-17-0": [
            {"udid": "U3", "name": "iPhone 15", "state": "Shutdown", "isAvailable": false, "dataPathSize": 500,
             "dataPath": "/Users/me/Library/Developer/CoreSimulator/Devices/U3/data"}
          ]
        }}
        """.utf8)
        let items = Simulators.parseDevices(json)
        #expect(items.map(\.simulator) == [.device(udid: "U1"), .device(udid: "U3")], "Largest first; the booted one is skipped")
        let first = try #require(items.first)
        #expect(first.title == "iPhone 17 Pro · iOS 26.5")
        #expect(first.url.path == "/Users/me/Library/Developer/CoreSimulator/Devices/U1")
        #expect(!first.selectedByDefault)
        #expect(items.last?.selectedByDefault == true)
        #expect(items.last?.note != nil)
    }
}
