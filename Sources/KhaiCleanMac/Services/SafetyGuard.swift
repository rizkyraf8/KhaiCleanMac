import Foundation

/// The last line of defense before anything is removed: whatever a scanner or the user picked,
/// these locations are never trashed or deleted. Every removal goes through `Trasher`, which asks here.
enum SafetyGuard {
    /// Folders that must never be removed themselves (their contents may be, item by item).
    private static func protectedFolders(home: URL) -> [String] {
        let library = home.appending(path: "Library")
        let systemRoots = [
            "/", "/System", "/Library", "/Applications", "/Users", "/Volumes", "/private", "/usr", "/bin", "/sbin",
            "/etc", "/var", "/opt", "/tmp", "/cores", "/Network",
        ]
        let homeFolders = [
            "", "Library", "Documents", "Desktop", "Downloads", "Pictures", "Movies", "Music", "Public",
            "Applications", ".Trash",
        ].map { home.appending(path: $0).path }
        let libraryFolders = [
            "Application Support", "Application Scripts", "Caches", "Containers", "Cookies", "Developer",
            "Group Containers", "HTTPStorages", "LaunchAgents", "Logs", "Preferences", "Saved Application State",
            "WebKit", "Fonts", "Services", "Mail", "Messages", "Safari", "Calendars", "Photos", "Accounts",
        ].map { library.appending(path: $0).path }
        return systemRoots + homeFolders + libraryFolders
    }

    /// Whole subtrees that hold the user's data or the system's: nothing inside them is ever removed.
    private static func protectedTrees(home: URL) -> [String] {
        let library = home.appending(path: "Library")
        return [
            "/System", "/usr", "/bin", "/sbin", "/private", "/etc", "/var", "/Library",
            library.appending(path: "Keychains").path,
            library.appending(path: "Mobile Documents").path,
            library.appending(path: "CloudStorage").path,
        ]
    }

    /// Why `url` must not be removed, or nil when it may be.
    static func refusal(for url: URL, home: URL = .homeDirectory) -> String? {
        guard url.isFileURL, url.path.hasPrefix("/") else { return "not a local absolute path" }
        // "a/../b" could point anywhere; real scan results never contain it.
        if url.pathComponents.contains("..") || url.pathComponents.contains(".") { return "relative path component" }

        // Check the path as given and with symlinks in its parent folders resolved, so a symlink can't
        // smuggle a protected folder in under an innocent name.
        // Paths are compared ignoring letter case and Unicode composition, as the disk does:
        // "~/documents" or "/LIBRARY/x" open the same folders as "~/Documents" and "/Library/x".
        let resolvedParent = url.deletingLastPathComponent().resolvingSymlinksInPath()
        let candidates = Set([
            key(url.path),
            key(resolvedParent.appending(path: url.lastPathComponent).path),
        ])
        let resolvedHome = home.resolvingSymlinksInPath()
        let folders = Set((protectedFolders(home: home) + protectedFolders(home: resolvedHome)).map(key))
        let trees = (protectedTrees(home: home) + protectedTrees(home: resolvedHome)).map(key)
        // The per-user temporary folder lives under /private, but what's inside it is always disposable.
        // Each form of the path is judged on its own, so a symlink out of it is still caught.
        // `resolvingSymlinksInPath` strips "/private", while directory listings keep it, so accept both spellings.
        let temporaryDirectory = key(FileManager.default.temporaryDirectory.resolvingSymlinksInPath().path)
        let temporaryRoots: Set<String> = temporaryDirectory.hasPrefix("/private/")
            ? [temporaryDirectory, String(temporaryDirectory.dropFirst("/private".count))]
            : [temporaryDirectory, "/private" + temporaryDirectory]
        let volumeSystemFolders = Set(ScanLocation.volumeSystemFolders.map(key))

        for path in candidates {
            if folders.contains(path) { return "protected folder \(path)" }
            // A disk's own root, such as /Volumes/Backup.
            let components = path.split(separator: "/")
            if components.count == 2, components[0] == "volumes" { return "volume root \(path)" }
            // A disk's Spotlight index, Trash, versions store or bootable system, and anything in them.
            if components.count >= 3, components[0] == "volumes", volumeSystemFolders.contains(String(components[2])) {
                return "disk system folder \(path)"
            }
            // On a bootable copy of macOS, its apps and user folders belong to that system too.
            if components.count >= 3, components[0] == "volumes", ["applications", "users"].contains(components[2]),
               ScanLocation.isBootable(URL(filePath: "/Volumes").appending(path: String(components[1]))) {
                return "bootable disk folder \(path)"
            }
            // Only the subtree rule is waived inside the temporary folder (it sits under /private).
            if temporaryRoots.contains(where: { path.hasPrefix($0 + "/") }) { continue }
            if let tree = trees.first(where: { path == $0 || path.hasPrefix($0 + "/") }) {
                return "inside protected folder \(tree)"
            }
        }
        return nil
    }

    static func isAllowed(_ url: URL, home: URL = .homeDirectory) -> Bool {
        refusal(for: url, home: home) == nil
    }

    /// The form paths are compared in: no trailing slash, precomposed, lowercased.
    private static func key(_ path: String) -> String {
        let trimmed = path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
        return trimmed.precomposedStringWithCanonicalMapping.lowercased()
    }
}
