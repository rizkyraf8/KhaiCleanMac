import Foundation

/// An installed Chrome version that Chrome itself will remove once it relaunches.
struct ChromeUpdateInfo: Sendable {
    /// Framework versions other than the one `Current` points to.
    let oldVersions: [String]
    let oldVersionsSize: Int64
    /// Leftover Google Updater versions in the system Library (root-owned, so admin-only).
    let updaterLeftovers: Int

    var hasOldVersions: Bool { !oldVersions.isEmpty }
}

/// Finds only the parts of Chrome's caches that are no longer useful, instead of the whole folder:
/// - web (HTTP) cache entries not used for a while,
/// - V8 code cache entries made by an older Chrome version, which V8 always rejects,
/// - temp folders left behind by headless Chrome (Puppeteer and similar tools).
///
/// Chrome's caches use the "simple cache" layout: one entry is a set of files named
/// `<16 hex>_0`, `_1` and `_s`, next to index files. Entries are removed as whole sets and
/// index files are left alone; Chrome treats a missing entry as a cache miss and fixes its index.
struct ChromeCacheScanner: Sendable {
    static let bundleID = "com.google.Chrome"
    static let cacheRoot = URL.homeDirectory.appending(path: "Library/Caches/Google/Chrome")
    static let headlessRoot = URL.homeDirectory.appending(path: "Library/Caches/Google/Chrome-headless")

    private static let codeCacheFolders = ["js", "wasm", "webui_js"]
    private static let entryKeys: Set<URLResourceKey> = [
        .contentAccessDateKey, .contentModificationDateKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey,
    ]

    let maxAgeDays: Int
    var now = Date()

    func scan() -> [CleanItem] {
        var items: [CleanItem] = []
        let codeCacheCutoff = Self.currentVersionInstallDate()
        for profile in Self.profiles() {
            if let item = staleWebCache(in: profile) { items.append(item) }
            if let cutoff = codeCacheCutoff, let item = obsoleteCodeCache(in: profile, madeBefore: cutoff) { items.append(item) }
        }
        if let item = headlessLeftovers() { items.append(item) }
        return items
    }

    // MARK: Web cache

    private func staleWebCache(in profile: URL) -> CleanItem? {
        let folder = profile.appending(path: "Cache/Cache_Data")
        let cutoff = now.addingTimeInterval(-Double(maxAgeDays) * 24 * 60 * 60)
        let stale = Self.entries(in: folder).filter { $0.lastUsed < cutoff }
        guard !stale.isEmpty else { return nil }
        return CleanItem(
            url: folder,
            size: stale.reduce(0) { $0 + $1.size },
            title: L("Cache web lama · \(Self.displayName(of: profile))", "Old web cache · \(Self.displayName(of: profile))"),
            detail: L("\(stale.count.formatted()) entri tidak dipakai lebih dari \(maxAgeDays) hari",
                      "\(stale.count.formatted()) entries unused for over \(maxAgeDays) days"),
            members: stale.flatMap(\.files)
        )
    }

    // MARK: Code cache

    private func obsoleteCodeCache(in profile: URL, madeBefore cutoff: Date) -> CleanItem? {
        let folder = profile.appending(path: "Code Cache")
        // An entry is obsolete only if every file of it predates the running version's install.
        let obsolete = Self.codeCacheFolders
            .flatMap { Self.entries(in: folder.appending(path: $0)) }
            .filter { $0.lastWritten < cutoff }
        guard !obsolete.isEmpty else { return nil }
        return CleanItem(
            url: folder,
            size: obsolete.reduce(0) { $0 + $1.size },
            title: L("Code Cache usang · \(Self.displayName(of: profile))", "Obsolete code cache · \(Self.displayName(of: profile))"),
            detail: L("\(obsolete.count.formatted()) entri dari versi Chrome sebelumnya, tidak bisa dipakai lagi",
                      "\(obsolete.count.formatted()) entries from an earlier Chrome version, no longer usable"),
            members: obsolete.flatMap(\.files)
        )
    }

    // MARK: Headless leftovers

    private func headlessLeftovers() -> CleanItem? {
        let cutoff = now.addingTimeInterval(-24 * 60 * 60)
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: Self.headlessRoot, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        // A folder touched in the last day may belong to an automation run that is still going.
        let leftovers = urls.filter { url in
            guard url.lastPathComponent.hasPrefix("scoped_dir") else { return false }
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantFuture
            return modified < cutoff
        }
        guard !leftovers.isEmpty else { return nil }
        return CleanItem(
            url: Self.headlessRoot,
            size: leftovers.reduce(0) { $0 + FileSizer.allocatedSize(of: $1) },
            title: L("Sisa Chrome headless", "Headless Chrome leftovers"),
            detail: L("\(leftovers.count) folder sementara dari otomasi browser", "\(leftovers.count) temp folders from browser automation"),
            members: leftovers
        )
    }

    // MARK: Simple cache entries

    private struct Entry {
        var files: [URL] = []
        var size: Int64 = 0
        var lastUsed = Date.distantPast
        var lastWritten = Date.distantPast
    }

    /// Groups `<16 hex>_0`, `_1` and `_s` files into entries; index files never match.
    private static func entries(in folder: URL) -> [Entry] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: Array(entryKeys))) ?? []
        var entries: [Substring: Entry] = [:]
        for url in urls { autoreleasepool {
            let name = url.lastPathComponent
            guard let key = entryKey(name) else { return }
            let values = try? url.resourceValues(forKeys: entryKeys)
            let written = values?.contentModificationDate ?? .distantPast
            let read = values?.contentAccessDate ?? .distantPast
            var entry = entries[key, default: Entry()]
            entry.files.append(url)
            entry.size += Int64(values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? 0)
            entry.lastWritten = max(entry.lastWritten, written)
            entry.lastUsed = max(entry.lastUsed, written, read)
            entries[key] = entry
        } }
        return Array(entries.values)
    }

    private static func entryKey(_ name: String) -> Substring? {
        let parts = name.split(separator: "_")
        guard parts.count == 2, parts[0].count == 16, ["0", "1", "s"].contains(parts[1]),
              parts[0].allSatisfy(\.isHexDigit) else { return nil }
        return parts[0]
    }

    // MARK: Chrome install

    static func profiles() -> [URL] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: cacheRoot, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
        return urls.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
    }

    private static func displayName(of profile: URL) -> String {
        profile.lastPathComponent == "Default" ? L("Profil utama", "Main profile") : profile.lastPathComponent
    }

    private static var frameworkVersions: URL? {
        let candidates = [URL(filePath: "/Applications"), URL.homeDirectory.appending(path: "Applications")]
        return candidates
            .map { $0.appending(path: "Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Versions") }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// When the version Chrome launches next was installed. Code cache written before then
    /// came from an older V8 and is rejected. Smart Scan only cleans Chrome while it is closed,
    /// so the next launch always runs `Current`.
    private static func currentVersionInstallDate() -> Date? {
        guard let versions = frameworkVersions else { return nil }
        let current = versions.appending(path: "Current").resolvingSymlinksInPath()
        let values = try? current.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
        return values?.creationDate ?? values?.contentModificationDate
    }

    /// Old versions inside Chrome.app are never removed here: while Chrome waits for a relaunch,
    /// the "old" one is the version actually running. Chrome deletes it itself after relaunching.
    static func updateInfo() -> ChromeUpdateInfo? {
        guard let versions = frameworkVersions else { return nil }
        let current = versions.appending(path: "Current").resolvingSymlinksInPath().lastPathComponent
        let names = (try? FileManager.default.contentsOfDirectory(atPath: versions.path)) ?? []
        let old = names.filter { $0 != "Current" && $0 != current && $0.first?.isNumber == true }.sorted()
        let size = old.reduce(Int64(0)) { $0 + FileSizer.allocatedSize(of: versions.appending(path: $1)) }

        let updater = URL(filePath: "/Library/Application Support/Google/GoogleUpdater")
        let updaterCurrent = updater.appending(path: "Current").resolvingSymlinksInPath().lastPathComponent
        let updaterNames = (try? FileManager.default.contentsOfDirectory(atPath: updater.path)) ?? []
        let updaterOld = updaterNames.filter { $0 != "Current" && $0 != updaterCurrent && $0.first?.isNumber == true }

        guard !old.isEmpty || !updaterOld.isEmpty else { return nil }
        return ChromeUpdateInfo(oldVersions: old, oldVersionsSize: size, updaterLeftovers: updaterOld.count)
    }
}
