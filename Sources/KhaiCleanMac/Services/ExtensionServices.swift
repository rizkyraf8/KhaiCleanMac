import Foundation

enum ExtensionKind: String, CaseIterable, Sendable {
    case safari, finderSync, share, quickLook, widget, notification, shortcuts, spotlight, other

    init(sdk: String) {
        switch sdk {
        case let s where s.hasPrefix("com.apple.Safari"): self = .safari
        case "com.apple.FinderSync": self = .finderSync
        case "com.apple.share-services", "com.apple.services": self = .share
        case let s where s.hasPrefix("com.apple.quicklook"): self = .quickLook
        case "com.apple.widgetkit-extension", "com.apple.widget-extension": self = .widget
        case let s where s.hasPrefix("com.apple.usernotifications"): self = .notification
        case "com.apple.intents-service", "com.apple.appintents-extension", "com.apple.intents-ui-service": self = .shortcuts
        case let s where s.hasPrefix("com.apple.spotlight"): self = .spotlight
        default: self = .other
        }
    }

    var title: String {
        switch self {
        case .safari: L("Ekstensi Safari", "Safari extensions")
        case .finderSync: L("Finder Sync", "Finder Sync")
        case .share: L("Menu Bagikan", "Share menu")
        case .quickLook: L("Pratinjau Quick Look", "Quick Look previews")
        case .widget: L("Widget", "Widgets")
        case .notification: L("Notifikasi", "Notifications")
        case .shortcuts: L("Shortcuts & Siri", "Shortcuts & Siri")
        case .spotlight: "Spotlight"
        case .other: L("Lainnya", "Other")
        }
    }

    var symbol: String {
        switch self {
        case .safari: "safari.fill"
        case .finderSync: "folder.badge.gearshape"
        case .share: "square.and.arrow.up.fill"
        case .quickLook: "eye.fill"
        case .widget: "square.grid.2x2.fill"
        case .notification: "bell.badge.fill"
        case .shortcuts: "square.stack.3d.forward.dottedline.fill"
        case .spotlight: "magnifyingglass"
        case .other: "puzzlepiece.extension.fill"
        }
    }
}

/// An app extension registered with macOS (what `pluginkit` lists).
struct AppExtension: Identifiable, Hashable, Sendable {
    enum Election: Sendable { case enabled, disabled, automatic }

    let id: String
    let name: String
    let version: String?
    let path: String
    let sdk: String
    var election: Election

    var kind: ExtensionKind { ExtensionKind(sdk: sdk) }
    var isEnabled: Bool { election != .disabled }
    /// The app that ships it, e.g. /Applications/WhatsApp.app.
    var appURL: URL? {
        guard let range = path.range(of: ".app/") else { return nil }
        return URL(filePath: String(path[..<range.lowerBound]) + ".app")
    }
}

/// A classic plug-in bundle installed into a Library folder.
struct LegacyPlugin: Identifiable, Hashable, Sendable {
    enum Kind: String, CaseIterable, Sendable {
        case quickLook = "qlgenerator", preferencePane = "prefPane", spotlight = "mdimporter",
             internetPlugin = "plugin", webPlugin = "webplugin", quickAction = "workflow", screenSaver = "saver"

        var folder: String {
            switch self {
            case .quickLook: "QuickLook"
            case .preferencePane: "PreferencePanes"
            case .spotlight: "Spotlight"
            case .internetPlugin, .webPlugin: "Internet Plug-Ins"
            case .quickAction: "Services"
            case .screenSaver: "Screen Savers"
            }
        }

        var title: String {
            switch self {
            case .quickLook: L("Plug-in Quick Look", "Quick Look plug-in")
            case .preferencePane: L("Panel Pengaturan", "Settings pane")
            case .spotlight: L("Pengindeks Spotlight", "Spotlight importer")
            case .internetPlugin, .webPlugin: L("Plug-in browser", "Browser plug-in")
            case .quickAction: L("Quick Action", "Quick Action")
            case .screenSaver: L("Screen saver", "Screen saver")
            }
        }
    }

    let url: URL
    let kind: Kind
    /// In /Library: installed with admin rights, so shown read-only.
    let isSystem: Bool
    let bundleID: String?
    let size: Int64

    var id: URL { url }
    var name: String { url.deletingPathExtension().lastPathComponent }
}

enum ExtensionScanner {
    /// Third-party app extensions only; Apple's own (hundreds of them) are left out.
    static func appExtensions() -> [AppExtension] {
        guard let output = StartupScanner.run("/usr/bin/pluginkit", ["-mAvvv"]) else { return [] }
        return parse(output)
            .filter { !$0.id.hasPrefix("com.apple.") && !$0.path.hasPrefix("/System/") }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Blocks look like `+    com.vendor.ext(1.0)` followed by indented `Key = value` lines.
    /// The first character is the user's choice: "+" on, "-" off, a space for the default.
    static func parse(_ output: String) -> [AppExtension] {
        var result: [AppExtension] = []
        var header: (id: String, version: String?, election: AppExtension.Election)?
        var fields: [String: String] = [:]

        func flush() {
            if let header, let path = fields["Path"] {
                result.append(AppExtension(
                    id: header.id, name: fields["Display Name"] ?? fields["Short Name"] ?? header.id,
                    version: header.version, path: path, sdk: fields["SDK"] ?? "", election: header.election
                ))
            }
            header = nil
            fields = [:]
        }

        for line in output.split(separator: "\n", omittingEmptySubsequences: false) {
            if let first = line.first, !line.trimmingCharacters(in: .whitespaces).isEmpty,
               !line.dropFirst().hasPrefix("\t"), !line.hasPrefix("\t"), line.contains("(") {
                flush()
                let election: AppExtension.Election = first == "+" ? .enabled : (first == "-" ? .disabled : .automatic)
                let body = line.dropFirst().trimmingCharacters(in: .whitespaces)
                // Bundle IDs never contain "(", but the version can be "(null)".
                guard let open = body.firstIndex(of: "(") else { continue }
                let id = String(body[..<open])
                let version = body[body.index(after: open)...].dropLast().description
                header = (id, version == "(null)" || version.isEmpty ? nil : version, election)
            } else if let equals = line.range(of: " = ") {
                let key = line[..<equals.lowerBound].trimmingCharacters(in: .whitespaces)
                fields[key] = String(line[equals.upperBound...]).trimmingCharacters(in: .whitespaces)
            }
        }
        flush()
        return result
    }

    static func legacyPlugins(home: URL = .homeDirectory) -> [LegacyPlugin] {
        let roots: [(URL, Bool)] = [(home.appending(path: "Library"), false), (URL(filePath: "/Library"), true)]
        var plugins: [LegacyPlugin] = []
        for (library, isSystem) in roots {
            for folder in Set(LegacyPlugin.Kind.allCases.map(\.folder)) {
                let urls = (try? FileManager.default.contentsOfDirectory(
                    at: library.appending(path: folder), includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
                for url in urls {
                    guard let kind = LegacyPlugin.Kind(rawValue: url.pathExtension), kind.folder == folder else { continue }
                    plugins.append(LegacyPlugin(url: url, kind: kind, isSystem: isSystem,
                                                bundleID: Bundle(url: url)?.bundleIdentifier, size: FileSizer.allocatedSize(of: url)))
                }
            }
        }
        return plugins.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

enum ExtensionActions {
    /// "use" and "ignore" are the user's own choice in macOS, the same switch System Settings flips.
    static func setEnabled(_ ext: AppExtension, _ enabled: Bool) -> Bool {
        StartupScanner.run("/usr/bin/pluginkit", ["-e", enabled ? "use" : "ignore", "-i", ext.id]) != nil
    }
}
