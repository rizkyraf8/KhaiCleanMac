import AppKit
import Darwin

enum MemoryPressure: Sendable {
    case normal, warning, critical
}

/// A snapshot of how RAM is used, split the way Activity Monitor splits it.
struct MemoryStats: Sendable {
    let total: UInt64
    /// Memory apps allocated themselves.
    let app: UInt64
    /// Memory the system keeps in RAM and can't page out.
    let wired: UInt64
    let compressed: UInt64
    /// Copies of files kept around for speed; macOS gives this up as soon as an app needs RAM.
    let cached: UInt64
    let free: UInt64
    let swapUsed: UInt64
    let swapTotal: UInt64
    let pressure: MemoryPressure

    var used: UInt64 { app + wired + compressed }

    static func read() -> MemoryStats? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        let page = UInt64(getpagesize())
        let total = ProcessInfo.processInfo.physicalMemory
        // Purgeable pages are counted as cache; never let them take "app" memory below zero.
        let appPages = UInt64(stats.internal_page_count) > UInt64(stats.purgeable_count)
            ? UInt64(stats.internal_page_count) - UInt64(stats.purgeable_count) : 0
        let app = appPages * page
        let wired = UInt64(stats.wire_count) * page
        let compressed = UInt64(stats.compressor_page_count) * page
        let cached = (UInt64(stats.external_page_count) + UInt64(stats.purgeable_count)) * page
        let accounted = app + wired + compressed + cached
        let free = total > accounted ? total - accounted : UInt64(stats.free_count) * page

        var swap = xsw_usage()
        var swapSize = MemoryLayout<xsw_usage>.size
        sysctlbyname("vm.swapusage", &swap, &swapSize, nil, 0)

        var level: Int32 = 1
        var levelSize = MemoryLayout<Int32>.size
        sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &levelSize, nil, 0)
        let pressure: MemoryPressure = level >= 4 ? .critical : (level >= 2 ? .warning : .normal)

        return MemoryStats(
            total: total, app: app, wired: wired, compressed: compressed, cached: cached, free: free,
            swapUsed: swap.xsu_used, swapTotal: swap.xsu_total, pressure: pressure
        )
    }
}

/// An app and all its helper processes (Chrome's tabs, for example, are separate processes).
struct AppMemoryUsage: Identifiable, Sendable {
    let bundleURL: URL
    let name: String
    let footprint: UInt64
    let processCount: Int

    var id: URL { bundleURL }
}

enum AppMemoryScanner {
    /// Sums each process's footprint (what Activity Monitor shows as "Memory") per enclosing .app.
    /// Only the user's own processes can be read, which is also all that can be quit from here.
    static func topApps(limit: Int = 12) -> [AppMemoryUsage] {
        let capacity = proc_listallpids(nil, 0) + 64
        guard capacity > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(capacity))
        let count = pids.withUnsafeMutableBytes { proc_listallpids($0.baseAddress, Int32($0.count)) }
        guard count > 0 else { return [] }

        var byApp: [URL: (footprint: UInt64, processes: Int)] = [:]
        var pathBuffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        for pid in pids.prefix(Int(count)) where pid > 0 {
            guard let footprint = footprint(of: pid) else { continue }
            let length = proc_pidpath(pid, &pathBuffer, UInt32(pathBuffer.count))
            guard length > 0 else { continue }
            let path = String(decoding: pathBuffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
            guard let bundle = enclosingApp(of: path) else { continue }
            byApp[bundle, default: (0, 0)].footprint += footprint
            byApp[bundle, default: (0, 0)].processes += 1
        }

        return byApp
            .map { url, usage in
                AppMemoryUsage(bundleURL: url, name: displayName(of: url), footprint: usage.footprint, processCount: usage.processes)
            }
            .sorted { $0.footprint > $1.footprint }
            .prefix(limit)
            .map { $0 }
    }

    private static func footprint(of pid: pid_t) -> UInt64? {
        var info = rusage_info_v2()
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V2, $0) }
        }
        return result == 0 ? info.ri_phys_footprint : nil
    }

    /// The app a process belongs to: helpers inside Frameworks or Helpers count towards the outer app,
    /// but an app shipped in an Applications folder inside another (Simulator inside Xcode) is its own.
    static func enclosingApp(of path: String) -> URL? {
        var app: String?
        var searchStart = path.startIndex
        while let range = path.range(of: ".app/", range: searchStart..<path.endIndex) {
            let candidate = String(path[..<range.lowerBound]) + ".app"
            if let outer = app {
                if candidate.dropFirst(outer.count).contains("/Applications/") { app = candidate }
            } else {
                app = candidate
            }
            searchStart = range.upperBound
        }
        return app.map { URL(filePath: $0) }
    }

    private static func displayName(of bundle: URL) -> String {
        FileManager.default.displayName(atPath: bundle.path).replacingOccurrences(of: ".app", with: "")
    }
}

enum MemoryActions {
    /// Asks an app to quit the normal way, so it can still save or ask about unsaved work.
    @MainActor
    static func quit(_ app: AppMemoryUsage) -> Bool {
        let running = NSWorkspace.shared.runningApplications.filter { $0.bundleURL?.path == app.bundleURL.path }
        guard !running.isEmpty else { return false }
        return running.map { $0.terminate() }.contains(true)
    }

    /// The app's own process and Finder are never offered for quitting.
    @MainActor
    static func canQuit(_ app: AppMemoryUsage) -> Bool {
        NSWorkspace.shared.runningApplications.contains {
            $0.bundleURL?.path == app.bundleURL.path
                && $0.activationPolicy == .regular
                && $0.bundleIdentifier != AppInfo.bundleID
                && $0.bundleIdentifier != "com.apple.finder"
        }
    }

    /// Runs `purge` behind macOS's own administrator prompt, so the password never passes through this app.
    /// It only drops cached file data, which macOS would reuse or release on its own anyway.
    static func purgeCachedFiles() -> Bool {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/osascript")
        process.arguments = ["-e", "do shell script \"/usr/sbin/purge\" with administrator privileges"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}
