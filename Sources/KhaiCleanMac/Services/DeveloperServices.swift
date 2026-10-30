import AppKit
import SwiftUI

enum DevCategory: String, CaseIterable, Identifiable, Sendable {
    case projects, packageCaches, simulators, xcodeArchives

    var id: String { rawValue }

    var title: String {
        switch self {
        case .projects: L("Dependensi Proyek", "Project Dependencies")
        case .packageCaches: L("Cache Package Manager", "Package Manager Caches")
        case .simulators: L("Simulator Xcode", "Xcode Simulators")
        case .xcodeArchives: L("Arsip Xcode", "Xcode Archives")
        }
    }

    func subtitle(days: Int) -> String {
        switch self {
        case .projects:
            L("node_modules, Pods, .build, dan target. Bisa dipasang ulang kapan saja. Yang tidak dipakai lebih dari \(days) hari dipilih otomatis.",
              "node_modules, Pods, .build and target. They can be reinstalled any time. Ones unused for \(days)+ days are preselected.")
        case .packageCaches:
            L("Hanya library dan versi yang tidak dipakai lebih dari \(days) hari yang dibersihkan. Yang masih dipakai proyek aktif tetap disimpan.",
              "Only libraries and versions unused for \(days)+ days are cleaned. Anything your active projects still use stays.")
        case .simulators:
            L("Runtime iOS, watchOS, tvOS, visionOS dan perangkat simulatornya. Dihapus lewat Xcode, tidak lewat Trash; runtime bisa diunduh lagi di Xcode › Settings › Components. Runtime lama yang tidak dipakai lebih dari \(days) hari dan simulator yang runtimenya sudah hilang dipilih otomatis.",
              "iOS, watchOS, tvOS and visionOS runtimes and their simulator devices. Removed through Xcode, not the Trash; runtimes can be downloaded again in Xcode › Settings › Components. Older runtimes unused for \(days)+ days and simulators whose runtime is gone are preselected.")
        case .xcodeArchives:
            L("Build yang pernah di-archive. Berisi dSYM untuk membaca laporan crash, jadi tidak dipilih otomatis.",
              "Builds you archived. They hold the dSYMs needed to read crash reports, so none are preselected.")
        }
    }

    var symbol: String {
        switch self {
        case .projects: "shippingbox.fill"
        case .packageCaches: "arrow.down.circle.fill"
        case .simulators: "ipad.and.iphone"
        case .xcodeArchives: "archivebox.fill"
        }
    }

    var colors: [Color] {
        switch self {
        case .projects: Palette.leaf
        case .packageCaches: Palette.sky
        case .simulators: Palette.ocean
        case .xcodeArchives: Palette.candy
        }
    }
}

/// One piece of a cache (a library version, a build-cache file…) and when anything in it was last read or written.
struct CacheEntry: Hashable, Sendable {
    let url: URL
    let size: Int64
    let lastUsed: Date
    /// Referenced by a project that was built recently, so it stays no matter how old it looks.
    var isPinned = false
}

struct DevItem: Identifiable, Hashable, Sendable {
    let url: URL
    var size: Int64
    let title: String
    let tool: String
    let lastUsed: Date?
    var selectedByDefault = true
    /// A warning shown under the item, e.g. for folders the tool itself doesn't use.
    var note: String?
    /// Apps that hold this cache open while running; it is locked while one of them is.
    var lockingBundleIDs: [String] = []
    /// For caches cleaned entry by entry: only stale entries go, the folder stays.
    var entries: [CacheEntry] = []
    /// Cleaned entry by entry, never as a whole folder. Set by the scanner and never inferred from
    /// `entries`: once every entry is gone the folder may still hold config or credentials.
    var isSmart = false
    /// Set for simulator runtimes and devices, which only `simctl` may remove.
    var simulator: SimulatorTarget?

    var id: URL { url }

    func staleEntries(before cutoff: Date) -> [CacheEntry] {
        entries.filter { !$0.isPinned && $0.lastUsed < cutoff }
    }

    func removing(_ urls: Set<URL>) -> DevItem {
        var copy = self
        copy.entries.removeAll { urls.contains($0.url) }
        copy.size = copy.entries.reduce(0) { $0 + $1.size }
        return copy
    }
}

/// A cleanup that only the tool itself can do safely; the app shows it so the user can run it in Terminal.
struct DevCommand: Identifiable, Sendable {
    let id: String
    let title: String
    let detail: String
    let command: String
    let size: Int64?
}

struct DevScanResult: Sendable {
    var items: [DevCategory: [DevItem]] = [:]
    var commands: [DevCommand] = []
}

/// Measures size and last use (access or modification time) without reading file contents,
/// so measuring never makes something look used.
enum UsageMeter {
    private static let keys: Set<URLResourceKey> = [
        .isRegularFileKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey,
        .contentAccessDateKey, .contentModificationDateKey,
    ]

    static func measure(_ url: URL) -> (size: Int64, lastUsed: Date) {
        var size: Int64 = 0
        var times: [TimeInterval] = []
        func add(_ values: URLResourceValues) {
            size += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
            let accessed = values.contentAccessDate ?? .distantPast
            let modified = values.contentModificationDate ?? .distantPast
            times.append(max(accessed, modified).timeIntervalSinceReferenceDate)
        }
        if let values = try? url.resourceValues(forKeys: keys), values.isRegularFile == true {
            add(values)
        } else if let enumerator = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: Array(keys), options: [], errorHandler: { _, _ in true }
        ) {
            enumerator.forEachURL { file in
                if Task.isCancelled { return false }
                if let values = try? file.resourceValues(forKeys: keys), values.isRegularFile == true { add(values) }
                return true
            }
        }
        return (size, lastUsed(from: times))
    }

    /// A build reads many files at once, while Spotlight or a security scanner touches a stray few.
    /// So the "last use" is the time by which the newest 2% of files (at most 20) had been read,
    /// which ignores a handful of stray reads but still catches any real build.
    private static func lastUsed(from times: [TimeInterval]) -> Date {
        guard !times.isEmpty else { return .distantPast }
        let rank = max(1, min(20, times.count / 50))
        let newest = times.sorted(by: >)
        return Date(timeIntervalSinceReferenceDate: newest[rank - 1])
    }

    static func entry(_ url: URL, pinned: Bool = false) -> CacheEntry? {
        let usage = measure(url)
        guard usage.size > 0 else { return nil }
        return CacheEntry(url: url, size: usage.size, lastUsed: usage.lastUsed, isPinned: pinned)
    }

    /// Items exactly `depth` levels below `folder` (1 = direct children).
    static func items(in folder: URL, depth: Int) -> [URL] {
        var level = [folder]
        for _ in 0..<depth {
            level = level.flatMap { dir in
                (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
            }
        }
        return level
    }
}

struct DeveloperScanner: Sendable {
    /// Build or dependency folders, recognised only when the project's manifest sits next to them.
    private static let artifacts: [(folder: String, manifest: String, tool: String)] = [
        ("node_modules", "package.json", "Node.js"),
        ("Pods", "Podfile", "CocoaPods"),
        (".build", "Package.swift", "Swift Package"),
        ("target", "Cargo.toml", "Rust"),
    ]
    /// A project counts as active when it was built within this window; its Gradle version stays pinned.
    private static let activeProjectWindow: TimeInterval = 90 * 24 * 60 * 60
    private static let jetBrainsIDEs = ["com.google.android.studio", "com.jetbrains.intellij", "com.jetbrains.intellij.ce"]
    private static let walkKeys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .contentModificationDateKey]

    /// Days a project dependency folder may go unused before it is preselected.
    var staleDays: Int

    func scan(progress: @Sendable (Int) -> Void) -> DevScanResult {
        var result = DevScanResult()
        let walk = walkProjects(progress: progress)
        if Task.isCancelled { return DevScanResult() }
        result.items[.projects] = walk.artifacts
        result.items[.packageCaches] = caches(activeGradleVersions: walk.activeGradleVersions)
        result.items[.simulators] = Simulators.items()
        result.items[.xcodeArchives] = xcodeArchives()
        result.commands = commands()
        return result
    }

    // MARK: Projects

    private func walkProjects(progress: @Sendable (Int) -> Void) -> (artifacts: [DevItem], activeGradleVersions: Set<String>) {
        let home = URL.homeDirectory
        let library = home.appending(path: "Library").standardizedFileURL.path
        let artifactNames = Set(Self.artifacts.map(\.folder))
        let cutoff = Date().addingTimeInterval(-Double(staleDays) * 24 * 60 * 60)
        guard let enumerator = FileManager.default.enumerator(
            at: home, includingPropertiesForKeys: Self.walkKeys,
            options: [.skipsPackageDescendants], errorHandler: { _, _ in true }
        ) else { return ([], []) }

        var found: [DevItem] = []
        var gradleVersions = Set<String>()
        var visited = 0
        var cancelled = false
        enumerator.forEachURL { url in
            if Task.isCancelled { cancelled = true; return false }
            visited += 1
            if visited % 1_500 == 0 { progress(visited) }

            let name = url.lastPathComponent
            guard let values = try? url.resourceValues(forKeys: Set(Self.walkKeys)), values.isSymbolicLink != true else { return true }
            if values.isDirectory != true {
                if name == "gradle-wrapper.properties", let version = activeGradleVersion(wrapper: url) {
                    gradleVersions.insert(version)
                }
                return true
            }
            if url.standardizedFileURL.path == library {
                enumerator.skipDescendants()
                return true
            }
            // Hidden folders (.git, .Trash, caches…) are skipped, except SwiftPM's .build.
            if name.hasPrefix("."), !artifactNames.contains(name) {
                enumerator.skipDescendants()
                return true
            }
            guard let artifact = Self.artifacts.first(where: { $0.folder == name }) else { return true }
            enumerator.skipDescendants()
            let project = url.deletingLastPathComponent()
            guard FileManager.default.fileExists(atPath: project.appending(path: artifact.manifest).path) else { return true }

            let usage = UsageMeter.measure(url)
            guard usage.size > 0 else { return true }
            found.append(DevItem(
                url: url,
                size: usage.size,
                title: project.lastPathComponent,
                tool: "\(artifact.tool) · \(name)",
                lastUsed: usage.lastUsed,
                selectedByDefault: usage.lastUsed < cutoff
            ))
            return true
        }
        if cancelled { return ([], []) }
        progress(visited)
        return (found.sorted { $0.size > $1.size }, gradleVersions)
    }

    /// The Gradle version a project's wrapper asks for, if that project was built recently.
    /// Gradle rewrites `<project>/.gradle` on every build, which makes it a good "last built" signal.
    private func activeGradleVersion(wrapper: URL) -> String? {
        let project = wrapper.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let marker = project.appending(path: ".gradle")
        let lastBuilt = (try? marker.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
            ?? (try? wrapper.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
        guard let lastBuilt, Date().timeIntervalSince(lastBuilt) < Self.activeProjectWindow,
              let text = try? String(contentsOf: wrapper, encoding: .utf8),
              let match = text.firstMatch(of: /gradle-([0-9][0-9A-Za-z.\-]*?)-(bin|all)\.zip/) else { return nil }
        return String(match.1)
    }

    // MARK: Package caches

    private func caches(activeGradleVersions: Set<String>) -> [DevItem] {
        var items: [DevItem] = []
        items += gradle(activeVersions: activeGradleVersions)
        items += smartCache(tool: "npm", path: ".npm/_cacache") { root in
            UsageMeter.items(in: root.appending(path: "content-v2"), depth: 4)
        }
        items += smartCache(tool: "Yarn", path: ".yarn/berry/cache") { UsageMeter.items(in: $0, depth: 1) }
        items += smartCache(tool: "Bun", path: ".bun/install/cache") { UsageMeter.items(in: $0, depth: 1) }
        items += smartCache(tool: "Cargo", path: ".cargo/registry/cache") { UsageMeter.items(in: $0, depth: 2) }
        items += smartCache(tool: "Dart / Flutter", path: ".pub-cache/hosted") { UsageMeter.items(in: $0, depth: 2) }
        items += smartCache(tool: "Maven", path: ".m2/repository", lockedBy: Self.jetBrainsIDEs) { mavenVersions(in: $0) }
        items += smartCache(tool: "Android", path: ".android/cache") { UsageMeter.items(in: $0, depth: 1) }
        return items.sorted { $0.size > $1.size }
    }

    private func smartCache(tool: String, path: String, lockedBy: [String] = [],
                            entries list: (URL) -> [URL]) -> [DevItem] {
        let root = URL.homeDirectory.appending(path: path)
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        let entries = list(root).compactMap { UsageMeter.entry($0) }
        guard !entries.isEmpty else { return [] }
        return [DevItem(
            url: root, size: entries.reduce(0) { $0 + $1.size }, title: tool, tool: "~/\(path)",
            lastUsed: entries.map(\.lastUsed).max(), lockingBundleIDs: lockedBy, entries: entries, isSmart: true
        )]
    }

    /// Maven keeps each version in `group/…/artifact/version/`; a folder holding a .pom is one version.
    private func mavenVersions(in root: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return [] }
        var versions: [URL] = []
        enumerator.forEachURL { url in
            if url.pathExtension == "pom" { versions.append(url.deletingLastPathComponent()) }
            return true
        }
        return Array(Set(versions))
    }

    private func gradle(activeVersions: Set<String>) -> [DevItem] {
        let root = URL.homeDirectory.appending(path: ".gradle")
        let caches = root.appending(path: "caches")
        guard FileManager.default.fileExists(atPath: caches.path) else { return [] }
        let fm = FileManager.default
        var urls: [(url: URL, version: String?)] = []

        // Downloaded libraries: group/artifact/version.
        urls += UsageMeter.items(in: caches.appending(path: "modules-2/files-2.1"), depth: 3).map { ($0, nil) }
        // Build cache and dependency transforms: one entry per file or hash folder.
        let cacheFolders = (try? fm.contentsOfDirectory(atPath: caches.path)) ?? []
        for folder in cacheFolders where folder.hasPrefix("build-cache-") || folder.hasPrefix("transforms-") {
            urls += UsageMeter.items(in: caches.appending(path: folder), depth: 1)
                .filter { !["lock", "properties"].contains($0.pathExtension) }
                .map { ($0, nil) }
        }
        // Per-Gradle-version caches and wrapper downloads, pinned while a recently built project uses them.
        for folder in cacheFolders where folder.first?.isNumber == true {
            urls.append((caches.appending(path: folder), folder))
        }
        for dist in UsageMeter.items(in: root.appending(path: "wrapper/dists"), depth: 1) {
            let version = dist.lastPathComponent
                .replacingOccurrences(of: "gradle-", with: "")
                .replacingOccurrences(of: #"-(bin|all)$"#, with: "", options: .regularExpression)
            urls.append((dist, version))
        }

        let entries = urls.compactMap { pair in
            UsageMeter.entry(pair.url, pinned: pair.version.map(activeVersions.contains) ?? false)
        }
        var items: [DevItem] = []
        if !entries.isEmpty {
            items.append(DevItem(
                url: root, size: entries.reduce(0) { $0 + $1.size }, title: "Gradle", tool: "~/.gradle",
                lastUsed: entries.map(\.lastUsed).max(), lockingBundleIDs: Self.jetBrainsIDEs, entries: entries, isSmart: true
            ))
        }

        // Folders Gradle never reads, such as a hand-made `files-backup`, are offered separately.
        let modules = caches.appending(path: "modules-2")
        for folder in UsageMeter.items(in: modules, depth: 1) {
            let name = folder.lastPathComponent
            let isGradle = name == "files-2.1" || name.hasPrefix("metadata-") || name.hasPrefix("resources-") || folder.pathExtension == "lock"
            guard !isGradle else { continue }
            let usage = UsageMeter.measure(folder)
            guard usage.size > 0 else { continue }
            items.append(DevItem(
                url: folder, size: usage.size, title: name, tool: "Gradle · modules-2",
                lastUsed: usage.lastUsed, selectedByDefault: false,
                note: L("Bukan folder yang dipakai Gradle, kemungkinan salinan cadangan manual. Periksa dulu sebelum dihapus.",
                        "Not a folder Gradle uses, probably a manual backup copy. Check it before removing.")
            ))
        }
        return items
    }

    // MARK: Xcode

    private func xcodeArchives() -> [DevItem] {
        let root = URL.homeDirectory.appending(path: "Library/Developer/Xcode/Archives")
        return UsageMeter.items(in: root, depth: 2)
            .filter { $0.pathExtension == "xcarchive" }
            .map { archive in
                let usage = UsageMeter.measure(archive)
                return DevItem(url: archive, size: usage.size, title: archive.deletingPathExtension().lastPathComponent,
                               tool: "Xcode", lastUsed: usage.lastUsed, selectedByDefault: false)
            }
            .sorted { $0.size > $1.size }
    }

    // MARK: Terminal commands

    private func commands() -> [DevCommand] {
        let fm = FileManager.default
        func exists(_ paths: String...) -> Bool { paths.contains { fm.fileExists(atPath: $0) } }
        var commands: [DevCommand] = []

        if exists("/opt/homebrew/bin/brew", "/usr/local/bin/brew") {
            commands.append(DevCommand(
                id: "brew", title: "Homebrew",
                detail: L("Menghapus versi lama paket dan unduhan Homebrew.", "Removes old package versions and Homebrew downloads."),
                command: "brew cleanup --prune=all", size: nil
            ))
        }
        // Docker has its own card, which cleans through the Docker CLI by age.
        let goModules = URL.homeDirectory.appending(path: "go/pkg/mod")
        if fm.fileExists(atPath: goModules.path) {
            commands.append(DevCommand(
                id: "go", title: L("Modul Go", "Go Modules"),
                detail: L("Cache modul Go bersifat read-only, jadi hanya bisa dibersihkan lewat perintah Go.",
                          "The Go module cache is read-only, so only the Go tool can clean it."),
                command: "go clean -modcache", size: FileSizer.allocatedSize(of: goModules)
            ))
        }
        return commands
    }
}

// MARK: Xcode simulators

/// Something CoreSimulator manages. Its files belong to the simulator service, so they are removed
/// with `simctl` (for good, not to the Trash) instead of being moved away behind its back.
enum SimulatorTarget: Hashable, Sendable {
    case runtime(identifier: String)
    case device(udid: String)
}

enum Simulators {
    static let simulatorAppID = "com.apple.iphonesimulator"

    /// `simctl` from the selected Xcode, called directly: going through `xcrun` on a Mac without Xcode
    /// would pop up the "install developer tools" dialog.
    static var simctl: String? {
        let selected = StartupScanner.run("/usr/bin/xcode-select", ["-p"])?.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidates = [selected, "/Applications/Xcode.app/Contents/Developer"].compactMap { $0 }
        return candidates.map { $0 + "/usr/bin/simctl" }.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static func items() -> [DevItem] {
        guard let simctl else { return [] }
        let runtimes = StartupScanner.run(simctl, ["runtime", "list", "-j"]).map { parseRuntimes(Data($0.utf8)) } ?? []
        let devices = StartupScanner.run(simctl, ["list", "devices", "-j"]).map { parseDevices(Data($0.utf8)) } ?? []
        return runtimes + devices
    }

    private static func date(_ value: Any?) -> Date? {
        (value as? String).flatMap { try? Date($0, strategy: .iso8601) }
    }

    private static func platform(_ identifier: String) -> String {
        switch identifier {
        case let id where id.contains("iphone"): "iOS"
        case let id where id.contains("watch"): "watchOS"
        case let id where id.contains("appletv"): "tvOS"
        case let id where id.contains("xr"): "visionOS"
        default: "Simulator"
        }
    }

    /// `simctl runtime list -j`: one entry per downloaded runtime image. The newest runtime of each
    /// platform is never preselected, since that is the one new projects build against.
    static func parseRuntimes(_ data: Data) -> [DevItem] {
        guard let list = (try? JSONSerialization.jsonObject(with: data)) as? [String: [String: Any]] else { return [] }
        let entries = list.values.compactMap { entry -> (item: DevItem, platform: String, version: AppVersion?)? in
            guard let identifier = entry["identifier"] as? String, entry["deletable"] as? Bool != false,
                  let path = entry["path"] as? String else { return nil }
            let platform = platform(entry["platformIdentifier"] as? String ?? "")
            let version = entry["version"] as? String ?? "?"
            let build = entry["build"] as? String
            let item = DevItem(
                url: URL(filePath: path), size: (entry["sizeBytes"] as? NSNumber)?.int64Value ?? 0,
                title: L("Runtime \(platform) \(version)", "\(platform) \(version) runtime") + (build.map { " (\($0))" } ?? ""),
                tool: "Simulator", lastUsed: date(entry["lastUsedAt"]),
                lockingBundleIDs: [simulatorAppID], simulator: .runtime(identifier: identifier))
            return (item, platform, AppVersion(version))
        }
        var newest: [String: AppVersion] = [:]
        for entry in entries {
            if let version = entry.version, newest[entry.platform].map({ $0 < version }) ?? true { newest[entry.platform] = version }
        }
        return entries.map { entry in
            var item = entry.item
            item.selectedByDefault = entry.version.map { $0 < newest[entry.platform]! } ?? false
            return item
        }
        .sorted { $0.size > $1.size }
    }

    /// `simctl list devices -j`: devices grouped by runtime. Ones whose runtime is gone can't boot
    /// any more, so they are preselected; the rest hold apps and data and stay opt-in.
    static func parseDevices(_ data: Data) -> [DevItem] {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let groups = root["devices"] as? [String: [[String: Any]]] else { return [] }
        return groups.flatMap { runtime, devices in
            devices.compactMap { device -> DevItem? in
                guard let udid = device["udid"] as? String, let dataPath = device["dataPath"] as? String,
                      device["state"] as? String != "Booted" else { return nil }
                let folder = URL(filePath: dataPath).deletingLastPathComponent()
                let available = device["isAvailable"] as? Bool ?? true
                let version = runtime.split(separator: ".").last.map {
                    $0.split(separator: "-").dropFirst().joined(separator: ".")
                } ?? ""
                let os = runtime.split(separator: ".").last?.split(separator: "-").first.map(String.init) ?? ""
                let size = (device["dataPathSize"] as? NSNumber)?.int64Value ?? FileSizer.allocatedSize(of: folder)
                var item = DevItem(
                    url: folder, size: size, title: "\(device["name"] as? String ?? udid) · \(os) \(version)",
                    tool: L("Simulator", "Simulator"), lastUsed: date(device["lastUsedAt"] ?? device["lastBootedAt"]),
                    selectedByDefault: !available, lockingBundleIDs: [simulatorAppID], simulator: .device(udid: udid))
                if !available { item.note = L("Runtime-nya sudah tidak terpasang, simulator ini tidak bisa dijalankan.",
                                               "Its runtime is no longer installed, so this simulator can't run.") }
                return item
            }
        }
        .filter { $0.size > 0 }
        .sorted { $0.size > $1.size }
    }

    static func remove(_ target: SimulatorTarget) -> Bool {
        guard let simctl else { return false }
        switch target {
        case .runtime(let identifier): return StartupScanner.run(simctl, ["runtime", "delete", identifier], timeout: 600) != nil
        case .device(let udid): return StartupScanner.run(simctl, ["delete", udid], timeout: 300) != nil
        }
    }
}
