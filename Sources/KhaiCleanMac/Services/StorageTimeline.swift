import Foundation
import Observation

/// How full the startup disk was on a day.
struct StoragePoint: Codable, Hashable, Sendable {
    let date: Date
    let used: Int64
    let total: Int64
}

/// Disk use over time: one point a day (the latest reading of that day), kept for a year.
/// Measured from the volume's own numbers, so taking a point costs nothing.
@MainActor @Observable
final class StorageTimeline {
    static let shared = StorageTimeline()
    static let limit = 366

    private(set) var points: [StoragePoint] = []
    private let fileURL: URL

    static var defaultFile: URL {
        URL.homeDirectory.appending(path: "Library/Application Support/\(AppInfo.bundleID)/storage-timeline.json")
    }

    init(fileURL: URL = StorageTimeline.defaultFile) {
        self.fileURL = fileURL
        if let data = try? Data(contentsOf: fileURL), let saved = try? JSONDecoder().decode([StoragePoint].self, from: data) {
            points = saved
        }
    }

    func recordNow() {
        guard let disk = DiskInfo.current() else { return }
        add(StoragePoint(date: Date(), used: disk.used, total: disk.total))
    }

    func add(_ point: StoragePoint, calendar: Calendar = .current) {
        points.removeAll { calendar.isDate($0.date, inSameDayAs: point.date) }
        points.append(point)
        points.sort { $0.date < $1.date }
        if points.count > Self.limit { points.removeFirst(points.count - Self.limit) }
        save()
    }

    /// Bytes cleaned per day, from the cleanup history.
    static func cleanedPerDay(_ records: [CleanRecord], calendar: Calendar = .current) -> [(day: Date, size: Int64)] {
        Dictionary(grouping: records) { calendar.startOfDay(for: $0.date) }
            .map { (day: $0.key, size: $0.value.reduce(0) { $0 + $1.totalSize }) }
            .sorted { $0.day < $1.day }
    }

    private func save() {
        guard !AppInfo.isSnapshot else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(points).write(to: fileURL, options: .atomic)
    }
}
