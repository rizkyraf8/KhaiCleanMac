import Foundation

/// An installed app and where it learns about its own updates.
struct UpdatableApp: Identifiable, Hashable, Sendable {
    enum Source: Hashable, Sendable {
        /// Sparkle, the updater most apps outside the App Store use; the feed is the app's own appcast.
        case sparkle(feed: URL)
        case appStore
        /// Updates itself some other way (its own updater, Homebrew, or not at all).
        case unknown
    }

    let app: InstalledApp
    /// CFBundleVersion, which Sparkle compares against the feed.
    let bundleVersion: String?
    let source: Source

    var id: URL { app.url }
    var displayVersion: String { app.version ?? bundleVersion ?? "?" }
}

/// The newest release an appcast offers this Mac.
struct AppcastRelease: Sendable, Equatable {
    let version: String
    let shortVersion: String?
    let releaseNotes: URL?
    let date: Date?
    var displayVersion: String { shortVersion ?? version }
}

struct AvailableUpdate: Identifiable, Sendable {
    let app: UpdatableApp
    let release: AppcastRelease
    var id: URL { app.id }
}

enum AppUpdateScanner {
    static func updatableApps(_ apps: [InstalledApp]) -> [UpdatableApp] {
        apps.map { app in
            let info = Bundle(url: app.url)?.infoDictionary ?? [:]
            return UpdatableApp(app: app, bundleVersion: info["CFBundleVersion"] as? String, source: source(of: app.url, info: info))
        }
    }

    static func source(of appURL: URL, info: [String: Any]) -> UpdatableApp.Source {
        if FileManager.default.fileExists(atPath: appURL.appending(path: "Contents/_MASReceipt/receipt").path) { return .appStore }
        // Only web feeds: a file:// or custom-scheme "feed" is never fetched.
        if let feed = (info["SUFeedURL"] as? String).flatMap(URL.init(string:)),
           let scheme = feed.scheme?.lowercased(), scheme == "https" || scheme == "http", feed.host() != nil {
            return .sparkle(feed: feed)
        }
        return .unknown
    }

    /// Downloads the appcast. Only the feed address is requested, the same request the app makes
    /// itself; nothing about this Mac or its other apps is sent.
    static func fetchRelease(feed: URL, session: URLSession = .shared) async -> AppcastRelease? {
        var request = URLRequest(url: feed, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("application/rss+xml, application/xml, text/xml", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? false,
              data.count < 20_000_000 else { return nil }
        return AppcastParser.newestRelease(in: data)
    }

    static func update(for app: UpdatableApp, release: AppcastRelease) -> AvailableUpdate? {
        guard let installed = app.bundleVersion,
              VersionComparator.compare(release.version, installed) == .orderedDescending else { return nil }
        // A feed whose "version" is the marketing number while the app's bundle version is a build
        // number (or the other way round) can't be compared reliably, so the short versions decide.
        if let short = release.shortVersion, let installedShort = app.app.version {
            switch VersionComparator.compare(short, installedShort) {
            case .orderedAscending: return nil
            case .orderedSame:
                // Same marketing version, newer build: only trust it when both builds are written alike.
                guard release.version.count(where: { $0 == "." }) == installed.count(where: { $0 == "." }) else { return nil }
            case .orderedDescending: break
            }
        }
        return AvailableUpdate(app: app, release: release)
    }
}

/// Reads a Sparkle appcast and picks the newest item this Mac can install.
enum AppcastParser {
    static func newestRelease(in data: Data, osVersion: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion) -> AppcastRelease? {
        let delegate = Delegate()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = false
        parser.delegate = delegate
        guard parser.parse() || !delegate.items.isEmpty else { return nil }

        let current = "\(osVersion.majorVersion).\(osVersion.minorVersion).\(osVersion.patchVersion)"
        return delegate.items
            .filter { item in
                // Beta and other opt-in channels, other platforms and releases that need a newer macOS are skipped.
                item.channel == nil
                    && (item.os == nil || item.os == "macos")
                    && (item.minimumSystem.map { VersionComparator.compare($0, current) != .orderedDescending } ?? true)
                    && item.version != nil
            }
            .max { VersionComparator.compare($0.version!, $1.version!) == .orderedAscending }
            .map { item in
                AppcastRelease(
                    version: item.version!, shortVersion: item.shortVersion,
                    releaseNotes: (item.releaseNotesLink ?? item.link).flatMap(URL.init(string:)).flatMap { $0.scheme == "https" ? $0 : nil },
                    date: item.pubDate.flatMap(parseDate)
                )
            }
    }

    private struct Item {
        var version: String?
        var shortVersion: String?
        var minimumSystem: String?
        var channel: String?
        var os: String?
        var releaseNotesLink: String?
        var link: String?
        var pubDate: String?
    }

    private final class Delegate: NSObject, XMLParserDelegate {
        var items: [Item] = []
        private var current: Item?
        private var text = ""

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?,
                    attributes: [String: String] = [:]) {
            text = ""
            if name == "item" {
                current = Item()
            } else if name == "enclosure", var item = current {
                // Older feeds put the versions on the enclosure instead of in their own elements.
                item.version = item.version ?? attributes["sparkle:version"]
                item.shortVersion = item.shortVersion ?? attributes["sparkle:shortVersionString"]
                item.os = item.os ?? attributes["sparkle:os"]?.lowercased()
                current = item
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

        func parser(_ parser: XMLParser, foundCDATA block: Data) { text += String(decoding: block, as: UTF8.self) }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            text = ""
            guard current != nil else { return }
            switch name {
            case "item":
                if let item = current { items.append(item) }
                current = nil
            case "sparkle:version" where !value.isEmpty: current?.version = value
            case "sparkle:shortVersionString" where !value.isEmpty: current?.shortVersion = value
            case "sparkle:minimumSystemVersion" where !value.isEmpty: current?.minimumSystem = value
            case "sparkle:channel" where !value.isEmpty: current?.channel = value
            case "sparkle:releaseNotesLink" where !value.isEmpty: current?.releaseNotesLink = value
            case "sparkle:fullReleaseNotesLink" where !value.isEmpty && current?.releaseNotesLink == nil: current?.releaseNotesLink = value
            case "link" where !value.isEmpty: current?.link = value
            case "pubDate" where !value.isEmpty: current?.pubDate = value
            default: break
            }
        }
    }

    private static func parseDate(_ text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        for format in ["EEE, dd MMM yyyy HH:mm:ss Z", "EEE, d MMM yyyy HH:mm:ss Z", "EEE, dd MMM yyyy HH:mm:ss zzz", "dd MMM yyyy HH:mm:ss Z"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: text) { return date }
        }
        return nil
    }
}

/// Compares version strings the way Sparkle does: "1.10" is newer than "1.9", "2.0" newer than "2.0b3".
enum VersionComparator {
    private enum Part: Equatable {
        case number(Int), text(String), separator
    }

    static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let a = parts(lhs), b = parts(rhs)
        for (x, y) in zip(a, b) {
            switch (x, y) {
            case let (.number(m), .number(n)) where m != n: return m < n ? .orderedAscending : .orderedDescending
            case let (.text(s), .text(t)) where s != t: return s < t ? .orderedAscending : .orderedDescending
            case (.number, .number), (.text, .text), (.separator, .separator): continue
            // Different kinds at the same place: a number beats text ("1.0.1" > "1.0b1"),
            // and anything beats a separator except text, which marks a pre-release.
            case (.number, _): return .orderedDescending
            case (_, .number): return .orderedAscending
            case (.text, .separator): return .orderedAscending
            case (.separator, .text): return .orderedDescending
            }
        }
        guard a.count != b.count else { return .orderedSame }
        // The longer one is newer ("1.0.1" > "1.0"), unless what it adds is a pre-release tag ("1.0b1" < "1.0").
        let longerIsLHS = a.count > b.count
        let extra = longerIsLHS ? a[b.count...] : b[a.count...]
        let next = extra.first { $0 != .separator }
        let longerIsNewer: Bool = if case .text = next { false } else { true }
        return (longerIsLHS == longerIsNewer) ? .orderedDescending : .orderedAscending
    }

    private static func parts(_ version: String) -> [Part] {
        var result: [Part] = []
        var buffer = ""
        var bufferIsNumber = false
        func flush() {
            guard !buffer.isEmpty else { return }
            result.append(bufferIsNumber ? .number(Int(buffer.prefix(18)) ?? 0) : .text(buffer.lowercased()))
            buffer = ""
        }
        for character in version.trimmingCharacters(in: .whitespaces) {
            if character.isNumber && character.isASCII {
                if !bufferIsNumber { flush() }
                bufferIsNumber = true
                buffer.append(character)
            } else if character == "." || character == "-" || character == "_" || character == " " || character == "+" {
                flush()
                result.append(.separator)
            } else {
                if bufferIsNumber { flush() }
                bufferIsNumber = false
                buffer.append(character)
            }
        }
        flush()
        return result
    }
}
