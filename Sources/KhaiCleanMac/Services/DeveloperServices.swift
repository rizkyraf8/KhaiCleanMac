import AppKit
import SwiftUI

enum DevCategory: String, CaseIterable, Identifiable, Sendable {
    case projects, packageCaches, xcodeArchives

    var id: String { rawValue }

    var title: String {
        switch self {
        case .projects: L("Dependensi Proyek", "Project Dependencies")
        case .packageCaches: L("Cache Package Manager", "Package Manager Caches")
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
        case .xcodeArchives:
            L("Build yang pernah di-archive. Berisi dSYM untuk membaca laporan crash, jadi tidak dipilih otomatis.",
              "Builds you archived. They hold the dSYMs needed to read crash reports, so none are preselected.")
        }
    }

    var symbol: String {
        switch self {
        case .projects: "shippingbox.fill"
        case .packageCaches: "arrow.down.circle.fill"
        case .xcodeArchives: "archivebox.fill"
        }
    }

    var colors: [Color] {
        switch self {
        case .projects: Palette.leaf
        case .packageCaches: Palette.sky
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
    let size: Int64
    let title: String
    let tool: String
    let lastUsed: Date?
    var selectedByDefault = true
    /// A warning shown under the item, e.g. for folders the tool itself doesn't use.
    var note: String?
    /// Apps that hold this cache open while running; it is locked while one of them is.
    var lockingBundleIDs: [String] = []
    /// Non-empty for caches cleaned entry by entry: only stale entries go, the folder stays.
    var entries: [CacheEntry] = []

    var id: URL { url }
    var isSmart: Bool { !entries.isEmpty }

    func staleEntries(before cutoff: Date) -> [CacheEntry] {
        entries.filter { !$0.isPinned && $0.lastUsed < cutoff }
    }

    func removing(_ urls: Set<URL>) -> DevItem {
        var copy = self
        copy.entries.removeAll { urls.contains($0.url) }
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
            lastUsed: entries.map(\.lastUsed).max(), lockingBundleIDs: lockedBy, entries: entries
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
                lastUsed: entries.map(\.lastUsed).max(), lockingBundleIDs: Self.jetBrainsIDEs, entries: entries
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
        if exists("/Applications/Docker.app", "/usr/local/bin/docker", "/opt/homebrew/bin/docker") {
            let disk = URL.homeDirectory.appending(path: "Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw")
            let size = fm.fileExists(atPath: disk.path) ? FileSizer.allocatedSize(of: disk) : 0
            commands.append(DevCommand(
                id: "docker", title: "Docker",
                detail: L("Menghapus container yang sudah berhenti, image tak terpakai, dan build cache. Jalankan saat Docker menyala.",
                          "Removes stopped containers, unused images and build cache. Run it while Docker is running."),
                command: "docker system prune", size: size > 0 ? size : nil
            ))
        }
        let simulators = URL.homeDirectory.appending(path: "Library/Developer/CoreSimulator/Devices")
        if exists("/usr/bin/xcrun"), fm.fileExists(atPath: simulators.path) {
            commands.append(DevCommand(
                id: "simctl", title: L("Simulator iOS", "iOS Simulators"),
                detail: L("Menghapus simulator untuk versi iOS yang sudah tidak terpasang.", "Removes simulators for iOS versions that are no longer installed."),
                command: "xcrun simctl delete unavailable", size: nil
            ))
        }
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
