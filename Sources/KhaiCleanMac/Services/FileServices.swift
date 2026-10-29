import AppKit
import Security

extension FileManager.DirectoryEnumerator {
    /// Calls `body` for each URL inside its own autorelease pool. Without one, the Foundation objects
    /// made for every file pile up until the whole walk ends, which is gigabytes on a big home folder.
    /// Return `false` from `body` to stop early.
    func forEachURL(_ body: (URL) -> Bool) {
        while autoreleasepool(invoking: { () -> Bool in
            guard let url = nextObject() as? URL else { return false }
            return body(url)
        }) {}
    }
}

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
        enumerator.forEachURL { file in
            if Task.isCancelled { return false }
            if let values = try? file.resourceValues(forKeys: keys), values.isRegularFile == true, values.isSymbolicLink != true {
                total += size(from: values)
            }
            return true
        }
        return total
    }

    private static func size(from values: URLResourceValues) -> Int64 {
        Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
    }
}

enum Trasher {
    /// Moves a file to the Trash and returns where it ended up there (if known).
    typealias TrashAction = @Sendable (URL) throws -> URL?

    static let systemTrash: TrashAction = { url in
        var resulting: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &resulting)
        return resulting as URL?
    }
    static var defaultStagingRoot: URL {
        URL.homeDirectory.appending(path: "Library/Caches/\(AppInfo.bundleID)/Trash staging")
    }

    /// Removes items the way the user chose in Settings: to the Trash (the default) or for good.
    static func remove(_ items: [CleanItem]) -> CleanReport {
        remove(items, permanently: AppSettings.shared.deletesPermanently)
    }

    /// Always uses the Trash, whatever the setting.
    static func moveToTrash(_ items: [CleanItem]) -> CleanReport {
        remove(items, permanently: false)
    }

    /// `stagingRoot` and `trash` exist so tests can run without touching the real Trash.
    static func remove(
        _ items: [CleanItem],
        permanently: Bool,
        stagingRoot: URL = defaultStagingRoot,
        home: URL = .homeDirectory,
        trash: TrashAction = systemTrash
    ) -> CleanReport {
        var report = CleanReport(permanent: permanently)
        for var item in items {
            // Never trust the caller: protected locations are refused here, whatever picked them.
            if item.members.isEmpty {
                guard SafetyGuard.isAllowed(item.url, home: home) else { report.blocked.append(item); continue }
            } else {
                item.members = item.members.filter { SafetyGuard.isAllowed($0, home: home) }
                guard !item.members.isEmpty else { report.blocked.append(item); continue }
            }
            // nil: failed. Otherwise what History needs to put it back (no Trash location when deleted).
            let record: RemovedItem?
            if permanently || item.removesPermanently {
                record = deletePermanently(item) ? RemovedItem(item, trashedTo: nil, memberPaths: []) : nil
            } else if item.members.isEmpty {
                record = (try? trash(item.url)).map { RemovedItem(item, trashedTo: $0, memberPaths: []) }
            } else {
                record = trashMembers(of: item, stagingRoot: stagingRoot, trash: trash, kept: &report.keptInStaging)
                    .map { RemovedItem(item, trashedTo: $0.folder, memberPaths: $0.relativePaths) }
            }
            if let record {
                report.movedCount += 1
                report.movedSize += item.size
                report.removed.append(record)
            } else {
                report.failed.append(item)
            }
        }
        return report
    }

    private static func deletePermanently(_ item: CleanItem) -> Bool {
        let targets = item.members.isEmpty ? [item.url] : item.members
        let removed = targets.filter { (try? FileManager.default.removeItem(at: $0)) != nil }
        return !removed.isEmpty
    }

    /// Gathers many small files (such as single cache entries) into one dated folder and trashes
    /// that folder, so the Trash gets one tidy item instead of thousands. Paths inside the folder
    /// mirror the originals, so files can still be put back by hand.
    /// When the Trash refuses and a file can't go back (its place is taken, or not writable), the staging
    /// folder is kept with that file in it and added to `kept`: it is never deleted.
    private static func trashMembers(of item: CleanItem, stagingRoot: URL, trash: TrashAction,
                                     kept: inout [URL]) -> (folder: URL?, relativePaths: [String])? {
        let fm = FileManager.default
        let stamp = Date().formatted(.verbatim("\(year: .defaultDigits)-\(month: .twoDigits)-\(day: .twoDigits) \(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)).\(minute: .twoDigits).\(second: .twoDigits)", timeZone: .current, calendar: .current))
        let staging = uniqueURL(stagingRoot.appending(path: "\(item.name.replacingOccurrences(of: "/", with: "-")) \(stamp)"))
        guard (try? fm.createDirectory(at: staging, withIntermediateDirectories: true)) != nil else { return nil }

        var moved: [(from: URL, to: URL, relative: String)] = []
        for file in item.members {
            let relative = relativePath(of: file, in: item.url)
            let target = staging.appending(path: relative)
            try? fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            if (try? fm.moveItem(at: file, to: target)) != nil { moved.append((file, target, relative)) }
        }

        if !moved.isEmpty, let trashed = try? trash(staging) { return (trashed, moved.map(\.relative)) }
        // Nothing moved, or the Trash refused: put every file back where it came from.
        let stranded = moved.filter { (try? fm.moveItem(at: $0.to, to: $0.from)) == nil }
        if stranded.isEmpty {
            // Only empty folders are left.
            try? fm.removeItem(at: staging)
        } else {
            kept.append(staging)
        }
        return nil
    }

    /// A member's path inside its item, so files from different subfolders can't collide in staging.
    /// Paths are compared as written and then with symlinks resolved (`/var` is `/private/var`).
    static func relativePath(of file: URL, in folder: URL) -> String {
        for (path, base) in [(file.standardizedFileURL.path, folder.standardizedFileURL.path),
                             (file.resolvingSymlinksInPath().path, folder.resolvingSymlinksInPath().path)] {
            if path.hasPrefix(base + "/") { return String(path.dropFirst(base.count + 1)) }
        }
        return file.lastPathComponent
    }

    /// Two items with the same name cleaned in the same second must not share a staging folder.
    private static func uniqueURL(_ url: URL) -> URL {
        var candidate = url
        var index = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = url.deletingLastPathComponent().appending(path: "\(url.lastPathComponent) \(index)")
            index += 1
        }
        return candidate
    }
}

/// Wording that follows the "delete permanently" setting.
enum Removal {
    static var isPermanent: Bool { AppSettings.shared.deletesPermanently }

    static var actionTitle: String {
        isPermanent ? L("Hapus Permanen", "Delete Permanently") : L("Pindahkan ke Trash", "Move to Trash")
    }

    static var actionSymbol: String { isPermanent ? "trash.slash" : "trash" }

    /// "Pindahkan 3 file ke Trash?" or "Hapus permanen 3 file?"
    static func question(_ subject: String) -> String {
        isPermanent ? L("Hapus permanen \(subject)?", "Permanently delete \(subject)?") : L("Pindahkan \(subject) ke Trash?", "Move \(subject) to the Trash?")
    }

    static var undoNote: String {
        isPermanent
            ? L("Mode hapus permanen aktif: file langsung dihapus dan tidak bisa dikembalikan.", "Delete permanently is on: files are removed right away and can't be put back.")
            : L("File masih bisa dikembalikan dari Trash.", "Files can still be put back from the Trash.")
    }

    static var progressText: String {
        isPermanent ? L("Menghapus item…", "Deleting items…") : L("Memindahkan item ke Trash…", "Moving items to the Trash…")
    }
}

struct JunkScanner: Sendable {
    /// How long browser web cache may go unused before it counts as junk.
    var chromeMaxAgeDays = ChromeCacheAge.days30.rawValue
    /// How long a download may go unopened before it counts as old.
    var downloadsMaxAgeDays = DownloadsAge.days90.rawValue
    var home = URL.homeDirectory

    private static let installerExtensions: Set<String> = ["dmg", "pkg", "mpkg", "xip"]
    /// Cache folders shared by several apps of one vendor (Google holds Chrome and Android Studio).
    /// They are listed per app, so one open app doesn't lock the others and one isn't removed with another.
    private static let vendorFolders: Set<String> = ["Google", "Mozilla", "JetBrains", "Microsoft", "Adobe", "BraveSoftware"]
    /// Caches that background system services are using right now, which "app is open" locking can't see:
    /// in-flight background downloads, iCloud and iCloud Drive, Family Sharing, Home and Music.
    /// Removing them loses work in progress or forces a heavy re-sync, so they are never offered.
    static let protectedCaches: Set<String> = [
        "com.apple.nsurlsessiond", "CloudKit", "com.apple.bird", "com.apple.cloudd", "com.apple.icloudwebd",
        "com.apple.iCloudHelper", "com.apple.itunescloudd", "FamilyCircle", "com.apple.homed", "com.apple.akd",
    ]
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
            items = appCaches()
        case .browsers:
            items = BrowserCacheScanner(maxAgeDays: chromeMaxAgeDays, home: home).scan()
        case .userLogs:
            items = children(of: library("Logs"))
        case .developer:
            items = Self.developerFolders.flatMap { children(of: library($0)) }
        case .installers:
            items = installers()
        case .oldDownloads:
            items = oldDownloads()
        case .mailDownloads:
            items = mailDownloads()
        case .iosBackups:
            items = iosBackups()
        case .trash:
            items = trashContents()
        }
        return items.filter { $0.size > 0 }.sorted { $0.size > $1.size }
    }

    private func library(_ subpath: String) -> URL {
        home.appending(path: "Library/\(subpath)", directoryHint: .isDirectory)
    }

    private var downloads: URL { home.appending(path: "Downloads", directoryHint: .isDirectory) }

    /// Top-level items in Downloads not opened, changed or added for a while. Installers have their own category.
    private func oldDownloads() -> [CleanItem] {
        let keys: Set<URLResourceKey> = [.contentAccessDateKey, .contentModificationDateKey, .addedToDirectoryDateKey]
        let cutoff = Date().addingTimeInterval(-Double(downloadsMaxAgeDays) * 24 * 60 * 60)
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: downloads, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles])) ?? []
        return urls.compactMap { url in
            guard !Self.installerExtensions.contains(url.pathExtension.lowercased()),
                  let values = try? url.resourceValues(forKeys: keys) else { return nil }
            let lastUsed = [values.contentAccessDate, values.contentModificationDate, values.addedToDirectoryDate]
                .compactMap { $0 }.max() ?? .distantFuture
            guard lastUsed < cutoff else { return nil }
            let when = lastUsed.formatted(Date.RelativeFormatStyle(presentation: .named).locale(AppSettings.shared.locale))
            return CleanItem(url: url, size: FileSizer.allocatedSize(of: url),
                             detail: L("Terakhir dipakai \(when)", "Last used \(when)"))
        }
    }

    /// Attachments Mail copied out when they were opened or previewed. The messages keep the originals,
    /// so these copies are safe to remove; Mail makes a new one if the attachment is opened again.
    private func mailDownloads() -> [CleanItem] {
        let folder = library("Containers/com.apple.mail/Data/Library/Mail Downloads")
        let keys: Set<URLResourceKey> = [.contentAccessDateKey, .contentModificationDateKey]
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles])) ?? []
        return urls.map { url in
            let values = try? url.resourceValues(forKeys: keys)
            let lastUsed = [values?.contentAccessDate, values?.contentModificationDate].compactMap { $0 }.max()
            let when = lastUsed?.formatted(Date.RelativeFormatStyle(presentation: .named).locale(AppSettings.shared.locale))
            return CleanItem(url: url, size: FileSizer.allocatedSize(of: url),
                             detail: when.map { L("Dibuka \($0)", "Opened \($0)") })
        }
    }

    /// Finder/iTunes device backups and downloaded iOS/iPadOS restore images.
    private func iosBackups() -> [CleanItem] {
        let backups = library("Application Support/MobileSync/Backup")
        let backupItems = (try? FileManager.default.contentsOfDirectory(
            at: backups, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]))?
            .map { folder -> CleanItem in
                let info = NSDictionary(contentsOf: folder.appending(path: "Info.plist"))
                let device = info?["Device Name"] as? String ?? folder.lastPathComponent
                let date = (info?["Last Backup Date"] as? Date)?
                    .formatted(Date.FormatStyle(date: .abbreviated, time: .omitted).locale(AppSettings.shared.locale))
                return CleanItem(url: folder, size: FileSizer.allocatedSize(of: folder),
                                 title: L("Backup \(device)", "\(device) backup"),
                                 detail: date.map { L("Backup terakhir \($0)", "Last backed up \($0)") })
            } ?? []

        let firmwareFolders = [
            "iTunes/iPhone Software Updates", "iTunes/iPad Software Updates", "iTunes/iPod Software Updates",
            "Group Containers/K36BKF7T3D.group.com.apple.configurator/Library/Caches/Firmware",
        ].map(library)
        let firmware = firmwareFolders.flatMap { folder in
            ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
                .filter { $0.pathExtension.lowercased() == "ipsw" }
                .map { CleanItem(url: $0, size: FileSizer.allocatedSize(of: $0),
                                 detail: L("File update iOS/iPadOS, bisa diunduh ulang", "iOS/iPadOS update file, can be downloaded again")) }
        }
        return backupItems + firmware
    }

    /// Items already in the Trash. Removing them is always permanent.
    private func trashContents() -> [CleanItem] {
        let trash = home.appending(path: ".Trash")
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: trash, includingPropertiesForKeys: [.addedToDirectoryDateKey], options: [.skipsHiddenFiles])) ?? []
        return urls.map { url in
            let added = (try? url.resourceValues(forKeys: [.addedToDirectoryDateKey]))?.addedToDirectoryDate
            let when = added?.formatted(Date.RelativeFormatStyle(presentation: .named).locale(AppSettings.shared.locale))
            return CleanItem(url: url, size: FileSizer.allocatedSize(of: url),
                             detail: when.map { L("Masuk Trash \($0)", "Trashed \($0)") },
                             removesPermanently: true)
        }
    }

    private func appCaches() -> [CleanItem] {
        let caches = library("Caches")
        return children(of: caches, excluding: Browser.ownedCacheFolders.union(Self.protectedCaches).union([AppInfo.bundleID])).flatMap { item -> [CleanItem] in
            let vendor = item.url.lastPathComponent
            guard Self.vendorFolders.contains(vendor) else { return [item] }
            return children(of: item.url)
                .filter { !Browser.ownedCacheFolders.contains("\(vendor)/\($0.url.lastPathComponent)") }
                .map { CleanItem(url: $0.url, size: $0.size, title: "\(vendor)/\($0.url.lastPathComponent)") }
        }
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
        case .browsers:
            // Old headless temp folders don't belong to the browser the user has open.
            guard let browser = Browser.owning(item.url) else { return nil }
            return apps.first { browser.bundleIDs.contains($0.bundleID) }
        case .mailDownloads:
            return apps.first { $0.bundleID == "com.apple.mail" }
        case .oldDownloads, .iosBackups, .trash:
            return nil
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
        // An app inside a vendor folder, e.g. "google/androidstudio2026.1.1" for Android Studio.
        if let slash = entry.lastIndex(of: "/") {
            let leaf = entry[entry.index(after: slash)...]
            let compactName = name.replacingOccurrences(of: " ", with: "")
            return compactName.count >= 4 && (leaf.hasPrefix(compactName) || leaf.hasPrefix(id))
        }
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

    /// Walks the home folder or a disk, skipping hidden files, package contents and system folders
    /// (~/Library, or a disk's own System, Library and Spotlight folders).
    func scan(minSize: Int64, root: URL = .homeDirectory, progress: @Sendable (Int) -> Void) -> [LargeFile] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: Self.keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { _, _ in true }
        ) else { return [] }

        var found: [LargeFile] = []
        var visited = 0
        var cancelled = false
        enumerator.forEachURL { url in
            if Task.isCancelled { cancelled = true; return false }
            visited += 1
            if visited % 1_500 == 0 { progress(visited) }

            if ScanLocation.skips(url, root: root) {
                enumerator.skipDescendants()
                return true
            }
            guard let values = try? url.resourceValues(forKeys: Set(Self.keys)),
                  values.isRegularFile == true, values.isSymbolicLink != true else { return true }
            let size = Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
            guard size >= minSize else { return true }
            found.append(LargeFile(
                url: url,
                size: size,
                lastUsed: values.contentAccessDate ?? values.contentModificationDate,
                kind: FileKind(pathExtension: url.pathExtension)
            ))
            return true
        }
        if cancelled { return [] }
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

    /// Files an app leaves behind in ~/Library.
    ///
    /// The bundle ID and names come from the app's own Info.plist, so they are untrusted input: an app
    /// named "../../Documents" or with an empty or tiny ID must not be able to point at other data.
    /// Matches by bundle ID are exact. Anything else is marked as a guess and never preselected: folders
    /// matched only by the app's name, look-alike IDs (`com.vendor.editor.beta` for `com.vendor.editor`),
    /// and Group Containers another installed app also declares.
    ///
    /// `ownGroups` and `otherAppsGroups` are the app groups from code signatures; nil reads them.
    func leftovers(for app: InstalledApp, home: URL = .homeDirectory,
                   ownGroups: Set<String>? = nil, otherAppsGroups: Set<String>? = nil) -> [CleanItem] {
        let id = app.bundleID
        // Without a well-formed ID nothing can be matched safely, so only the app itself goes.
        guard Self.isValidBundleID(id) else { return [] }

        let library = home.appending(path: "Library")
        let nameGuess = L("Mungkin terkait · cocok dari nama aplikasi", "Possibly related · matched by the app's name")
        let lookAlike = L("Mungkin milik app lain · ID-nya hanya mirip", "May belong to another app · its ID only looks alike")
        var candidates: [(url: URL, guess: String?)] = []
        func add(_ subpath: String, guess: String? = nil) { candidates.append((library.appending(path: subpath), guess)) }

        for folder in ["Application Support", "Caches", "Logs"] {
            add("\(folder)/\(id)")
            for name in app.searchNames where Self.isSafeName(name) { add("\(folder)/\(name)", guess: nameGuess) }
        }
        add("Preferences/\(id).plist")
        add("Containers/\(id)")
        add("Application Scripts/\(id)")
        add("Saved Application State/\(id).savedState")
        add("HTTPStorages/\(id)")
        add("HTTPStorages/\(id).binarycookies")
        add("WebKit/\(id)")
        add("Cookies/\(id).binarycookies")
        // Group Containers: the app's signed app groups, or the conventional "group.<id>" / "<TEAM>.<id>".
        // A container another installed app also declares is shared, and look-alikes may be another app's.
        let ownGroups = ownGroups ?? Self.appGroups(of: app.url)
        let otherAppsGroups = otherAppsGroups ?? Self.appGroups(ofAppsOtherThan: app)
        let shared = L("Dipakai bersama app lain yang masih terpasang", "Shared with another installed app")
        candidates += entries(in: library.appending(path: "Group Containers")) {
            ownGroups.contains($0) || Self.isOwnGroupName($0, id: id) || $0.hasSuffix(".\(id)") || $0.contains(".\(id).")
        }.map { url in
            let name = url.lastPathComponent
            if otherAppsGroups.contains(name) { return (url, shared) }
            return (url, ownGroups.contains(name) || Self.isOwnGroupName(name, id: id) ? nil : lookAlike)
        }
        // "<id>.plist" is the app's own agent; "<id>.<more>.plist" may be a helper or another app such as a beta.
        candidates += entries(in: library.appending(path: "LaunchAgents")) {
            $0 == "\(id).plist" || $0.hasPrefix("\(id).")
        }.map { ($0, $0.lastPathComponent == "\(id).plist" ? nil : lookAlike) }
        // ByHost preferences are "<id>.<host UUID>.plist".
        candidates += entries(in: library.appending(path: "Preferences/ByHost")) { $0.hasPrefix("\(id).") }
            .map { ($0, Self.isByHostName($0.lastPathComponent, id: id) ? nil : lookAlike) }

        var seen = Set<String>()
        let libraryPath = library.resolvingSymlinksInPath().path
        return candidates
            .filter { candidate in
                // Belt and braces: a candidate must stay inside ~/Library and pass the global guard.
                let parent = candidate.url.deletingLastPathComponent().resolvingSymlinksInPath().path
                return (parent == libraryPath || parent.hasPrefix(libraryPath + "/"))
                    && SafetyGuard.isAllowed(candidate.url, home: home)
                    && FileManager.default.fileExists(atPath: candidate.url.path)
                    && seen.insert(candidate.url.path).inserted
            }
            .map { candidate in
                CleanItem(url: candidate.url, size: FileSizer.allocatedSize(of: candidate.url),
                          detail: candidate.guess, isGuess: candidate.guess != nil)
            }
            .sorted { $0.size > $1.size }
    }

    /// "group.<id>", "<id>", or either behind a ten-character team ID, such as "ABCDE12345.<id>".
    static func isOwnGroupName(_ name: String, id: String) -> Bool {
        if name == id || name == "group.\(id)" { return true }
        let parts = name.split(separator: ".", maxSplits: 1).map(String.init)
        guard parts.count == 2, parts[0].count == 10,
              parts[0].allSatisfy({ ($0.isUppercase || $0.isNumber) && $0.isASCII }) else { return false }
        return parts[1] == id || parts[1] == "group.\(id)"
    }

    /// "<id>.<host UUID>.plist": the UUID, or an older 12-digit hardware address, and nothing else.
    static func isByHostName(_ name: String, id: String) -> Bool {
        guard name.hasPrefix("\(id)."), name.hasSuffix(".plist") else { return false }
        let host = name.dropFirst(id.count + 1).dropLast(".plist".count)
        return (host.count == 36 || host.count == 12) && host.allSatisfy { $0.isHexDigit || $0 == "-" }
    }

    /// The app groups an app declares in its signed entitlements.
    static func appGroups(of appURL: URL) -> Set<String> {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(appURL as CFURL, [], &code) == errSecSuccess, let code else { return [] }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSRequirementInformation), &info) == errSecSuccess,
              let signing = info as? [String: Any],
              let entitlements = signing[kSecCodeInfoEntitlementsDict as String] as? [String: Any] else { return [] }
        return Set(entitlements["com.apple.security.application-groups"] as? [String] ?? [])
    }

    /// App groups declared by every other installed app, Apple's included, to spot shared containers.
    static func appGroups(ofAppsOtherThan app: InstalledApp) -> Set<String> {
        let roots = [URL(filePath: "/Applications"), URL(filePath: "/System/Applications"), URL.homeDirectory.appending(path: "Applications")]
        let bundles = roots.flatMap { AppScanner().appBundles(in: $0, depth: 2) }
        return bundles.filter { $0.standardizedFileURL != app.url.standardizedFileURL }
            .reduce(into: Set<String>()) { $0.formUnion(appGroups(of: $1)) }
    }

    /// Reverse-DNS like "com.vendor.App": letters, digits, hyphens and underscores, at least two parts.
    static func isValidBundleID(_ id: String) -> Bool {
        guard id.count >= 5, id.count <= 255, !id.hasPrefix("."), !id.hasSuffix("."), !id.contains("..") else { return false }
        let parts = id.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count >= 2 && parts.allSatisfy { part in
            !part.isEmpty && part.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        }
    }

    /// Folder names shared by many apps or by macOS itself; matching on them would catch other apps' data.
    private static let genericNames: Set<String> = [
        "apple", "google", "microsoft", "adobe", "mozilla", "jetbrains", "oracle", "app", "apps", "helper",
        "library", "caches", "logs", "preferences", "containers", "application support", "documents",
        "desktop", "downloads", "data", "cache", "temp", "tmp", "backup", "backups", "user", "users", "shared",
    ]

    /// A name usable as one folder name: no path separators, no "." or "..", no hidden names.
    static func isSafeName(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed == name, name.count >= 3, name.count <= 255 else { return false }
        guard !name.contains("/"), !name.contains(":"), !name.hasPrefix("."), !name.contains("\0") else { return false }
        return !genericNames.contains(name.lowercased())
    }

    private func entries(in folder: URL, where matches: (String) -> Bool) -> [URL] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return urls.filter { matches($0.lastPathComponent) }
    }

    func appBundles(in folder: URL, depth: Int) -> [URL] {
        guard depth > 0, let urls = try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
        ) else { return [] }
        return urls.flatMap { url -> [URL] in
            if url.pathExtension == "app" { return [url] }
            let isFolder = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            return isFolder ? appBundles(in: url, depth: depth - 1) : []
        }
    }

    func makeApp(_ url: URL) -> InstalledApp? {
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
