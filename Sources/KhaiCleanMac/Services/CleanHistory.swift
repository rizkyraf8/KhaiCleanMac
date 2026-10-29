import SwiftUI

enum RestoreResult: Sendable, Equatable {
    case restored
    /// Already gone from the Trash: emptied, or put back by hand.
    case notInTrash
    /// Something new already sits at the original place; it is never overwritten.
    case conflict
    /// The Trash can't be read without Full Disk Access.
    case noAccess
    case failed
}

enum Restorer {
    /// Moves an item back from the Trash to where it was cleaned from.
    static func restore(_ item: RemovedItem, home: URL = .homeDirectory) -> RestoreResult {
        guard let trashedPath = item.trashedPath else { return .notInTrash }
        let fm = FileManager.default
        let trashed = URL(filePath: trashedPath)
        let original = URL(filePath: item.originalPath)
        guard fm.fileExists(atPath: trashed.path) else {
            return canReadTrash(home: home) ? .notInTrash : .noAccess
        }

        if item.memberPaths.isEmpty {
            guard !fm.fileExists(atPath: original.path) else { return .conflict }
            try? fm.createDirectory(at: original.deletingLastPathComponent(), withIntermediateDirectories: true)
            return (try? fm.moveItem(at: trashed, to: original)) != nil ? .restored : .failed
        }

        // Items made of many files: each goes back to its own place inside the original folder.
        var moved = 0
        for relative in item.memberPaths where !relative.split(separator: "/").contains("..") {
            let from = trashed.appending(path: relative)
            let to = original.appending(path: relative)
            guard fm.fileExists(atPath: from.path), !fm.fileExists(atPath: to.path) else { continue }
            try? fm.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
            if (try? fm.moveItem(at: from, to: to)) != nil { moved += 1 }
        }
        // Tidy the Trash only when nothing but empty folders is left behind.
        if moved > 0, !containsFiles(trashed) { try? fm.removeItem(at: trashed) }
        return moved > 0 ? .restored : .conflict
    }

    static func canReadTrash(home: URL = .homeDirectory) -> Bool {
        (try? FileManager.default.contentsOfDirectory(atPath: home.appending(path: ".Trash").path)) != nil
    }

    private static func containsFiles(_ folder: URL) -> Bool {
        var found = false
        FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey])?.forEachURL { url in
            found = (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
            return !found
        }
        return found
    }
}

/// Every cleanup, saved locally so the user can see what went where and put things back.
@MainActor @Observable
final class CleanHistory {
    static let shared = CleanHistory()

    private(set) var records: [CleanRecord] = []
    private let fileURL: URL
    private static let limit = 100

    static var defaultFile: URL {
        URL.homeDirectory.appending(path: "Library/Application Support/\(AppInfo.bundleID)/history.json")
    }

    init(fileURL: URL = CleanHistory.defaultFile) {
        self.fileURL = fileURL
        if let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder.history.decode([CleanRecord].self, from: data) {
            records = saved
        }
    }

    var lastRecord: CleanRecord? { records.first }

    func record(_ report: CleanReport, source: String) {
        guard !report.removed.isEmpty else { return }
        records.insert(CleanRecord(date: Date(), source: source, permanent: report.permanent, items: report.removed), at: 0)
        if records.count > Self.limit { records.removeLast(records.count - Self.limit) }
        save()
    }

    func restore(_ itemID: RemovedItem.ID, in recordID: CleanRecord.ID) async -> RestoreResult {
        guard let r = records.firstIndex(where: { $0.id == recordID }),
              let i = records[r].items.firstIndex(where: { $0.id == itemID }) else { return .failed }
        let item = records[r].items[i]
        let result = await Task.detached(priority: .userInitiated) { Restorer.restore(item) }.value
        if result == .restored || result == .notInTrash { markRestored(itemID, in: recordID, gone: result == .notInTrash) }
        return result
    }

    /// Puts back everything still in the Trash from one cleanup; returns how many came back.
    func restoreAll(in recordID: CleanRecord.ID) async -> (restored: Int, results: [RestoreResult]) {
        guard let record = records.first(where: { $0.id == recordID }) else { return (0, []) }
        var results: [RestoreResult] = []
        for item in record.items where item.canRestore {
            results.append(await restore(item.id, in: recordID))
        }
        return (results.count { $0 == .restored }, results)
    }

    func clear() {
        records = []
        save()
    }

    private func markRestored(_ itemID: RemovedItem.ID, in recordID: CleanRecord.ID, gone: Bool) {
        guard let r = records.firstIndex(where: { $0.id == recordID }),
              let i = records[r].items.firstIndex(where: { $0.id == itemID }) else { return }
        // An item that left the Trash on its own can't be restored any more either.
        records[r].items[i].restoredAt = gone ? .distantPast : Date()
        save()
    }

    private func save() {
        guard !AppInfo.isSnapshot else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder.history.encode(records).write(to: fileURL, options: .atomic)
    }
}

private extension JSONEncoder {
    static var history: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var history: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

extension Trasher {
    /// Removes items (Trash or permanent, per Settings) and saves the run in the cleanup history.
    @MainActor
    static func removeRecorded(_ items: [CleanItem], source: String) async -> CleanReport {
        let report = await Task.detached(priority: .userInitiated) { remove(items) }.value
        CleanHistory.shared.record(report, source: source)
        return report
    }
}
