import AppKit
import CryptoKit
import IOKit.ps

struct DuplicateScanner: Sendable {
    enum Progress: Sendable {
        case collecting(Int)
        case comparing(Double)
    }

    private static let keys: [URLResourceKey] = [
        .isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey, .fileResourceIdentifierKey,
        .contentModificationDateKey, .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey,
    ]

    /// Folders whose files belong to a project, package or bundle: removing one "duplicate"
    /// inside them breaks the thing that owns it, so they are never searched.
    private static let protectedFolderNames: Set<String> = [
        "node_modules", "Pods", "Carthage", "DerivedData", "build", "Build", "dist",
        "vendor", "venv", "site-packages", "bower_components", "go",
    ]
    private static let protectedFolderExtensions: Set<String> = [
        "app", "appex", "framework", "xcframework", "bundle", "plugin", "kext",
        "photoslibrary", "musiclibrary", "tvlibrary", "xcodeproj", "xcworkspace",
    ]

    static func isProtected(_ folder: URL) -> Bool {
        protectedFolderNames.contains(folder.lastPathComponent)
            || protectedFolderExtensions.contains(folder.pathExtension.lowercased())
    }

    /// Groups files by size, then by a hash of the first 64 KB, then by a full SHA-256.
    func scan(minSize: Int64, root: URL = .homeDirectory, progress: @Sendable (Progress) -> Void) -> [DuplicateGroup] {
        let bySize = collect(minSize: minSize, root: root, progress: progress)
        let candidates = bySize.values.filter { $0.count > 1 }
        let total = Double(candidates.reduce(0) { $0 + $1.count })
        var hashed = 0.0

        var groups: [DuplicateGroup] = []
        for sameSize in candidates {
            guard let size = sameSize.first?.size else { continue }
            let byHead = Dictionary(grouping: sameSize) { Self.hash($0.file.url, limit: 64 * 1024) ?? UUID().uuidString }
            for sameHead in byHead.values {
                if Task.isCancelled { return [] }
                hashed += Double(sameHead.count)
                progress(.comparing(hashed / max(total, 1)))
                guard sameHead.count > 1 else { continue }
                let needsFullHash = size > 64 * 1024
                let byContent = needsFullHash
                    ? Dictionary(grouping: sameHead) { Self.hash($0.file.url, limit: nil) ?? UUID().uuidString }
                    : ["head": sameHead]
                for (digest, matches) in byContent where matches.count > 1 {
                    let files = matches.map(\.file).sorted { ($0.modified ?? .distantFuture) < ($1.modified ?? .distantFuture) }
                    groups.append(DuplicateGroup(id: "\(size)-\(digest)-\(files[0].url.path)", size: size, files: files))
                }
            }
        }
        return groups.sorted { $0.wasted > $1.wasted }
    }

    private func collect(minSize: Int64, root home: URL, progress: (Progress) -> Void) -> [Int64: [(file: DuplicateFile, size: Int64)]] {
        var bySize: [Int64: [(file: DuplicateFile, size: Int64)]] = [:]
        guard let enumerator = FileManager.default.enumerator(
            at: home, includingPropertiesForKeys: Self.keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants], errorHandler: { _, _ in true }
        ) else { return [:] }

        var visited = 0
        // Hard links and paths through symlinks reach the same file; count each file once.
        var seenFiles = Set<NSObject>()
        var cancelled = false
        enumerator.forEachURL { url in
            if Task.isCancelled { cancelled = true; return false }
            visited += 1
            if visited % 1_500 == 0 { progress(.collecting(visited)) }
            guard let values = try? url.resourceValues(forKeys: Set(Self.keys)) else { return true }
            if values.isSymbolicLink == true {
                enumerator.skipDescendants()
                return true
            }
            if values.isDirectory == true {
                if ScanLocation.skips(url, root: home) || Self.isProtected(url) { enumerator.skipDescendants() }
                return true
            }
            guard values.isRegularFile == true,
                  let size = values.fileSize.map(Int64.init), size >= minSize else { return true }
            if let identity = values.fileResourceIdentifier as? NSObject, !seenFiles.insert(identity).inserted { return true }
            // Reading an iCloud file that isn't downloaded would pull it from the cloud.
            if values.isUbiquitousItem == true, values.ubiquitousItemDownloadingStatus != .current { return true }
            bySize[size, default: []].append((DuplicateFile(url: url, modified: values.contentModificationDate), size))
            return true
        }
        if cancelled { return [:] }
        progress(.collecting(visited))
        return bySize
    }

    /// SHA-256 of the first `limit` bytes, or of the whole file. A read error gives nil rather than
    /// the digest of what was read so far, so a half-read file never looks like a copy.
    static func hash(_ url: URL, limit: Int?) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        var remaining = limit ?? .max
        while remaining > 0 {
            if Task.isCancelled { return nil }
            let read = autoreleasepool { () -> Int? in
                do {
                    guard let chunk = try handle.read(upToCount: min(1 << 20, remaining)), !chunk.isEmpty else { return 0 }
                    hasher.update(data: chunk)
                    return chunk.count
                } catch {
                    return nil
                }
            }
            guard let read else { return nil }
            guard read > 0 else { break }
            remaining -= read
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Checks a group again right before cleanup, since files may have changed since the scan. A selected
    /// copy is only removed when it is still a regular file of the group's size whose content matches a
    /// different, unselected copy that still exists. Anything that fails to read counts as changed.
    static func verifiedRemovals(in group: DuplicateGroup, selected: Set<URL>) -> (remove: [DuplicateFile], skipped: [DuplicateFile]) {
        let chosen = group.files.filter { selected.contains($0.url) }
        guard !chosen.isEmpty else { return ([], []) }

        func identity(_ url: URL) -> (id: NSObject, size: Int64)? {
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .fileResourceIdentifierKey]),
                  values.isRegularFile == true, values.isSymbolicLink != true,
                  let size = values.fileSize, let id = values.fileResourceIdentifier as? NSObject else { return nil }
            return (id, Int64(size))
        }

        var keptDigests = Set<String>()
        var keptFiles = Set<NSObject>()
        for file in group.files where !selected.contains(file.url) {
            guard let kept = identity(file.url), kept.size == group.size, let digest = hash(file.url, limit: nil) else { continue }
            keptDigests.insert(digest)
            keptFiles.insert(kept.id)
        }

        var remove: [DuplicateFile] = []
        var skipped: [DuplicateFile] = []
        for file in chosen {
            // A hard link to a kept copy is the kept copy: trashing it would leave nothing behind.
            if let current = identity(file.url), current.size == group.size, !keptFiles.contains(current.id),
               let digest = hash(file.url, limit: nil), keptDigests.contains(digest) {
                remove.append(file)
            } else {
                skipped.append(file)
            }
        }
        return (remove, skipped)
    }
}

enum SpaceScanner {
    /// Immediate children of a folder, hidden ones included (they count towards disk use).
    static func entries(in folder: URL) -> [SpaceItem] {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isPackageKey, .isSymbolicLinkKey]
        let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: Array(keys))) ?? []
        return urls.compactMap { url in
            let values = try? url.resourceValues(forKeys: keys)
            if values?.isSymbolicLink == true { return nil }
            let canOpen = values?.isDirectory == true && values?.isPackage != true
            return SpaceItem(url: url, canOpen: canOpen, size: nil)
        }
    }
}

struct BatteryInfo: Sendable {
    let percent: Int
    let isCharging: Bool
}

/// Live CPU, memory, disk and battery readings for the menu bar.
@MainActor @Observable
final class SystemMonitor {
    private(set) var cpu: Double = 0
    private(set) var memoryUsed: UInt64 = 0
    let memoryTotal = ProcessInfo.processInfo.physicalMemory
    private(set) var disk: DiskInfo?
    private(set) var battery: BatteryInfo?

    private var previousTicks: [UInt32]?

    var memoryFraction: Double { memoryTotal > 0 ? Double(memoryUsed) / Double(memoryTotal) : 0 }

    init() {
        // Ends once the monitor is gone; `self?.sample()` alone would keep a released monitor's loop running.
        Task { [weak self] in
            while !Task.isCancelled {
                guard let monitor = self else { return }
                monitor.sample()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private func sample() {
        if let ticks = Self.cpuTicks() {
            if let previous = previousTicks {
                let delta = zip(ticks, previous).map { Double($0 &- $1) }
                let total = delta.reduce(0, +)
                // Order: user, system, idle, nice.
                if total > 0 { cpu = (total - delta[2]) / total }
            }
            previousTicks = ticks
        }
        memoryUsed = Self.memoryUsed() ?? memoryUsed
        disk = DiskInfo.current()
        battery = Self.battery()
    }

    private static func cpuTicks() -> [UInt32]? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let t = info.cpu_ticks
        return [t.0, t.1, t.2, t.3]
    }

    /// Roughly what Activity Monitor calls "Memory Used": app memory + wired + compressed.
    private static func memoryUsed() -> UInt64? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let page = UInt64(getpagesize())
        let appPages = UInt64(stats.internal_page_count) &- UInt64(stats.purgeable_count)
        return (appPages + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)) * page
    }

    private static func battery() -> BatteryInfo? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any],
                  let current = description[kIOPSCurrentCapacityKey] as? Int,
                  let max = description[kIOPSMaxCapacityKey] as? Int, max > 0 else { continue }
            return BatteryInfo(percent: current * 100 / max, isCharging: description[kIOPSIsChargingKey] as? Bool ?? false)
        }
        return nil
    }
}
