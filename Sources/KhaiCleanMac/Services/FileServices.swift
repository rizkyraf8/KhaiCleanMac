import AppKit

enum FileSizer {
    private static let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]

    /// On-disk size of a file, or the recursive size of a folder or bundle.
    static func allocatedSize(of url: URL) -> Int64 {
        if let values = try? url.resourceValues(forKeys: keys), values.isRegularFile == true {
            return size(from: values)
        }
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: Array(keys),
            options: [],
            errorHandler: { _, _ in true }
        ) else { return 0 }

        var total: Int64 = 0
        for case let file as URL in enumerator {
            if Task.isCancelled { break }
            if let values = try? file.resourceValues(forKeys: keys), values.isRegularFile == true, values.isSymbolicLink != true {
                total += size(from: values)
            }
        }
        return total
    }

    private static func size(from values: URLResourceValues) -> Int64 {
        Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
    }
}

enum Trasher {
    /// Moves items to the Trash (never deletes permanently), so everything can be put back.
    static func moveToTrash(_ items: [CleanItem]) -> CleanReport {
        var report = CleanReport()
        for item in items {
            do {
                try FileManager.default.trashItem(at: item.url, resultingItemURL: nil)
                report.movedCount += 1
                report.movedSize += item.size
            } catch {
                report.failed.append(item)
            }
        }
        return report
    }
}

struct JunkScanner: Sendable {
    private static let installerExtensions: Set<String> = ["dmg", "pkg", "mpkg", "xip"]
    private static let developerFolders = [
        "Developer/Xcode/DerivedData",
        "Developer/Xcode/iOS DeviceSupport",
        "Developer/Xcode/watchOS DeviceSupport",
        "Developer/Xcode/macOS DeviceSupport",
        "Developer/CoreSimulator/Caches",
    ]

    func scan(_ kind: JunkKind) -> [CleanItem] {
        let items: [CleanItem]
        switch kind {
        case .userCache:
            items = children(of: library("Caches"), excluding: [AppInfo.bundleID])
        case .userLogs:
            items = children(of: library("Logs"))
        case .developer:
            items = Self.developerFolders.flatMap { children(of: library($0)) }
        case .installers:
            items = installers()
        }
        return items.filter { $0.size > 0 }.sorted { $0.size > $1.size }
    }

    private func library(_ subpath: String) -> URL {
        URL.homeDirectory.appending(path: "Library/\(subpath)", directoryHint: .isDirectory)
    }

    private func children(of folder: URL, excluding: Set<String> = []) -> [CleanItem] {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else { return [] }
        return urls
            .filter { !excluding.contains($0.lastPathComponent) }
            .map { CleanItem(url: $0, size: FileSizer.allocatedSize(of: $0)) }
    }

    private func installers() -> [CleanItem] {
        let downloads = URL.downloadsDirectory
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: downloads, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]
        ) else { return [] }
        return urls
            .filter { Self.installerExtensions.contains($0.pathExtension.lowercased()) }
            .map { CleanItem(url: $0, size: FileSizer.allocatedSize(of: $0)) }
    }
}

/// Works out which open app a cache or log entry belongs to, so it is left alone while that app runs.
struct RunningAppMatcher: Sendable {
    struct RunningApp: Sendable {
        let bundleID: String
        let name: String
        /// Dock apps the user can quit; menu-bar agents and system helpers are false.
        let isUserApp: Bool
    }

    let apps: [RunningApp]

    @MainActor
    static func current() -> RunningAppMatcher {
        let apps = NSWorkspace.shared.runningApplications.compactMap { app -> RunningApp? in
            guard app.activationPolicy != .prohibited,
                  let id = app.bundleIdentifier,
                  id != AppInfo.bundleID else { return nil }
            return RunningApp(bundleID: id, name: app.localizedName ?? id, isUserApp: app.activationPolicy == .regular)
        }
        return RunningAppMatcher(apps: apps)
    }

    func owner(of item: CleanItem, kind: JunkKind) -> RunningApp? {
        switch kind {
        case .installers:
            return nil
        case .developer:
            return apps.first { $0.bundleID == "com.apple.dt.Xcode" || $0.bundleID == "com.apple.iphonesimulator" }
        case .userCache, .userLogs:
            let entry = item.name.lowercased()
            return apps.first { matches(entry, $0) }
        }
    }

    private func matches(_ entry: String, _ app: RunningApp) -> Bool {
        let id = app.bundleID.lowercased()
        let name = app.name.lowercased()
        if entry == id || entry.hasPrefix(id + ".") { return true }
        if entry == name || entry == name.replacingOccurrences(of: " ", with: "") { return true }
        // Vendor folders such as "Google" (Chrome, Android Studio) or "Mozilla".
        let parts = id.split(separator: ".")
        if parts.count >= 3, parts[1] != "apple", parts[1].count >= 4, entry == parts[1] { return true }
        return false
    }
}

struct LargeFileScanner: Sendable {
    private static let keys: [URLResourceKey] = [
        .isRegularFileKey, .isSymbolicLinkKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey,
        .contentAccessDateKey, .contentModificationDateKey,
    ]

    /// Walks the home folder (skipping ~/Library, hidden files and package contents).
    func scan(minSize: Int64, progress: @Sendable (Int) -> Void) -> [LargeFile] {
        let home = URL.homeDirectory
        let library = home.appending(path: "Library").standardizedFileURL.path
        guard let enumerator = FileManager.default.enumerator(
            at: home,
            includingPropertiesForKeys: Self.keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { _, _ in true }
        ) else { return [] }

        var found: [LargeFile] = []
        var visited = 0
        for case let url as URL in enumerator {
            if Task.isCancelled { return [] }
            visited += 1
            if visited % 1_500 == 0 { progress(visited) }

            if url.standardizedFileURL.path == library {
                enumerator.skipDescendants()
                continue
            }
            guard let values = try? url.resourceValues(forKeys: Set(Self.keys)),
                  values.isRegularFile == true, values.isSymbolicLink != true else { continue }
            let size = Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
            guard size >= minSize else { continue }
            found.append(LargeFile(
                url: url,
                size: size,
                lastUsed: values.contentAccessDate ?? values.contentModificationDate,
                kind: FileKind(pathExtension: url.pathExtension)
            ))
        }
        progress(visited)
        return found.sorted { $0.size > $1.size }
    }
}

struct AppScanner: Sendable {
    func installedApps() -> [InstalledApp] {
        let roots = [URL(filePath: "/Applications"), URL.homeDirectory.appending(path: "Applications")]
        var seen = Set<String>()
        var apps: [InstalledApp] = []
        for root in roots {
            for url in appBundles(in: root, depth: 2) {
                guard let app = makeApp(url), seen.insert(app.bundleID).inserted else { continue }
                apps.append(app)
            }
        }
        return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Files an app leaves behind in ~/Library, matched by bundle ID or app name.
    func leftovers(for app: InstalledApp) -> [CleanItem] {
        let library = URL.homeDirectory.appending(path: "Library")
        let id = app.bundleID
        var candidates: [URL] = []
        func add(_ subpath: String) { candidates.append(library.appending(path: subpath)) }

        for name in [id] + app.searchNames where name.count >= 3 {
            add("Application Support/\(name)")
            add("Caches/\(name)")
            add("Logs/\(name)")
        }
        add("Preferences/\(id).plist")
        add("Containers/\(id)")
        add("Application Scripts/\(id)")
        add("Saved Application State/\(id).savedState")
        add("HTTPStorages/\(id)")
        add("HTTPStorages/\(id).binarycookies")
        add("WebKit/\(id)")
        add("Cookies/\(id).binarycookies")
        candidates += entries(in: library.appending(path: "Group Containers")) { $0.contains(id) }
        candidates += entries(in: library.appending(path: "LaunchAgents")) { $0.hasPrefix(id) }
        candidates += entries(in: library.appending(path: "Preferences/ByHost")) { $0.hasPrefix(id) }

        var seen = Set<String>()
        return candidates
            .filter { FileManager.default.fileExists(atPath: $0.path) && seen.insert($0.path).inserted }
            .map { CleanItem(url: $0, size: FileSizer.allocatedSize(of: $0)) }
            .sorted { $0.size > $1.size }
    }

    private func entries(in folder: URL, where matches: (String) -> Bool) -> [URL] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return urls.filter { matches($0.lastPathComponent) }
    }

    private func appBundles(in folder: URL, depth: Int) -> [URL] {
        guard depth > 0, let urls = try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
        ) else { return [] }
        return urls.flatMap { url -> [URL] in
            if url.pathExtension == "app" { return [url] }
            let isFolder = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            return isFolder ? appBundles(in: url, depth: depth - 1) : []
        }
    }

    private func makeApp(_ url: URL) -> InstalledApp? {
        guard let bundle = Bundle(url: url),
              let id = bundle.bundleIdentifier,
              !id.hasPrefix("com.apple."),
              id != AppInfo.bundleID else { return nil }
        let info = bundle.infoDictionary ?? [:]
        let fileName = url.deletingPathExtension().lastPathComponent
        let bundleName = info["CFBundleName"] as? String
        return InstalledApp(
            url: url,
            name: fileName,
            bundleID: id,
            version: info["CFBundleShortVersionString"] as? String,
            searchNames: Array(Set([fileName, bundleName].compactMap { $0 }))
        )
    }
}

struct DiskInfo: Sendable {
    let total: Int64
    let available: Int64

    var used: Int64 { total - available }
    var usedFraction: Double { total > 0 ? Double(used) / Double(total) : 0 }

    static func current() -> DiskInfo? {
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        guard let values = try? URL.homeDirectory.resourceValues(forKeys: keys),
              let total = values.volumeTotalCapacity,
              let available = values.volumeAvailableCapacityForImportantUsage else { return nil }
        return DiskInfo(total: Int64(total), available: available)
    }
}

enum Permissions {
    /// Files that only open with Full Disk Access. Not every macOS version has all of them,
    /// so access counts as granted as soon as one of them can actually be read.
    private static let protectedProbes = [
        "/Library/Application Support/com.apple.TCC/TCC.db",
        URL.homeDirectory.appending(path: "Library/Application Support/com.apple.TCC/TCC.db").path,
        URL.homeDirectory.appending(path: "Library/Safari/Bookmarks.plist").path,
        URL.homeDirectory.appending(path: "Library/Safari/CloudTabs.db").path,
    ]

    static var hasFullDiskAccess: Bool {
        protectedProbes.contains { path in
            guard let handle = FileHandle(forReadingAtPath: path) else { return false }
            try? handle.close()
            return true
        }
    }

    @MainActor
    static func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    @MainActor
    static func openTrash() {
        NSWorkspace.shared.open(URL.homeDirectory.appending(path: ".Trash"))
    }
}
