import AppKit

/// Something that starts on its own: a login item, or a launchd agent or daemon.
struct StartupItem: Identifiable, Hashable, Sendable {
    enum Kind: Sendable {
        /// Classic login items, listed by System Events.
        case loginItem
        /// `~/Library/LaunchAgents`: the user's own, can be turned off or removed.
        case userAgent
        /// `/Library/LaunchAgents` and `/Library/LaunchDaemons`: root-owned, shown read-only.
        case systemAgent, systemDaemon
    }

    let id: String
    let kind: Kind
    /// The launchd label, or the login item's name.
    let label: String
    let name: String
    let fileURL: URL?
    let programPath: String?
    let appURL: URL?
    let runsAtLoad: Bool
    let keepsAlive: Bool
    var isDisabled: Bool
    /// The program it starts no longer exists, usually because its app was removed.
    let isOrphan: Bool

    var isEditable: Bool { kind == .loginItem || kind == .userAgent }
}

enum StartupScanner {
    static let userAgentsFolder = URL.homeDirectory.appending(path: "Library/LaunchAgents")
    static let systemAgentsFolder = URL(filePath: "/Library/LaunchAgents")
    static let systemDaemonsFolder = URL(filePath: "/Library/LaunchDaemons")

    static func launchdItems(in folder: URL, kind: StartupItem.Kind, disabled: Set<String>) -> [StartupItem] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return urls
            .filter { $0.pathExtension == "plist" }
            .compactMap { parse($0, kind: kind, disabled: disabled) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func parse(_ plist: URL, kind: StartupItem.Kind, disabled: Set<String>,
                      appForBundleID: (String) -> URL? = appURL(forBundleID:)) -> StartupItem? {
        guard let dict = NSDictionary(contentsOf: plist) as? [String: Any] else { return nil }
        let label = dict["Label"] as? String ?? plist.deletingPathExtension().lastPathComponent
        let program = (dict["Program"] as? String) ?? (dict["ProgramArguments"] as? [String])?.first

        // An agent counts as orphaned when the absolute program it runs is gone, or when it names
        // its owning app (AssociatedBundleIdentifiers) and none of those apps is installed anymore.
        let programMissing = program.map { $0.hasPrefix("/") && !FileManager.default.fileExists(atPath: $0) } ?? false
        let bundleIDs = (dict["AssociatedBundleIdentifiers"] as? [String])
            ?? (dict["AssociatedBundleIdentifiers"] as? String).map { [$0] } ?? []
        let ownerApp = bundleIDs.lazy.compactMap(appForBundleID).first
        let appGone = !bundleIDs.isEmpty && ownerApp == nil
        let app = ownerApp ?? program.flatMap(enclosingApp)

        let keepAlive = (dict["KeepAlive"] as? Bool) ?? (dict["KeepAlive"] is [String: Any])
        return StartupItem(
            id: plist.path,
            kind: kind,
            label: label,
            name: app.map { $0.deletingPathExtension().lastPathComponent } ?? readableName(of: label),
            fileURL: plist,
            programPath: program,
            appURL: app,
            runsAtLoad: dict["RunAtLoad"] as? Bool ?? false,
            keepsAlive: keepAlive,
            isDisabled: disabled.contains(label) || (dict["Disabled"] as? Bool ?? false),
            isOrphan: programMissing || appGone
        )
    }

    /// Labels launchd has been told to skip for the given domain, e.g. `gui/501`.
    static func disabledLabels(domain: String) -> Set<String> {
        guard let output = run("/bin/launchctl", ["print-disabled", domain]) else { return [] }
        return parseDisabled(output)
    }

    /// Lines look like `"com.example.agent" => disabled` (older systems print `=> true`).
    static func parseDisabled(_ output: String) -> Set<String> {
        Set(output.split(separator: "\n").compactMap { line in
            let parts = line.components(separatedBy: "=>")
            guard parts.count == 2 else { return nil }
            let state = parts[1].trimmingCharacters(in: .whitespaces)
            guard state == "disabled" || state == "true" else { return nil }
            return parts[0].trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        })
    }

    /// Classic login items through System Events. macOS asks once for permission to control it;
    /// `nil` means that was declined or failed. Each item is read on its own, so one whose app is gone
    /// (its path can't be read) shows up as an orphan instead of failing the whole list.
    static func loginItems() -> [StartupItem]? {
        let script = """
        set output to ""
        tell application "System Events"
            repeat with anItem in login items
                try
                    set thePath to (path of anItem)
                on error
                    set thePath to ""
                end try
                try
                    set output to output & (name of anItem) & tab & thePath & linefeed
                end try
            end repeat
        end tell
        return output
        """
        guard let output = run("/usr/bin/osascript", ["-e", script]) else { return nil }
        return parseLoginItems(output)
    }

    /// Lines are "name<tab>path"; the path is empty when System Events couldn't read it.
    static func parseLoginItems(_ output: String) -> [StartupItem] {
        output.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: "\t", maxSplits: 1).map(String.init)
            guard let name = parts.first, !name.isEmpty else { return nil }
            let path = parts.count > 1 && !parts[1].isEmpty ? parts[1] : nil
            return StartupItem(
                id: "login:\(name)", kind: .loginItem, label: name, name: name,
                fileURL: path.map { URL(filePath: $0) }, programPath: path,
                appURL: path.flatMap { $0.hasSuffix(".app") ? URL(filePath: $0) : nil },
                runsAtLoad: true, keepsAlive: false, isDisabled: false,
                isOrphan: path.map { !FileManager.default.fileExists(atPath: $0) } ?? true
            )
        }
    }

    // MARK: Helpers

    static func appURL(forBundleID id: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
    }

    private static func enclosingApp(of path: String) -> URL? {
        guard let range = path.range(of: ".app/") else { return path.hasSuffix(".app") ? URL(filePath: path) : nil }
        return URL(filePath: String(path[..<range.lowerBound]) + ".app")
    }

    /// "com.valvesoftware.steamclean" → "steamclean", "sh.brew.redis" → "redis".
    private static func readableName(of label: String) -> String {
        label.split(separator: ".").last.map(String.init) ?? label
    }

    /// Runs a tool and returns its output, or nil when it fails.
    @discardableResult
    static func run(_ tool: String, _ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(filePath: tool)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            return String(decoding: data, as: UTF8.self)
        } catch {
            return nil
        }
    }
}

enum StartupActions {
    private static var guiDomain: String { "gui/\(getuid())" }

    /// Turning an agent off stops it now and keeps launchd from starting it again, even after a restart.
    /// It's fully reversible, unlike removing the plist.
    static func setDisabled(_ item: StartupItem, _ disabled: Bool) -> Bool {
        guard item.kind == .userAgent, let plist = item.fileURL else { return false }
        if disabled {
            guard StartupScanner.run("/bin/launchctl", ["disable", "\(guiDomain)/\(item.label)"]) != nil else { return false }
            StartupScanner.run("/bin/launchctl", ["bootout", guiDomain, plist.path])
        } else {
            guard StartupScanner.run("/bin/launchctl", ["enable", "\(guiDomain)/\(item.label)"]) != nil else { return false }
            StartupScanner.run("/bin/launchctl", ["bootstrap", guiDomain, plist.path])
        }
        return true
    }

    /// Stops the agent, then removes its plist the way the user chose (Trash by default).
    static func remove(_ item: StartupItem) -> CleanReport {
        guard item.kind == .userAgent, let plist = item.fileURL else { return CleanReport() }
        StartupScanner.run("/bin/launchctl", ["bootout", guiDomain, plist.path])
        return Trasher.remove([CleanItem(url: plist, size: FileSizer.allocatedSize(of: plist))])
    }

    static func removeLoginItem(_ item: StartupItem) -> Bool {
        guard item.kind == .loginItem else { return false }
        let name = item.label.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return StartupScanner.run("/usr/bin/osascript", ["-e", "tell application \"System Events\" to delete login item \"\(name)\""]) != nil
    }
}
