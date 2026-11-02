import AppKit
import SwiftUI

@MainActor @Observable
final class SystemDataModel {
    enum Phase { case idle, measuring, done }

    private(set) var phase: Phase = .idle
    private(set) var buckets: [StorageBucket] = []
    private(set) var snapshots: [LocalSnapshots.Snapshot] = []
    private(set) var purgeable: Int64?
    private(set) var isDeletingSnapshots = false
    var toast: ToastMessage?
    private var task: Task<Void, Never>?

    var measuredTotal: Int64 { buckets.reduce(0) { $0 + ($1.size ?? 0) } }

    func measure() {
        task?.cancel()
        withAnimation(.smooth) {
            phase = .measuring
            buckets = SystemDataScanner.buckets()
        }
        task = Task { [weak self] in
            guard let self else { return }
            async let snapshots = Task.detached(priority: .userInitiated) { LocalSnapshots.list() }.value
            async let purgeable = Task.detached(priority: .userInitiated) { SystemDataScanner.purgeable() }.value
            // One at a time, so each size shows up as soon as it is known.
            for index in buckets.indices {
                let bucket = buckets[index]
                let size = await Task.detached(priority: .userInitiated) { SystemDataScanner.measure(bucket) }.value
                guard !Task.isCancelled else { return }
                withAnimation(.snappy) { buckets[index].size = size }
            }
            self.snapshots = await snapshots
            self.purgeable = await purgeable
            withAnimation(.snappy) {
                buckets.sort { ($0.size ?? 0) > ($1.size ?? 0) }
                phase = .done
            }
        }
    }

    func showInFinder(_ bucket: StorageBucket) {
        let existing = bucket.folders.filter { FileManager.default.fileExists(atPath: $0.path) }
        NSWorkspace.shared.activateFileViewerSelecting(existing.isEmpty ? bucket.folders : existing)
    }

    func deleteSnapshots() async {
        guard !snapshots.isEmpty, !isDeletingSnapshots else { return }
        isDeletingSnapshots = true
        let chosen = snapshots
        let (deleted, remaining) = await Task.detached(priority: .userInitiated) { LocalSnapshots.delete(chosen) }.value
        isDeletingSnapshots = false
        withAnimation(.snappy) { snapshots = remaining }
        purgeable = SystemDataScanner.purgeable()
        toast = deleted > 0
            ? ToastMessage(text: L("\(deleted) snapshot lokal dihapus", "\(deleted) local snapshots deleted"),
                           symbol: "checkmark.circle.fill", colors: Module.systemData.colors)
            : ToastMessage(text: L("Snapshot tidak dihapus", "No snapshots were deleted"),
                           symbol: "exclamationmark.triangle.fill", colors: Module.systemData.colors)
    }
}

/// Minimum size for iCloud Drive files to list; small files free little space.
enum CloudSizeThreshold: Int64, CaseIterable, Identifiable {
    case mb10 = 10_000_000
    case mb50 = 50_000_000
    case mb200 = 200_000_000

    var id: Int64 { rawValue }
    var label: String { rawValue.formattedBytes }
}

@MainActor @Observable
final class ICloudModel {
    enum Phase { case idle, scanning, results }

    private(set) var phase: Phase = .idle
    private(set) var files: [CloudFile] = []
    private(set) var visitedCount = 0
    private(set) var isEvicting = false
    var selected: Set<URL> = []
    var threshold: CloudSizeThreshold = .mb10
    var toast: ToastMessage?
    private var task: Task<Void, Never>?

    var hasICloudDrive: Bool { FileManager.default.fileExists(atPath: ICloudScanner.root().path) }
    var totalSize: Int64 { files.reduce(0) { $0 + $1.size } }
    var selectedSize: Int64 { files.reduce(0) { selected.contains($1.url) ? $0 + $1.size : $0 } }

    func scan() {
        task?.cancel()
        withAnimation(.smooth) { phase = .scanning }
        visitedCount = 0
        selected = []
        let minSize = threshold.rawValue
        task = Task.detached(priority: .userInitiated) { [weak self] in
            let files = ICloudScanner.scan(minSize: minSize) { visited in
                Task { @MainActor in self?.visitedCount = visited }
            }
            guard !Task.isCancelled else { return }
            await self?.finish(files)
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        withAnimation(.smooth) { phase = .idle }
    }

    private func finish(_ files: [CloudFile]) {
        self.files = files
        withAnimation(.smooth) { phase = .results }
    }

    func toggle(_ file: CloudFile) {
        if selected.contains(file.url) { selected.remove(file.url) } else { selected.insert(file.url) }
    }

    func toggleAll() {
        selected = selected.count == files.count ? [] : Set(files.map(\.url))
    }

    /// Removes the downloaded copies. Nothing is deleted: each file stays in iCloud and downloads again when opened.
    func evictSelected() async {
        guard !isEvicting else { return }
        isEvicting = true
        let chosen = files.filter { selected.contains($0.url) }
        let evicted = await Task.detached(priority: .userInitiated) { chosen.filter { ICloudScanner.evict($0) } }.value
        isEvicting = false
        let gone = Set(evicted.map(\.url))
        let freed = evicted.reduce(0) { $0 + $1.size }
        withAnimation(.snappy) {
            files.removeAll { gone.contains($0.url) }
            selected.subtract(gone)
        }
        let failed = chosen.count - evicted.count
        toast = ToastMessage(
            text: failed == 0
                ? L("\(evicted.count) salinan lokal dilepas · \(freed.formattedBytes) kosong", "\(evicted.count) local copies removed · \(freed.formattedBytes) freed")
                : L("\(evicted.count) salinan dilepas · \(failed) dilewati karena belum selesai sinkron", "\(evicted.count) copies removed · \(failed) skipped, not fully synced yet"),
            symbol: failed == 0 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill", colors: Module.iCloud.colors)
    }
}
