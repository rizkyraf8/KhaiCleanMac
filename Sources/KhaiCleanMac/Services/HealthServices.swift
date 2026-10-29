import Foundation
import IOKit

/// How worn the battery is, as macOS itself reports it in System Settings › Battery.
struct BatteryHealth: Sendable, Equatable {
    enum Condition: Sendable, Equatable {
        case normal
        case serviceRecommended
        /// A wording this version doesn't know yet, shown as macOS wrote it.
        case other(String)
    }

    let cycleCount: Int
    /// Cycles the battery is designed for (1000 on every Apple silicon MacBook so far).
    let designCycleCount: Int?
    /// Today's full charge compared to when it was new, in percent.
    let maximumCapacity: Int?
    let condition: Condition

    var cycleFraction: Double? {
        designCycleCount.map { $0 > 0 ? Double(cycleCount) / Double($0) : 0 }
    }
}

/// The startup disk's self-check (S.M.A.R.T.), as Disk Utility shows it.
struct DiskHealth: Sendable, Equatable {
    enum Status: Sendable, Equatable { case verified, failing, notSupported }

    let name: String
    let status: Status
    let isSolidState: Bool
}

enum HealthReader {
    /// `nil` on Macs without a battery.
    static func battery() -> BatteryHealth? {
        guard let output = StartupScanner.run("/usr/sbin/system_profiler", ["SPPowerDataType", "-json"]) else { return nil }
        return parseBattery(Data(output.utf8), registry: batteryRegistry())
    }

    /// `system_profiler` has Apple's own maximum-capacity figure, which a raw capacity ratio
    /// doesn't always match. The IORegistry adds the design cycle count and a fallback.
    static func parseBattery(_ json: Data, registry: [String: Any] = [:]) -> BatteryHealth? {
        let root = (try? JSONSerialization.jsonObject(with: json)) as? [String: Any]
        let sections = root?["SPPowerDataType"] as? [[String: Any]] ?? []
        let info = sections.lazy.compactMap { $0["sppower_battery_health_info"] as? [String: Any] }.first

        let batteryData = registry["BatteryData"] as? [String: Any] ?? [:]
        func number(_ key: String) -> Int? { (registry[key] as? Int) ?? (batteryData[key] as? Int) }

        guard let cycles = (info?["sppower_battery_cycle_count"] as? Int) ?? number("CycleCount") else { return nil }

        var capacity = (info?["sppower_battery_health_maximum_capacity"] as? String)
            .flatMap { Int($0.trimmingCharacters(in: CharacterSet(charactersIn: "% "))) }
        if capacity == nil, let design = number("DesignCapacity"), design > 0,
           let nominal = number("NominalChargeCapacity") ?? number("AppleRawMaxCapacity") {
            capacity = min(100, Int((Double(nominal) / Double(design) * 100).rounded()))
        }

        let condition: BatteryHealth.Condition
        switch (info?["sppower_battery_health"] as? String)?.trimmingCharacters(in: .whitespaces) {
        case nil, "Good", "Normal": condition = .normal
        case let text? where text.localizedCaseInsensitiveContains("service")
            || text.localizedCaseInsensitiveContains("replace") || text == "Poor" || text == "Fair":
            condition = .serviceRecommended
        case let text?: condition = .other(text)
        }

        return BatteryHealth(cycleCount: cycles, designCycleCount: number("DesignCycleCount9C"),
                             maximumCapacity: capacity, condition: condition)
    }

    private static func batteryRegistry() -> [String: Any] {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return [:] }
        defer { IOObjectRelease(service) }
        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS else { return [:] }
        return properties?.takeRetainedValue() as? [String: Any] ?? [:]
    }

    static func startupDisk() -> DiskHealth? {
        // The startup volume answers for the physical disk under its APFS container.
        guard let output = StartupScanner.run("/usr/sbin/diskutil", ["info", "-plist", "/"]) else { return nil }
        let volume = parseDisk(Data(output.utf8))
        guard let store = volume?.physicalStore,
              let whole = StartupScanner.run("/usr/sbin/diskutil", ["info", "-plist", store]) else { return volume?.health }
        return parseDisk(Data(whole.utf8))?.health ?? volume?.health
    }

    static func parseDisk(_ plist: Data) -> (health: DiskHealth, physicalStore: String?)? {
        guard let info = (try? PropertyListSerialization.propertyList(from: plist, format: nil)) as? [String: Any],
              let smart = info["SMARTStatus"] as? String else { return nil }
        let status: DiskHealth.Status = switch smart {
        case "Verified": .verified
        case "Failing": .failing
        default: .notSupported
        }
        let mediaName = (info["MediaName"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let store = (info["APFSPhysicalStores"] as? [[String: Any]])?.first?["APFSPhysicalStore"] as? String
        // "disk0s2" → "disk0", the whole disk whose name is the drive model.
        let wholeDisk = store.map { $0.replacing(/s\d+$/, with: "") }
        return (DiskHealth(name: mediaName ?? info["VolumeName"] as? String ?? "Disk", status: status,
                           isSolidState: info["SolidState"] as? Bool ?? false), wholeDisk)
    }
}
