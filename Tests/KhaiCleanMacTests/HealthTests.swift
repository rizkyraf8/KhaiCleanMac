import Foundation
import Testing
@testable import KhaiCleanMac

@Suite struct HealthTests {
    @Test func readsApplesOwnBatteryFigures() {
        let json = Data("""
        {"SPPowerDataType":[{"_name":"spbattery_information","sppower_battery_health_info":
          {"sppower_battery_cycle_count":363,"sppower_battery_health":"Good","sppower_battery_health_maximum_capacity":"88%"}},
          {"_name":"sppower_ac_charger_information"}]}
        """.utf8)
        let registry: [String: Any] = ["DesignCycleCount9C": 1000, "BatteryData": ["DesignCapacity": 6249, "NominalChargeCapacity": 5582]]
        let health = HealthReader.parseBattery(json, registry: registry)
        #expect(health == BatteryHealth(cycleCount: 363, designCycleCount: 1000, maximumCapacity: 88, condition: .normal),
                "Apple's percentage wins over the raw capacity ratio (89%)")
    }

    @Test func fallsBackToTheRegistryAndFlagsService() {
        let json = Data(#"{"SPPowerDataType":[{"sppower_battery_health_info":{"sppower_battery_cycle_count":1210,"sppower_battery_health":"Service Recommended"}}]}"#.utf8)
        let health = HealthReader.parseBattery(json, registry: ["DesignCapacity": 5000, "AppleRawMaxCapacity": 3600])
        #expect(health?.maximumCapacity == 72)
        #expect(health?.condition == .serviceRecommended)
    }

    @Test func noBatteryMeansNil() {
        let json = Data(#"{"SPPowerDataType":[{"_name":"sppower_ac_charger_information"}]}"#.utf8)
        #expect(HealthReader.parseBattery(json) == nil)
    }

    @Test func readsSmartStatusAndPhysicalStore() throws {
        let volume: [String: Any] = ["SMARTStatus": "Verified", "MediaName": "", "VolumeName": "Macintosh HD", "SolidState": true,
                                     "APFSPhysicalStores": [["APFSPhysicalStore": "disk0s2"]]]
        let parsed = try #require(HealthReader.parseDisk(try PropertyListSerialization.data(fromPropertyList: volume, format: .xml, options: 0)))
        #expect(parsed.physicalStore == "disk0")
        #expect(parsed.health == DiskHealth(name: "Macintosh HD", status: .verified, isSolidState: true))

        let failing: [String: Any] = ["SMARTStatus": "Failing", "MediaName": "APPLE SSD AP0512Z", "SolidState": true]
        let disk = try #require(HealthReader.parseDisk(try PropertyListSerialization.data(fromPropertyList: failing, format: .xml, options: 0)))
        #expect(disk.health.status == .failing)
        #expect(disk.health.name == "APPLE SSD AP0512Z")
    }
}
