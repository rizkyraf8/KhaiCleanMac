import AppKit
import SwiftUI

/// How long something may go unused before the Developer module treats it as stale.
enum StaleAge: Int, CaseIterable, Identifiable {
    case days30 = 30, days60 = 60, days90 = 90

    var id: Int { rawValue }
    var label: String { L("\(rawValue) hari", "\(rawValue) days") }
}

@MainActor @Observable
final class DeveloperModel {
    enum Phase { case idle, scanning, results }

    private(set) var phase: Phase = .idle
    private(set) var result = DevScanResult()
    private(set) var visitedCount = 0
    /// Item URL → name of the open app that keeps it locked.
    private(set) var lockedBy: [URL: String] = [:]
    var selected: Set<URL> = []
    var toast: ToastMessage?
    var staleAge: StaleAge = .days90 {
        didSet { applyDefaultSelection() }
    }

    private var scanTask: Task<Void, Never>?

    var cutoff: Date { Date().addingTimeInterval(-Double(staleAge.rawValue) * 24 * 60 * 60) }
    var categories: [DevCategory] { DevCategory.allCases.filter { !items(in: $0).isEmpty } }
    var allItems: [DevItem] { DevCategory.allCases.flatMap { items(in: $0) } }
    var totalRemovable: Int64 { allItems.reduce(0) { $0 + removableSize($1) } }
    var selectedSize: Int64 { allItems.reduce(0) { selected.contains($1.url) ? $0 + removableSize($1) : $0 } }

    func items(in category: DevCategory) -> [DevItem] { result.items[category] ?? [] }

    func size(of category: DevCategory) -> Int64 { items(in: category).reduce(0) { $0 + removableSize($1) } }

    /// What cleaning the item would remove: the whole folder, or only its stale entries.
    func removableSize(_ item: DevItem) -> Int64 {
        guard item.isSmart else { return item.size }
        return item.staleEntries(before: cutoff).reduce(0) { $0 + $1.size }
    }

    func staleCount(_ item: DevItem) -> Int { item.staleEntries(before: cutoff).count }

    func keptSize(_ item: DevItem) -> Int64 { item.size - removableSize(item) }

    func isSelectable(_ item: DevItem) -> Bool {
        lockedBy[item.url] == nil && removableSize(item) > 0
    }

    func scan() {
        scanTask?.cancel()
        withAnimation(.smooth) { phase = .scanning }
        visitedCount = 0
        selected = []
        let days = staleAge.rawValue
        scanTask = Task.detached(priority: .userInitiated) { [weak self] in
            let result = DeveloperScanner(staleDays: days).scan { visited in
                Task { @MainActor in self?.visitedCount = visited }
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

    private func finish(_ result: DevScanResult) {
        self.result = result
        refreshLocks()
        applyDefaultSelection()
        withAnimation(.smooth) { phase = .results }
    }

    private func applyDefaultSelection() {
        selected = Set(allItems.filter { item in
            guard isSelectable(item) else { return false }
            if item.isSmart { return item.selectedByDefault }
            switch item.simulator {
            case .runtime: return item.selectedByDefault && (item.lastUsed ?? .distantPast) < cutoff
            case .device: return item.selectedByDefault
            case nil: break
            }
            // Project folders follow the chosen age; archives and unknown folders stay opt-in.
            if item.tool == "Xcode" || item.note != nil { return false }
            return (item.lastUsed ?? .distantFuture) < cutoff
        }.map(\.url))
    }

    /// Android Studio and IntelliJ keep the Gradle and Maven caches open, so those wait until the IDE is closed.
    private func refreshLocks() {
        var locks: [URL: String] = [:]
        for item in allItems where !item.lockingBundleIDs.isEmpty {
            for id in item.lockingBundleIDs {
                if let app = NSRunningApplication.runningApplications(withBundleIdentifier: id).first {
                    locks[item.url] = app.localizedName ?? id
                    break
                }
            }
        }
        lockedBy = locks
        selected = selected.filter { locks[$0] == nil }
    }

    func selectionState(of category: DevCategory) -> SelectionState {
        let items = items(in: category).filter(isSelectable)
        let count = items.count { selected.contains($0.url) }
        if count == 0 { return .none }
        return count == items.count ? .all : .partial
    }

    func toggle(_ category: DevCategory) {
        let urls = Set(items(in: category).filter(isSelectable).map(\.url))
        if urls.isSubset(of: selected) { selected.subtract(urls) } else { selected.formUnion(urls) }
    }

    func toggle(_ item: DevItem) {
        guard isSelectable(item) else { return }
        if selected.contains(item.url) { selected.remove(item.url) } else { selected.insert(item.url) }
    }

    func copy(_ command: DevCommand) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command.command, forType: .string)
        toast = ToastMessage(text: L("Perintah disalin. Tempel di Terminal untuk menjalankannya.", "Command copied. Paste it into Terminal to run it."),
                             symbol: "doc.on.clipboard.fill", colors: Module.developer.colors)
    }

    /// Simulator runtimes and devices are deleted through `simctl`, not moved to the Trash.
    var selectionHasSimulators: Bool { items(in: .simulators).contains { selected.contains($0.url) } }

    func moveSelectedToTrash() async {
        // An IDE or the Simulator may have been opened since the scan.
        refreshLocks()
        let cutoff = cutoff
        let chosen = allItems.filter { selected.contains($0.url) && isSelectable($0) }
        let simulatorItems = chosen.filter { $0.simulator != nil }
        let simulatorReport = await removeSimulators(simulatorItems)
        let trashItems = chosen.filter { $0.simulator == nil }.map { item -> CleanItem in
            guard item.isSmart else { return CleanItem(url: item.url, size: item.size) }
            let stale = item.staleEntries(before: cutoff)
            return CleanItem(url: item.url, size: stale.reduce(0) { $0 + $1.size },
                             title: L("\(item.title) (tidak dipakai)", "\(item.title) (unused)"),
                             members: stale.map(\.url))
        }
        let report = trashItems.isEmpty ? CleanReport() : await Trasher.removeRecorded(trashItems, source: Module.developer.title)
        let failed = Set((report.failed + simulatorReport.failed).map(\.url))

        withAnimation(.snappy) {
            for category in DevCategory.allCases {
                result.items[category] = items(in: category).compactMap { item in
                    guard selected.contains(item.url), !failed.contains(item.url) else { return item }
                    guard item.isSmart else { return nil }
                    let gone = Set(item.staleEntries(before: cutoff).map(\.url))
                    return item.removing(gone)
                }
            }
            selected = failed
        }
        let summary = [trashItems.isEmpty ? nil : report.summaryText, simulatorItems.isEmpty ? nil : simulatorReport.summaryText]
        toast = ToastMessage(text: summary.compactMap { $0 }.joined(separator: " · "),
                             symbol: failed.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                             colors: Module.developer.colors)
    }

    /// One at a time: CoreSimulator handles a single delete at once anyway.
    private func removeSimulators(_ items: [DevItem]) async -> CleanReport {
        guard !items.isEmpty else { return CleanReport() }
        let report = await Task.detached(priority: .userInitiated) { () -> CleanReport in
            var report = CleanReport()
            report.permanent = true
            for item in items {
                let cleanItem = CleanItem(url: item.url, size: item.size, title: item.title)
                if let target = item.simulator, Simulators.remove(target) {
                    report.movedCount += 1
                    report.movedSize += item.size
                    report.removed.append(RemovedItem(cleanItem, trashedTo: nil, memberPaths: []))
                } else {
                    report.failed.append(cleanItem)
                }
            }
            return report
        }.value
        CleanHistory.shared.record(report, source: L("Simulator Xcode", "Xcode Simulators"))
        return report
    }
}
