import Foundation

// MARK: Python

/// Python virtual environments: ones inside projects, and the shared folders tools keep them in.
enum PythonEnvironments {
    /// Files a project lists its packages in, so a removed environment can be installed again.
    static let manifests = [
        "requirements.txt", "pyproject.toml", "setup.py", "setup.cfg", "Pipfile", "poetry.lock", "uv.lock",
        "environment.yml",
    ]

    /// A venv (`pyvenv.cfg`) or a Conda environment (`conda-meta`).
    static func isEnvironment(_ folder: URL) -> Bool {
        let fm = FileManager.default
        return fm.fileExists(atPath: folder.appending(path: "pyvenv.cfg").path)
            || fm.fileExists(atPath: folder.appending(path: "conda-meta").path)
    }

    /// A project's own environment. Only one next to a manifest is preselected: without one,
    /// its packages may not be written down anywhere.
    static func projectItem(_ url: URL, cutoff: Date) -> DevItem? {
        let project = url.deletingLastPathComponent()
        let usage = UsageMeter.measure(url)
        guard usage.size > 0 else { return nil }
        let hasManifest = manifests.contains { FileManager.default.fileExists(atPath: project.appending(path: $0).path) }
        var item = DevItem(url: url, size: usage.size, title: project.lastPathComponent,
                           tool: "Python · \(url.lastPathComponent)", lastUsed: usage.lastUsed,
                           selectedByDefault: hasManifest && usage.lastUsed < cutoff)
        if !hasManifest {
            item.note = L("Tidak ada requirements.txt atau pyproject.toml di sampingnya, jadi daftar paketnya mungkin tidak tercatat di mana pun. Periksa dulu sebelum dihapus.",
                          "There's no requirements.txt or pyproject.toml next to it, so its packages may not be written down anywhere. Check it before removing.")
        }
        return item
    }

    /// Environments kept outside projects. None are preselected: some are made by hand.
    static func sharedItems(home: URL = .homeDirectory) -> [DevItem] {
        let poetry = L("Poetry membuatnya lagi dengan poetry install.", "Poetry makes it again with poetry install.")
        let pipenv = L("Pipenv membuatnya lagi dengan pipenv install.", "Pipenv makes it again with pipenv install.")
        let manual = L("Dibuat dengan tangan, jadi paketnya mungkin tidak tercatat di mana pun. Periksa dulu sebelum dihapus.",
                       "Made by hand, so its packages may not be written down anywhere. Check it before removing.")
        var roots: [(path: String, tool: String, note: String)] = [
            ("Library/Caches/pypoetry/virtualenvs", "Poetry", poetry),
            (".cache/pypoetry/virtualenvs", "Poetry", poetry),
            (".local/share/virtualenvs", "Pipenv", pipenv),
            (".virtualenvs", "virtualenvwrapper", manual),
        ]
        for conda in ["miniconda3", "anaconda3", "miniforge3", "mambaforge", ".conda"] {
            roots.append(("\(conda)/envs", "Conda", manual))
        }
        roots += UsageMeter.items(in: home.appending(path: ".pyenv/versions"), depth: 1).map {
            (".pyenv/versions/\($0.lastPathComponent)/envs", "pyenv", manual)
        }
        return roots.flatMap { root in
            UsageMeter.items(in: home.appending(path: root.path), depth: 1)
                .filter { isEnvironment($0) && !isSymlink($0) }
                .compactMap { url -> DevItem? in
                    let usage = UsageMeter.measure(url)
                    guard usage.size > 0 else { return nil }
                    return DevItem(url: url, size: usage.size, title: url.lastPathComponent, tool: "Python · \(root.tool)",
                                   lastUsed: usage.lastUsed, selectedByDefault: false, note: root.note)
                }
        }
    }

    private static func isSymlink(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
    }
}

// MARK: Android

/// Android SDK system images and emulators (AVDs).
enum AndroidSDK {
    static let studioID = "com.google.android.studio"

    struct Emulator: Sendable {
        let folder: URL
        let ini: URL
        let name: String
        /// "system-images/android-34/google_apis/arm64-v8a", without a trailing slash.
        let systemImage: String?
    }

    static func sdkRoot(home: URL = .homeDirectory, environment: [String: String] = ProcessInfo.processInfo.environment) -> URL? {
        let candidates = [environment["ANDROID_HOME"], environment["ANDROID_SDK_ROOT"]].compactMap { $0 }.map { URL(filePath: $0) }
            + [home.appending(path: "Library/Android/sdk")]
        return candidates.first { FileManager.default.fileExists(atPath: $0.appending(path: "system-images").path) }
            ?? candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    static func items(home: URL = .homeDirectory, sdk: URL? = sdkRoot()) -> [DevItem] {
        let emulators = emulators(home: home)
        return (systemImages(sdk: sdk, emulators: emulators) + emulators.compactMap(item)).sorted { $0.size > $1.size }
    }

    /// `~/.android/avd/<name>.ini` points at `<name>.avd`, whose `config.ini` names its system image.
    static func emulators(home: URL = .homeDirectory) -> [Emulator] {
        let avd = home.appending(path: ".android/avd")
        let inis = ((try? FileManager.default.contentsOfDirectory(at: avd, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "ini" }
        return inis.compactMap { ini in
            let pointer = properties(ini)
            let fallback = avd.appending(path: ini.deletingPathExtension().lastPathComponent + ".avd")
            // The pointer may be relative to ~/.android or absolute; only a folder inside ~/.android/avd is used.
            let folder = [pointer["path"].map { URL(filePath: $0) }, pointer["path.rel"].map { home.appending(path: ".android/\($0)") }, fallback]
                .compactMap { $0 }
                .first { FileManager.default.fileExists(atPath: $0.path) && $0.deletingLastPathComponent().standardizedFileURL == avd.standardizedFileURL }
            guard let folder else { return nil }
            let config = properties(folder.appending(path: "config.ini"))
            let image = config["image.sysdir.1"].map { $0.hasSuffix("/") ? String($0.dropLast()) : $0 }
            let name = config["avd.ini.displayname"] ?? folder.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "_", with: " ")
            return Emulator(folder: folder, ini: ini, name: name, systemImage: image)
        }
    }

    /// `system-images/<api>/<tag>/<abi>`. An image an emulator uses is never preselected.
    static func systemImages(sdk: URL?, emulators: [Emulator]) -> [DevItem] {
        guard let sdk else { return [] }
        let root = sdk.appending(path: "system-images")
        return UsageMeter.items(in: root, depth: 3).compactMap { folder -> DevItem? in
            let relative = "system-images/" + folder.pathComponents.suffix(3).joined(separator: "/")
            let users = emulators.filter { $0.systemImage == relative }
            let usage = UsageMeter.measure(folder)
            guard usage.size > 0 else { return nil }
            let parts = folder.pathComponents.suffix(3)
            var item = DevItem(url: folder, size: usage.size, title: title(api: parts.first!, tag: parts.dropFirst().first!, abi: parts.last!),
                               tool: L("Android · system image", "Android · system image"), lastUsed: usage.lastUsed,
                               selectedByDefault: users.isEmpty, lockingBundleIDs: [studioID])
            if !users.isEmpty {
                item.note = L("Dipakai emulator \(users.map(\.name).joined(separator: ", ")).", "Used by the emulator \(users.map(\.name).joined(separator: ", ")).")
                item.emulatorFolders = users.map(\.folder)
            }
            return item
        }
    }

    private static func item(_ emulator: Emulator) -> DevItem? {
        let usage = UsageMeter.measure(emulator.folder)
        guard usage.size > 0 else { return nil }
        var item = DevItem(url: emulator.folder, size: usage.size, title: emulator.name, tool: L("Android · emulator", "Android · emulator"),
                           lastUsed: usage.lastUsed, selectedByDefault: false, lockingBundleIDs: [studioID])
        item.note = L("Berisi app, data, dan snapshot emulator ini.", "Holds this emulator's apps, data and snapshots.")
        item.companions = [emulator.ini]
        item.emulatorFolders = [emulator.folder]
        return item
    }

    /// The emulator keeps `*.lock` files in its folder while it runs.
    static func isRunning(_ folder: URL) -> Bool {
        ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).contains { $0.hasSuffix(".lock") }
    }

    /// "android-34", "google_apis_playstore", "arm64-v8a" → "API 34 · Google Play · arm64-v8a".
    static func title(api: String, tag: String, abi: String) -> String {
        let level = api.hasPrefix("android-") ? "API \(api.dropFirst("android-".count))" : api
        let tags = [
            "google_apis_playstore": "Google Play", "google_apis": "Google APIs", "google_atd": "Google ATD",
            "aosp_atd": "AOSP ATD", "default": "AOSP", "android-tv": "Android TV", "google-tv": "Google TV",
            "android-wear": "Wear OS", "android-automotive": "Automotive",
        ]
        return "\(level) · \(tags[tag] ?? tag) · \(abi)"
    }

    /// `key=value` lines, as the AVD files are written.
    static func properties(_ file: URL) -> [String: String] {
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return [:] }
        var values: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            guard let equals = line.firstIndex(of: "=") else { continue }
            values[line[..<equals].trimmingCharacters(in: .whitespaces)] = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
        }
        return values
    }
}

// MARK: Homebrew

/// What `brew cleanup` would remove and which packages have a newer version. Homebrew removes
/// things itself (old versions it still links to are its business), so this only reads and asks it.
struct BrewReport: Sendable, Equatable {
    struct Removal: Sendable, Equatable, Hashable {
        let path: String
        let size: Int64
    }

    struct Outdated: Sendable, Equatable, Identifiable {
        let name: String
        let installed: String
        let current: String
        let isCask: Bool
        let isPinned: Bool

        var id: String { (isCask ? "cask:" : "formula:") + name }
    }

    var removals: [Removal] = []
    var reclaimable: Int64 = 0
    var outdated: [Outdated] = []

    /// Old versions in the Cellar or Caskroom, and downloads in Homebrew's cache.
    var oldVersions: [Removal] { removals.filter { !$0.path.contains("/Caches/Homebrew") && !$0.path.contains("/portable-ruby/") } }
    var downloads: [Removal] { removals.filter { $0.path.contains("/Caches/Homebrew") } }
}

enum BrewState: Sendable, Equatable {
    case notInstalled, checking, failed, ready(BrewReport)
}

enum Homebrew {
    static func binary(exists: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }) -> String? {
        ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"].first(where: exists)
    }

    /// No auto-update, hints or analytics: a check must not change anything or phone home on its own.
    static func environment(for brew: String) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["HOMEBREW_NO_AUTO_UPDATE"] = "1"
        environment["HOMEBREW_NO_ENV_HINTS"] = "1"
        environment["HOMEBREW_NO_ANALYTICS"] = "1"
        let folder = URL(filePath: brew).deletingLastPathComponent().path
        environment["PATH"] = [folder, "/usr/bin", "/bin", "/usr/sbin", "/sbin", environment["PATH"] ?? ""].joined(separator: ":")
        return environment
    }

    static func check(brew: String) -> BrewState {
        let environment = environment(for: brew)
        guard let dryRun = StartupScanner.run(brew, ["cleanup", "--prune=all", "--dry-run"], timeout: 180, environment: environment) else {
            return .failed
        }
        var report = parseDryRun(dryRun)
        if let json = StartupScanner.run(brew, ["outdated", "--json=v2"], timeout: 180, environment: environment) {
            report.outdated = parseOutdated(Data(json.utf8))
        }
        return .ready(report)
    }

    /// `Would remove: <path> (<n> files, 63.4MB)` lines and a closing `free approximately 400MB`.
    static func parseDryRun(_ output: String) -> BrewReport {
        var report = BrewReport()
        for line in output.split(whereSeparator: \.isNewline) {
            if line.hasPrefix("Would remove: "), let match = line.firstMatch(of: /^Would remove: (.+) \((?:[\d,]+ files?, )?([\d.,]+\s?[KMGT]?B)\)$/) {
                report.removals.append(.init(path: String(match.1), size: bytes(String(match.2)) ?? 0))
            } else if let match = line.firstMatch(of: /free approximately ([\d.,]+\s?[KMGT]?B)/) {
                report.reclaimable = bytes(String(match.1)) ?? 0
            }
        }
        if report.reclaimable == 0 { report.reclaimable = report.removals.reduce(0) { $0 + $1.size } }
        report.removals.sort { $0.size > $1.size }
        return report
    }

    /// Homebrew's sizes are in powers of 1024 ("63.4MB").
    static func bytes(_ text: String) -> Int64? {
        guard let match = text.replacingOccurrences(of: ",", with: "").firstMatch(of: /([\d.]+)\s?([KMGT]?)B/),
              let value = Double(match.1) else { return nil }
        let powers: [String: Double] = ["": 0, "K": 1, "M": 2, "G": 3, "T": 4]
        let power = powers[String(match.2)] ?? 0
        return Int64(value * pow(1024, power))
    }

    /// `brew outdated --json=v2`: formulae and casks with the installed and the newest version.
    static func parseOutdated(_ data: Data) -> [BrewReport.Outdated] {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return [] }
        func entries(_ key: String, cask: Bool) -> [BrewReport.Outdated] {
            ((root[key] as? [[String: Any]]) ?? []).compactMap { entry in
                guard let name = entry["name"] as? String else { return nil }
                let installed = (entry["installed_versions"] as? [String])?.last ?? "?"
                return .init(name: name, installed: installed, current: entry["current_version"] as? String ?? "?",
                             isCask: cask, isPinned: entry["pinned"] as? Bool ?? false)
            }
        }
        return (entries("formulae", cask: false) + entries("casks", cask: true))
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Runs `brew cleanup --prune=all`. Returns false when Homebrew failed or timed out.
    static func cleanup(brew: String) -> Bool {
        StartupScanner.run(brew, ["cleanup", "--prune=all"], timeout: 600, environment: environment(for: brew)) != nil
    }

    /// The command to upgrade what is outdated, for the user to run in Terminal: upgrades can ask
    /// for a password or take a long time, which a background process can't handle well.
    static func upgradeCommand(_ outdated: [BrewReport.Outdated]) -> String {
        let formulae = outdated.filter { !$0.isCask && !$0.isPinned }.map(\.name)
        let casks = outdated.filter(\.isCask).map(\.name)
        var parts: [String] = []
        if !formulae.isEmpty { parts.append("brew upgrade --formula " + formulae.joined(separator: " ")) }
        if !casks.isEmpty { parts.append("brew upgrade --cask " + casks.joined(separator: " ")) }
        return parts.isEmpty ? "brew upgrade" : parts.joined(separator: " && ")
    }
}
