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

/// A browser whose cache Smart Scan cleans entry by entry.
struct Browser: Sendable {
    enum Layout: Sendable {
        /// Chrome, Brave, Edge, Arc, Vivaldi: per-profile "simple cache" folders.
        case chromium
        /// Firefox: one file per entry in `<profile>/cache2/entries`.
        case firefox
        /// Safari: WebKit's network cache, one file per record or blob.
        case safari
    }

    let name: String
    let bundleIDs: [String]
    let layout: Layout
    /// Folders under the home folder that hold the cache.
    let cachePaths: [String]
    /// App bundle names, used to find the installed Chromium version.
    let appNames: [String]

    static let chrome = Browser(name: "Chrome", bundleIDs: ["com.google.Chrome"], layout: .chromium,
                                cachePaths: ["Library/Caches/Google/Chrome"], appNames: ["Google Chrome"])

    static let all: [Browser] = [
        chrome,
        Browser(name: "Brave", bundleIDs: ["com.brave.Browser"], layout: .chromium,
                cachePaths: ["Library/Caches/BraveSoftware/Brave-Browser"], appNames: ["Brave Browser"]),
        Browser(name: "Edge", bundleIDs: ["com.microsoft.edgemac"], layout: .chromium,
                cachePaths: ["Library/Caches/Microsoft Edge"], appNames: ["Microsoft Edge"]),
        Browser(name: "Arc", bundleIDs: ["company.thebrowser.Browser"], layout: .chromium,
                cachePaths: ["Library/Caches/Arc"], appNames: ["Arc"]),
        Browser(name: "Vivaldi", bundleIDs: ["com.vivaldi.Vivaldi"], layout: .chromium,
                cachePaths: ["Library/Caches/Vivaldi"], appNames: ["Vivaldi"]),
        Browser(name: "Firefox", bundleIDs: ["org.mozilla.firefox", "org.mozilla.firefoxdeveloperedition", "org.mozilla.nightly"],
                layout: .firefox, cachePaths: ["Library/Caches/Firefox/Profiles"], appNames: []),
        Browser(name: "Safari", bundleIDs: ["com.apple.Safari"], layout: .safari,
                cachePaths: ["Library/Containers/com.apple.Safari/Data/Library/Caches/com.apple.Safari/WebKitCache",
                             "Library/Caches/com.apple.Safari/WebKitCache"], appNames: []),
    ]

    /// Folders in ~/Library/Caches handled by the browser category, so App Caches leaves them out.
    static let ownedCacheFolders: Set<String> = [
        "Google/Chrome", "Google/Chrome-headless", "BraveSoftware/Brave-Browser",
        "Microsoft Edge", "Arc", "Vivaldi", "Firefox", "com.apple.Safari",
    ]

    /// The browser whose cache folder holds `url`, so its items stay locked while it runs.
    static func owning(_ url: URL, home: URL = .homeDirectory) -> Browser? {
        all.first { browser in
            browser.cachePaths.contains { cachePath in
                // Compare whole folder names: "Google/Chrome-headless" must not count as "Google/Chrome".
                let root = home.appending(path: cachePath).path
                return url.path == root || url.path.hasPrefix(root + "/")
            }
        }
    }
}

/// Finds only the parts of browser caches that are no longer useful, instead of whole folders:
/// - web cache entries not used for a while (every browser),
/// - Chromium code cache made by an older browser version, which V8 always rejects,
/// - temp folders left behind by headless Chrome (Puppeteer and similar tools).
///
/// Chromium's "simple cache" stores one entry as files named `<16 hex>_0`, `_1` and `_s`, next to
/// index files. Entries are removed as whole sets and index files are left alone; every browser
/// treats a missing entry as a cache miss and fixes its own index.
struct BrowserCacheScanner: Sendable {
    let maxAgeDays: Int
    var home = URL.homeDirectory
    var applicationFolders = [URL(filePath: "/Applications"), URL.homeDirectory.appending(path: "Applications")]
    var now = Date()

    var headlessRoot: URL { home.appending(path: "Library/Caches/Google/Chrome-headless") }
    private var ageCutoff: Date { now.addingTimeInterval(-Double(maxAgeDays) * 24 * 60 * 60) }

    private static let codeCacheFolders = ["js", "wasm", "webui_js"]
    private static let fileKeys: Set<URLResourceKey> = [
        .isRegularFileKey, .contentAccessDateKey, .contentModificationDateKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey,
    ]

    func scan() -> [CleanItem] {
        Browser.all.flatMap(scan) + [headlessLeftovers()].compactMap { $0 }
    }

    func scan(_ browser: Browser) -> [CleanItem] {
        let roots = browser.cachePaths.map { home.appending(path: $0) }
        switch browser.layout {
        case .chromium:
            let codeCacheCutoff = installDate(of: browser)
            return roots.flatMap(chromiumProfiles).flatMap { profile in
                [
                    staleWebCache(browser, profile: profile),
                    obsoleteCodeCache(browser, profile: profile, madeBefore: codeCacheCutoff),
                ].compactMap { $0 }
            }
        case .firefox:
            return roots.flatMap(Self.subfolders).compactMap { profile in
                staleFiles(browser, folder: profile.appending(path: "cache2/entries"),
                           profileName: profile.lastPathComponent, recursive: false)
            }
        case .safari:
            guard let root = roots.first(where: { FileManager.default.fileExists(atPath: $0.path) }) else { return [] }
            return [staleFiles(browser, folder: root, profileName: nil, recursive: true)].compactMap { $0 }
        }
    }

    // MARK: Chromium

    /// Profile folders are `Default`, `Profile 1`… either at the root or inside `User Data` (Arc).
    private func chromiumProfiles(in root: URL) -> [URL] {
        let candidates = Self.subfolders(of: root) + Self.subfolders(of: root.appending(path: "User Data"))
        return candidates.filter { profile in
            ["Cache/Cache_Data", "Code Cache"].contains { FileManager.default.fileExists(atPath: profile.appending(path: $0).path) }
        }
    }

    private func staleWebCache(_ browser: Browser, profile: URL) -> CleanItem? {
        let folder = profile.appending(path: "Cache/Cache_Data")
        let stale = Self.simpleCacheEntries(in: folder).filter { $0.lastUsed < ageCutoff }
        guard !stale.isEmpty else { return nil }
        let name = Self.label(browser, profile: profile.lastPathComponent)
        return CleanItem(
            url: folder,
            size: stale.reduce(0) { $0 + $1.size },
            title: L("Cache web lama · \(name)", "Old web cache · \(name)"),
            detail: L("\(stale.count.formatted()) entri tidak dipakai lebih dari \(maxAgeDays) hari",
                      "\(stale.count.formatted()) entries unused for over \(maxAgeDays) days"),
            members: stale.flatMap(\.files)
        )
    }

    /// With a known install date, an entry is obsolete when every file of it predates that install.
    /// Without one (an unusual app layout), unused code cache simply ages out like web cache.
    private func obsoleteCodeCache(_ browser: Browser, profile: URL, madeBefore installDate: Date?) -> CleanItem? {
        let folder = profile.appending(path: "Code Cache")
        let entries = Self.codeCacheFolders.flatMap { Self.simpleCacheEntries(in: folder.appending(path: $0)) }
        let obsolete = entries.filter { entry in
            if let installDate { return entry.lastWritten < installDate }
            return entry.lastUsed < ageCutoff
        }
        guard !obsolete.isEmpty else { return nil }
        let name = Self.label(browser, profile: profile.lastPathComponent)
        return CleanItem(
            url: folder,
            size: obsolete.reduce(0) { $0 + $1.size },
            title: L("Code Cache usang · \(name)", "Obsolete code cache · \(name)"),
            detail: installDate == nil
                ? L("\(obsolete.count.formatted()) entri tidak dipakai lebih dari \(maxAgeDays) hari",
                    "\(obsolete.count.formatted()) entries unused for over \(maxAgeDays) days")
                : L("\(obsolete.count.formatted()) entri dari versi \(browser.name) sebelumnya, tidak bisa dipakai lagi",
                    "\(obsolete.count.formatted()) entries from an earlier \(browser.name) version, no longer usable"),
            members: obsolete.flatMap(\.files)
        )
    }

    struct Entry {
        var files: [URL] = []
        var size: Int64 = 0
        var lastUsed = Date.distantPast
        var lastWritten = Date.distantPast
    }

    /// Groups `<16 hex>_0`, `_1` and `_s` files into entries; index files never match.
    static func simpleCacheEntries(in folder: URL) -> [Entry] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: Array(fileKeys))) ?? []
        var entries: [Substring: Entry] = [:]
        for url in urls { autoreleasepool {
            guard let key = entryKey(url.lastPathComponent) else { return }
            let values = try? url.resourceValues(forKeys: fileKeys)
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

    static func entryKey(_ name: String) -> Substring? {
        let parts = name.split(separator: "_")
        guard parts.count == 2, parts[0].count == 16, ["0", "1", "s"].contains(parts[1]),
              parts[0].allSatisfy(\.isHexDigit) else { return nil }
        return parts[0]
    }

    /// When the version the browser launches next was installed. Code cache written before then came
    /// from an older V8 and is rejected. Browser caches are only cleaned while the browser is closed,
    /// so the next launch always runs `Current`.
    func installDate(of browser: Browser) -> Date? {
        guard let versions = frameworkVersions(of: browser) else { return nil }
        let current = versions.appending(path: "Current").resolvingSymlinksInPath()
        let values = try? current.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
        return values?.creationDate ?? values?.contentModificationDate
    }

    /// `<App>.app/Contents/Frameworks/<Name> Framework.framework/Versions`; Chromium browsers all use it.
    func frameworkVersions(of browser: Browser) -> URL? {
        for folder in applicationFolders {
            for appName in browser.appNames {
                let frameworks = folder.appending(path: "\(appName).app/Contents/Frameworks")
                let names = (try? FileManager.default.contentsOfDirectory(atPath: frameworks.path)) ?? []
                if let framework = names.first(where: { $0.hasSuffix(" Framework.framework") }) {
                    return frameworks.appending(path: "\(framework)/Versions")
                }
            }
        }
        return nil
    }

    // MARK: One file per entry (Firefox, Safari)

    private func staleFiles(_ browser: Browser, folder: URL, profileName: String?, recursive: Bool) -> CleanItem? {
        var stale: [URL] = []
        var size: Int64 = 0
        func consider(_ url: URL) {
            guard let values = try? url.resourceValues(forKeys: Self.fileKeys), values.isRegularFile == true else { return }
            let lastUsed = max(values.contentAccessDate ?? .distantPast, values.contentModificationDate ?? .distantPast)
            guard lastUsed < ageCutoff else { return }
            stale.append(url)
            size += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        }
        if recursive {
            FileManager.default.enumerator(at: folder, includingPropertiesForKeys: Array(Self.fileKeys), options: [],
                                           errorHandler: { _, _ in true })?
                .forEachURL { url in
                    // WebKit's `salt` file keys the whole cache; losing it would throw everything away.
                    if url.lastPathComponent != "salt" { consider(url) }
                    return !Task.isCancelled
                }
        } else {
            let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: Array(Self.fileKeys))) ?? []
            for url in urls { autoreleasepool { consider(url) } }
        }
        guard !stale.isEmpty else { return nil }
        let name = Self.label(browser, profile: profileName)
        return CleanItem(
            url: folder,
            size: size,
            title: L("Cache web lama · \(name)", "Old web cache · \(name)"),
            detail: L("\(stale.count.formatted()) file tidak dipakai lebih dari \(maxAgeDays) hari",
                      "\(stale.count.formatted()) files unused for over \(maxAgeDays) days"),
            members: stale
        )
    }

    // MARK: Headless leftovers

    func headlessLeftovers() -> CleanItem? {
        let cutoff = now.addingTimeInterval(-24 * 60 * 60)
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: headlessRoot, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        // A folder touched in the last day may belong to an automation run that is still going.
        let leftovers = urls.filter { url in
            guard url.lastPathComponent.hasPrefix("scoped_dir") else { return false }
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantFuture
            return modified < cutoff
        }
        guard !leftovers.isEmpty else { return nil }
        return CleanItem(
            url: headlessRoot,
            size: leftovers.reduce(0) { $0 + FileSizer.allocatedSize(of: $1) },
            title: L("Sisa Chrome headless", "Headless Chrome leftovers"),
            detail: L("\(leftovers.count) folder sementara dari otomasi browser", "\(leftovers.count) temp folders from browser automation"),
            members: leftovers
        )
    }

    // MARK: Helpers

    private static func subfolders(of folder: URL) -> [URL] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
        return urls.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
    }

    /// "Chrome" for the default profile, "Chrome · Profile 3" otherwise.
    private static func label(_ browser: Browser, profile: String?) -> String {
        guard let profile, profile != "Default" else { return browser.name }
        // Firefox profile folders look like "abcd1234.default-release"; the part after the dot is the name.
        let readable = profile.split(separator: ".", maxSplits: 1).last.map(String.init) ?? profile
        return "\(browser.name) · \(readable)"
    }

    // MARK: Chrome updates

    /// Old versions inside Chrome.app are never removed here: while Chrome waits for a relaunch,
    /// the "old" one is the version actually running. Chrome deletes it itself after relaunching.
    func chromeUpdateInfo() -> ChromeUpdateInfo? {
        guard let versions = frameworkVersions(of: .chrome) else { return nil }
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
