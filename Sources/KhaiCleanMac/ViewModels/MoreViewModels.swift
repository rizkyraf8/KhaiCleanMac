import AppKit
import SwiftUI

@MainActor @Observable
final class DuplicatesModel {
    enum Phase { case idle, scanning, results }
    enum MinSize: Int64, CaseIterable, Identifiable {
        case kb100 = 100_000
        case mb1 = 1_000_000
        case mb10 = 10_000_000

        var id: Int64 { rawValue }
        var label: String { rawValue.formattedBytes }
    }

    private(set) var phase: Phase = .idle
    private(set) var groups: [DuplicateGroup] = []
    private(set) var progress: DuplicateScanner.Progress?
    var minSize: MinSize = .mb1
    var location: ScanLocation = .home
    var selected: Set<URL> = []
    var toast: ToastMessage?

    private var scanTask: Task<Void, Never>?

    var totalWasted: Int64 { groups.reduce(0) { $0 + $1.wasted } }
    var selectedSize: Int64 {
        groups.reduce(0) { total, group in total + group.size * Int64(group.files.count { selected.contains($0.url) }) }
    }

    func scan() {
        scanTask?.cancel()
        withAnimation(.smooth) { phase = .scanning }
        progress = nil
        selected = []
        let minSize = minSize.rawValue
        let root = location.url
        scanTask = Task.detached(priority: .userInitiated) { [weak self] in
            let result = DuplicateScanner().scan(minSize: minSize, root: root) { progress in
                Task { @MainActor in self?.progress = progress }
            }
            guard !Task.isCancelled else { return }
            await self?.finish(result)
        }
    }

    func cancel() {
        scanTask?.cancel()
        scanTask = nil
        withAnimation(.smooth) { phase = .idle }
    }

    private func finish(_ result: [DuplicateGroup]) {
        groups = result
        autoSelect()
        withAnimation(.smooth) { phase = .results }
    }

    /// Keeps the oldest copy in every group (likely the original) and selects the rest.
    func autoSelect() {
        selected = Set(groups.flatMap { $0.files.dropFirst().map(\.url) })
    }

    func toggle(_ file: DuplicateFile, in group: DuplicateGroup) {
        if selected.contains(file.url) {
            selected.remove(file.url)
        } else if group.files.count(where: { selected.contains($0.url) }) < group.files.count - 1 {
            selected.insert(file.url)
        } else {
            toast = ToastMessage(text: L("Sisakan minimal satu salinan di setiap grup", "Keep at least one copy in every group"), symbol: "hand.raised.fill", colors: Module.duplicates.colors)
        }
    }

    func moveSelectedToTrash() async {
        // Files may have changed since the scan: only copies that still match a kept copy go.
        let groups = groups
        let selected = selected
        let (items, skipped) = await Task.detached(priority: .userInitiated) { () -> ([CleanItem], [URL]) in
            var items: [CleanItem] = []
            var skipped: [URL] = []
            for group in groups {
                let check = DuplicateScanner.verifiedRemovals(in: group, selected: selected)
                items += check.remove.map { CleanItem(url: $0.url, size: group.size) }
                skipped += check.skipped.map(\.url)
            }
            return (items, skipped)
        }.value
        let report = items.isEmpty ? CleanReport() : await Trasher.removeRecorded(items, source: Module.duplicates.title)
        let failed = Set(report.failed.map(\.url))
        let removed = Set(items.map(\.url)).subtracting(failed)
        withAnimation(.snappy) {
            self.groups = groups.compactMap { group in
                var group = group
                group.files.removeAll { removed.contains($0.url) }
                return group.files.count > 1 ? group : nil
            }
            self.selected = failed
        }
        var text = report.summaryText
        if !skipped.isEmpty {
            text += L(" · \(skipped.count) dilewati karena berubah sejak dipindai, pindai ulang",
                      " · \(skipped.count) skipped because files changed since the scan, scan again")
        }
        toast = ToastMessage(text: text, symbol: report.failed.isEmpty && skipped.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                             colors: Module.duplicates.colors)
    }
}

@MainActor @Observable
final class SpaceLensModel {
    static let tileColors = [Palette.mint, Palette.peach, Palette.lavender, Palette.sunny, Palette.sky, Palette.candy, Palette.leaf, Palette.ocean, Palette.berry]

    private(set) var path: [URL] = []
    private(set) var items: [SpaceItem] = []
    private(set) var isMeasuring = false
    /// False while the folder's list of entries is still being read.
    private(set) var hasListed = false
    /// The entry being measured right now, shown in the progress bar.
    private(set) var measuringName: String?
    var selectedID: URL?
    var toast: ToastMessage?

    private var cache: [URL: Int64] = [:]
    private var task: Task<Void, Never>?

    var current: URL? { path.last }
    var sortedItems: [SpaceItem] { items.sorted { ($0.size ?? -1) > ($1.size ?? -1) } }
    var measuredItems: [SpaceItem] { sortedItems.filter { ($0.size ?? 0) > 0 } }
    var knownTotal: Int64 { items.reduce(0) { $0 + ($1.size ?? 0) } }
    var measuredCount: Int { items.count { $0.size != nil } }
    var selectedItem: SpaceItem? { items.first { $0.id == selectedID } }

    func color(for item: SpaceItem) -> [Color] {
        let index = measuredItems.firstIndex { $0.id == item.id } ?? 0
        return Self.tileColors[index % Self.tileColors.count]
    }

    func open(root: URL) {
        path = [root]
        load()
    }

    func open(_ item: SpaceItem) {
        guard item.canOpen else { return }
        path.append(item.url)
        load()
    }

    func goTo(level: Int) {
        guard level < path.count - 1 else { return }
        path = Array(path.prefix(level + 1))
        load()
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = L("Pindai", "Scan")
        panel.directoryURL = current
        if panel.runModal() == .OK, let url = panel.url { open(root: url) }
    }

    private func load() {
        task?.cancel()
        guard let folder = current else { return }
        selectedID = nil
        isMeasuring = true
        hasListed = false
        measuringName = nil
        let cached = cache
        task = Task.detached(priority: .userInitiated) { [weak self] in
            let entries = SpaceScanner.entries(in: folder)
            await self?.show(entries, cached: cached, in: folder)
            for entry in entries where cached[entry.url] == nil {
                await self?.setMeasuring(entry.name, in: folder)
                let size = FileSizer.allocatedSize(of: entry.url)
                // A cancelled measurement is partial, so it must not be cached.
                if Task.isCancelled { return }
                await self?.record(size, for: entry.url, in: folder)
            }
            await self?.finishMeasuring(in: folder)
        }
    }

    private func setMeasuring(_ name: String, in folder: URL) {
        guard current == folder else { return }
        measuringName = name
    }

    private func show(_ entries: [SpaceItem], cached: [URL: Int64], in folder: URL) {
        guard current == folder else { return }
        hasListed = true
        items = entries.map { entry in
            var entry = entry
            entry.size = cached[entry.url]
            return entry
        }
    }

    private func record(_ size: Int64, for url: URL, in folder: URL) {
        cache[url] = size
        guard current == folder, let index = items.firstIndex(where: { $0.url == url }) else { return }
        withAnimation(.smooth) { items[index].size = size }
    }

    private func finishMeasuring(in folder: URL) {
        guard current == folder else { return }
        withAnimation(.smooth) {
            isMeasuring = false
            measuringName = nil
        }
    }

    func moveToTrash(_ item: SpaceItem) async {
        let report = await Trasher.removeRecorded([CleanItem(url: item.url, size: item.size ?? 0)], source: Module.spaceLens.title)
        if report.failed.isEmpty {
            withAnimation(.snappy) { items.removeAll { $0.id == item.id } }
            cache[item.url] = nil
            // Every folder above this one is now smaller than what was cached.
            for url in path { cache[url] = nil }
            selectedID = nil
        }
        toast = ToastMessage(text: report.summaryText, symbol: report.failed.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill", colors: Module.spaceLens.colors)
    }
}
