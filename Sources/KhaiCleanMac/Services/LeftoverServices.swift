import AppKit

/// Something in ~/Library named after an app that is no longer on this Mac.
struct OrphanLeftover: Identifiable, Hashable, Sendable {
    let url: URL
    let size: Int64
    /// The bundle ID the entry is named after.
    let bundleID: String
    /// "Caches", "Preferences"…
    let location: String
    let modified: Date?
    /// Set when another app from the same developer is installed and may still use it.
    var note: String?

    var id: URL { url }
    var item: CleanItem { CleanItem(url: url, size: size, title: "\(bundleID) · \(location)", isGuess: true) }
}

/// Finds ~/Library entries named after a bundle ID no app on this Mac has. Only entries named exactly
/// like a bundle ID count (folder names such as "Slack" are too ambiguous), and anything that something
/// wrote to recently is left out: whatever wrote it is still around.
struct OrphanScanner: Sendable {
    var home: URL = .homeDirectory
    /// Entries changed more recently than this are in use by something.
    var quietDays = 14

    /// Folders where the entry name is the bundle ID, with the suffix the entry carries.
    private static let places: [(folder: String, suffix: String)] = [
        ("Application Support", ""), ("Caches", ""), ("Containers", ""), ("Application Scripts", ""),
        ("Preferences", ".plist"), ("Saved Application State", ".savedState"), ("HTTPStorages", ""),
        ("HTTPStorages", ".binarycookies"), ("WebKit", ""), ("Logs", ""), ("Cookies", ".binarycookies"),
    ]
    /// Command-line tools and system helpers that keep files under a bundle-ID-like name without an app.
    private static let toolPrefixes = [
        "org.swift.", "org.llvm.", "org.python.", "org.ruby-lang.", "org.nodejs.", "sh.brew.", "homebrew.",
        "com.github.gh", "com.docker.cli", "org.mozilla.updater", "com.google.keystone", "com.microsoft.autoupdate",
        "com.microsoft.office.licensing", "org.sparkle-project.",
        // macOS's own: Shortcuts keeps its library in group.is.workflow.*, printing in org.cups.*.
        "is.workflow.", "org.cups.",
    ]

    /// `known` says whether an app with this lowercased ID exists anywhere. Nil asks Launch Services
    /// and the usual app folders. `declaredGroups` are the app groups installed apps declare in their
    /// signatures; nil reads them.
    func scan(known: ((String) -> Bool)? = nil, declaredGroups: Set<String>? = nil,
              progress: @Sendable (Int) -> Void = { _ in }) -> [OrphanLeftover] {
        let installed = known == nil ? Self.installedIDs() : []
        let groups = declaredGroups ?? Self.declaredAppGroups()
        let isKnown = known ?? { id in installed.contains(id) || Self.launchServicesKnows(id) }
        let vendors = Set(installed.compactMap(Self.vendor))
        let library = home.appending(path: "Library")
        let cutoff = Date().addingTimeInterval(-Double(quietDays) * 24 * 60 * 60)
        var found: [OrphanLeftover] = []
        var checked = 0
        var cache: [String: Bool] = [:]
        func orphaned(_ id: String) -> Bool {
            let key = id.lowercased()
            if let cached = cache[key] { return cached }
            // A helper or extension ("com.vendor.app.helper") belongs to its app when that is installed.
            let parts = key.split(separator: ".")
            let prefixes = (2...parts.count).map { parts.prefix($0).joined(separator: ".") }
            let result = !prefixes.contains(where: isKnown)
            cache[key] = result
            return result
        }

        var entries: [(url: URL, id: String, location: String)] = []
        for place in Self.places {
            let folder = library.appending(path: place.folder)
            for url in (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [] {
                let name = url.lastPathComponent
                guard place.suffix.isEmpty ? !name.contains(".plist") && !name.hasSuffix(".binarycookies") : name.hasSuffix(place.suffix) else { continue }
                let id = String(name.dropLast(place.suffix.count))
                entries.append((url, id, place.folder))
            }
        }
        // "group.com.vendor.app" or "ABCDE12345.com.vendor.app". A group some installed app declares
        // (Apple's included) is in use, whatever ID its name spells.
        for url in (try? FileManager.default.contentsOfDirectory(at: library.appending(path: "Group Containers"), includingPropertiesForKeys: nil)) ?? [] {
            guard !groups.contains(url.lastPathComponent) else { continue }
            entries.append((url, Self.groupOwner(url.lastPathComponent), "Group Containers"))
        }

        for entry in entries {
            if Task.isCancelled { return [] }
            checked += 1
            if checked % 50 == 0 { progress(checked) }
            let id = entry.id
            guard Self.looksLikeAppID(id), orphaned(id),
                  SafetyGuard.isAllowed(entry.url, home: home),
                  AppScanner.containerBelongs(entry.url, to: id) || entry.location != "Containers" else { continue }
            let usage = Self.sizeAndNewestChange(entry.url)
            guard usage.size > 0, (usage.newest ?? .distantFuture) < cutoff else { continue }
            var leftover = OrphanLeftover(url: entry.url, size: usage.size, bundleID: id, location: entry.location, modified: usage.newest)
            if let vendor = Self.vendor(id.lowercased()), vendors.contains(vendor) {
                leftover.note = L("Ada app lain dari pembuat yang sama, mungkin masih dipakai bersama", "Another app from the same developer is installed and may still share it")
            }
            found.append(leftover)
        }
        progress(checked)
        return found.sorted { $0.size > $1.size }
    }

    /// At least three parts ("com.vendor.App"), well formed, not Apple's, not ours, not a known tool.
    /// Apple also names things "<TEAM>.groups.com.apple.podcasts", so "com.apple" anywhere counts as Apple's.
    static func looksLikeAppID(_ id: String) -> Bool {
        let lower = id.lowercased()
        return AppScanner.isValidBundleID(id) && id.split(separator: ".").count >= 3 && !AppScanner.isAppleID(id)
            && !lower.contains("com.apple.")
            && !lower.hasPrefix(AppInfo.productionBundleID.lowercased()) && !JunkScanner.protectedCaches.contains(id)
            && !toolPrefixes.contains { lower.hasPrefix($0) }
    }

    /// The app ID a group container is named after.
    static func groupOwner(_ name: String) -> String {
        var name = name
        let parts = name.split(separator: ".", maxSplits: 1).map(String.init)
        if parts.count == 2, parts[0].count == 10, parts[0].allSatisfy({ ($0.isUppercase || $0.isNumber) && $0.isASCII }) {
            name = parts[1]
        }
        if name.hasPrefix("group.") { name = String(name.dropFirst("group.".count)) }
        return name
    }

    /// "com.vendor" of "com.vendor.app".
    static func vendor(_ id: String) -> String? {
        let parts = id.split(separator: ".")
        return parts.count >= 3 ? parts.prefix(2).joined(separator: ".") : nil
    }

    /// Lowercased IDs of every app in the usual folders, and of every running app.
    static func installedIDs() -> Set<String> {
        let roots = [URL(filePath: "/Applications"), URL(filePath: "/System/Applications"),
                     URL(filePath: "/System/Library/CoreServices"), URL.homeDirectory.appending(path: "Applications")]
        var ids = Set(roots.flatMap { AppScanner().appBundles(in: $0, depth: 3) }.compactMap { Bundle(url: $0)?.bundleIdentifier?.lowercased() })
        // Apps inside apps (helpers, login items) have their own IDs.
        for app in roots.flatMap({ AppScanner().appBundles(in: $0, depth: 2) }) {
            for folder in ["Contents/Library/LoginItems", "Contents/Helpers", "Contents/PlugIns", "Contents/Library/LaunchServices"] {
                for url in (try? FileManager.default.contentsOfDirectory(at: app.appending(path: folder), includingPropertiesForKeys: nil)) ?? [] {
                    if let id = Bundle(url: url)?.bundleIdentifier?.lowercased() { ids.insert(id) }
                }
            }
        }
        ids.formUnion(NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier?.lowercased() })
        return ids
    }

    /// Every app group the apps in the usual folders declare, Apple's apps and their helpers included.
    static func declaredAppGroups() -> Set<String> {
        let roots = [URL(filePath: "/Applications"), URL(filePath: "/System/Applications"),
                     URL(filePath: "/System/Library/CoreServices"), URL.homeDirectory.appending(path: "Applications")]
        return roots.flatMap { AppScanner().appBundles(in: $0, depth: 3) }
            .reduce(into: Set<String>()) { $0.formUnion(AppScanner.appGroups(of: $1)) }
    }

    /// Launch Services knows apps anywhere, also on other disks; a stale record whose app is gone doesn't count.
    static func launchServicesKnows(_ id: String) -> Bool {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    /// Size and the newest modification inside, without reading access dates (Spotlight and backups touch those).
    static func sizeAndNewestChange(_ url: URL) -> (size: Int64, newest: Date?) {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .contentModificationDateKey]
        var size: Int64 = 0
        var newest = (try? url.resourceValues(forKeys: keys))?.contentModificationDate
        func add(_ values: URLResourceValues) {
            size += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
            if let date = values.contentModificationDate, date > (newest ?? .distantPast) { newest = date }
        }
        if let values = try? url.resourceValues(forKeys: keys), values.isRegularFile == true {
            add(values)
        } else if let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(keys), options: [], errorHandler: { _, _ in true }) {
            enumerator.forEachURL { file in
                if Task.isCancelled { return false }
                if let values = try? file.resourceValues(forKeys: keys), values.isRegularFile == true { add(values) }
                return true
            }
        }
        return (size, newest)
    }
}

// MARK: Languages

/// The translations an app carries that none of the Mac's languages use.
struct AppLanguages: Identifiable, Hashable, Sendable {
    let app: InstalledApp
    let unusedSize: Int64
    let unusedCount: Int
    let totalCount: Int

    var id: URL { app.url }
}

/// Only reports: removing files inside an app breaks its code signature, so macOS may refuse to open
/// it and its updater may fail. That's why there is no remove button.
enum LanguageReport {
    /// Old names some apps still use for their folders.
    private static let legacyNames: [String: String] = [
        "english": "en", "japanese": "ja", "french": "fr", "german": "de", "spanish": "es", "italian": "it",
        "dutch": "nl", "portuguese": "pt", "swedish": "sv", "danish": "da", "finnish": "fi", "norwegian": "nb",
        "korean": "ko", "chinese": "zh", "russian": "ru", "polish": "pl",
    ]

    /// The language part of each preferred language ("id", "en"), plus English, which apps fall back to.
    static func usedLanguages(preferred: [String] = Locale.preferredLanguages) -> Set<String> {
        Set(preferred.map(language) + ["en"])
    }

    /// "pt-BR.lproj", "zh_Hans.lproj", "Japanese.lproj" → "pt", "zh", "ja".
    static func language(_ name: String) -> String {
        let base = name.replacingOccurrences(of: ".lproj", with: "").lowercased()
        if let legacy = legacyNames[base] { return legacy }
        return String(base.split(whereSeparator: { $0 == "-" || $0 == "_" }).first ?? Substring(base))
    }

    static func report(for app: InstalledApp, used: Set<String>) -> AppLanguages? {
        let resources = app.url.appending(path: "Contents/Resources")
        let folders = ((try? FileManager.default.contentsOfDirectory(at: resources, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "lproj" }
        guard folders.count > 1 else { return nil }
        let development = (Bundle(url: app.url)?.developmentLocalization).map(language)
        let unused = folders.filter { folder in
            let code = language(folder.lastPathComponent)
            return folder.lastPathComponent != "Base.lproj" && !used.contains(code) && code != development
        }
        guard !unused.isEmpty else { return nil }
        let size = unused.reduce(0) { $0 + FileSizer.allocatedSize(of: $1) }
        return size > 0 ? AppLanguages(app: app, unusedSize: size, unusedCount: unused.count, totalCount: folders.count) : nil
    }
}
