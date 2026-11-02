import Foundation

/// Starts the command-line tool when the binary is run with one of its commands, otherwise the app.
@main
enum Entry {
    @MainActor
    static func main() {
        if let status = CommandLineTool.runIfRequested(CommandLine.arguments) { exit(status) }
        KhaiCleanMacApp.main()
    }
}

/// `KhaiCleanMac scan`, `history` and `version`, for scripts and Terminal. It only reads: scans
/// report what Smart Scan would offer and never remove anything, since removing needs the app's
/// confirmation. Link it into your PATH to call it `khaiclean`.
@MainActor
enum CommandLineTool {
    static let commands: Set<String> = ["scan", "history", "version", "help", "--help", "-h", "--version"]

    /// Short names for the Smart Scan categories, besides their own IDs.
    static let aliases: [String: JunkKind] = [
        "caches": .userCache, "browser": .browsers, "logs": .userLogs, "crash": .crashReports, "xcode": .developer,
        "downloads": .oldDownloads, "files": .oldFiles, "mail": .mailDownloads, "ios": .iosBackups,
    ]

    /// The exit status when a command ran, nil to start the app.
    static func runIfRequested(_ arguments: [String], output: (String) -> Void = { print($0) }) -> Int32? {
        guard arguments.count > 1, commands.contains(arguments[1]) else { return nil }
        let options = Array(arguments.dropFirst(2))
        switch arguments[1] {
        case "scan": return scan(options, output: output)
        case "history": return history(options, output: output)
        case "version", "--version":
            output("\(AppInfo.name) \(AppInfo.version) (\(AppInfo.build))")
            return 0
        default:
            output(help)
            return 0
        }
    }

    static var help: String {
        """
        \(AppInfo.name) \(AppInfo.version)

        USAGE
          khaiclean scan [--category <name>]… [--json] [--verbose]
          khaiclean history [--limit <n>] [--json]
          khaiclean version

        scan only measures what Smart Scan would offer; nothing is removed (--dry-run is accepted and changes nothing).
        Categories: \(JunkKind.allCases.map(\.rawValue).joined(separator: ", "))
        Short names: \(aliases.keys.sorted().joined(separator: ", "))
        """
    }

    static func kinds(_ options: [String]) -> [JunkKind]? {
        var kinds: [JunkKind] = []
        var index = 0
        while index < options.count {
            if options[index] == "--category" || options[index] == "-c" {
                guard index + 1 < options.count else { return nil }
                let name = options[index + 1].lowercased()
                guard let kind = JunkKind(rawValue: options[index + 1]) ?? JunkKind.allCases.first(where: { $0.rawValue.lowercased() == name }) ?? aliases[name] else { return nil }
                kinds.append(kind)
                index += 2
            } else {
                index += 1
            }
        }
        return kinds.isEmpty ? JunkKind.allCases : kinds
    }

    private static func scan(_ options: [String], output: (String) -> Void) -> Int32 {
        guard let kinds = kinds(options) else {
            output("Unknown category.\n\n" + help)
            return 64
        }
        let settings = AppSettings.shared
        let scanner = JunkScanner(chromeMaxAgeDays: settings.chromeCacheAge.rawValue, downloadsMaxAgeDays: settings.downloadsAge.rawValue,
                                  logsMaxAgeDays: settings.logsAge.rawValue)
        let hasAccess = Permissions.hasFullDiskAccess
        let results = kinds.map { kind in
            // Desktop and Documents would ask for permission from Terminal's name instead.
            (kind, kind == .oldFiles && !hasAccess ? [] : scanner.scan(kind))
        }
        let total = results.reduce(Int64(0)) { $0 + $1.1.reduce(0) { $0 + $1.size } }

        if options.contains("--json") {
            let categories: [[String: Any]] = results.map { kind, items in
                ["id": kind.rawValue, "title": kind.title, "size": items.reduce(0) { $0 + $1.size }, "selectedByDefault": kind.selectedByDefault,
                 "items": items.map { ["path": $0.url.path, "name": $0.name, "size": $0.size] }]
            }
            let object: [String: Any] = ["version": AppInfo.version, "dryRun": true, "total": total, "categories": categories]
            if let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]) {
                output(String(decoding: data, as: UTF8.self))
            }
            return 0
        }
        let verbose = options.contains("--verbose") || options.contains("-v")
        for (kind, items) in results {
            let size = items.reduce(Int64(0)) { $0 + $1.size }
            output("\(pad(kind.title, 28)) \(pad("\(items.count)", 6, left: true))  \(pad(size.formattedBytes, 10, left: true))")
            if verbose {
                for item in items { output("    \(pad(item.size.formattedBytes, 10, left: true))  \(item.url.abbreviatedPath)") }
            }
        }
        output(String(repeating: "─", count: 48))
        output("\(pad("Total", 36)) \(pad(total.formattedBytes, 10, left: true))")
        if !hasAccess { output("Without Full Disk Access some categories can't be read.") }
        output("Nothing was removed. Open \(AppInfo.name) to review and clean.")
        return 0
    }

    private static func history(_ options: [String], output: (String) -> Void) -> Int32 {
        var limit = 20
        if let index = options.firstIndex(of: "--limit"), index + 1 < options.count, let value = Int(options[index + 1]) { limit = max(1, value) }
        let records = Array(CleanHistory.shared.records.prefix(limit))
        if options.contains("--json") {
            let objects: [[String: Any]] = records.map { record in
                ["date": record.date.formatted(.iso8601), "source": record.source, "permanent": record.permanent,
                 "size": record.totalSize, "items": record.items.map { ["path": $0.originalPath, "size": $0.size, "restored": $0.restoredAt != nil] }]
            }
            if let data = try? JSONSerialization.data(withJSONObject: objects, options: [.prettyPrinted, .sortedKeys]) {
                output(String(decoding: data, as: UTF8.self))
            }
            return 0
        }
        if records.isEmpty { output("No cleanups yet.") }
        for record in records {
            let date = record.date.formatted(date: .abbreviated, time: .shortened)
            output("\(pad(date, 22)) \(pad(record.source, 22)) \(pad("\(record.items.count) items", 10, left: true))  \(pad(record.totalSize.formattedBytes, 10, left: true))\(record.permanent ? "  permanent" : "")")
        }
        return 0
    }

    private static func pad(_ text: String, _ width: Int, left: Bool = false) -> String {
        guard text.count < width else { return text }
        let space = String(repeating: " ", count: width - text.count)
        return left ? space + text : text + space
    }
}
