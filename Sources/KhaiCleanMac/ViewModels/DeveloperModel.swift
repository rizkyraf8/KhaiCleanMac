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
    private(set) var docker: DockerState = .notInstalled
    private(set) var isCleaningDocker = false
    /// Docker has its own, shorter ages: images and build cache pile up much faster than libraries.
    var dockerAge: DockerAge = .days30
    /// Off by default: a stopped container's own files can hold data that isn't in a volume.
    var includeStoppedContainers = false

    /// Stopped containers the current settings would remove (none unless they're opted in).
    var dockerContainersToRemove: [DockerContainer] {
        guard includeStoppedContainers, case .ready(let engine) = docker else { return [] }
        return engine.containers(olderThan: dockerAge)
    }

    private var scanTask: Task<Void, Never>?
    /// Bumped by every scan and cancel, so a scan that was replaced can't deliver its old result.
    private var scanGeneration = 0
    /// True while selected items are being removed, so the button can't start a second run on them.
    private(set) var isCleaning = false

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
        scanGeneration += 1
        let generation = scanGeneration
        scanTask = Task.detached(priority: .userInitiated) { [weak self] in
            let result = DeveloperScanner(staleDays: days).scan { visited in
                Task { @MainActor in self?.visitedCount = visited }
            }
            guard !Task.isCancelled else { return }
            await self?.finish(result, generation: generation)
        }
    }

    func cancel() {
        scanTask?.cancel()
        scanTask = nil
        scanGeneration += 1
        withAnimation(.smooth) { phase = .idle }
    }

    private func finish(_ result: DevScanResult, generation: Int) {
        guard generation == scanGeneration else { return }
        self.result = result
        refreshLocks()
        applyDefaultSelection()
        withAnimation(.smooth) { phase = .results }
        Task { await refreshDocker() }
    }

    // MARK: Docker

    #if DEBUG
    /// Snapshots show the Docker card on Macs without Docker.
    func previewDocker(_ state: DockerState) {
        docker = state
    }
    #endif

    func refreshDocker() async {
        let state = await Task.detached(priority: .userInitiated) {
            DockerCleaner.state(binary: DockerCleaner.binary())
        }.value
        withAnimation(.smooth) { docker = state }
    }

    /// Docker removes these itself and for good: there is no Trash for images or containers.
    func cleanDocker() async {
        guard case .ready(let engine) = docker, let binary = DockerCleaner.binary() else { return }
        isCleaningDocker = true
        let age = dockerAge
        let containers = dockerContainersToRemove
        let result = await Task.detached(priority: .userInitiated) {
            DockerCleaner.prune(age, engine: engine, containers: containers, binary: binary)
        }.value
        isCleaningDocker = false
        CleanHistory.shared.record(Self.dockerHistory(result, engine: engine, age: age, containers: containers), source: "Docker")
        let text = result.failures.isEmpty
            ? L("Docker: \(result.reclaimed.formattedBytes) dibersihkan", "Docker: \(result.reclaimed.formattedBytes) cleaned")
            : L("Docker: \(result.reclaimed.formattedBytes) dibersihkan · \(result.failures.count) langkah gagal",
                "Docker: \(result.reclaimed.formattedBytes) cleaned · \(result.failures.count) steps failed")
        toast = ToastMessage(text: text, symbol: result.failures.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                             colors: Module.developer.colors)
        await refreshDocker()
    }

    /// One History line per Docker cleanup. Nothing can be restored from it (Docker has no Trash),
    /// but it shows what went, from which engine and how much.
    nonisolated static func dockerHistory(_ result: DockerPruneResult, engine: DockerEngine, age: DockerAge,
                                          containers: [DockerContainer]) -> CleanReport {
        var report = CleanReport(permanent: true)
        guard result.reclaimed > 0 || !containers.isEmpty else { return report }
        var what = L("image & build cache", "images & build cache")
        if !containers.isEmpty { what += L(" + \(containers.count) container", " + \(containers.count) containers") }
        let title = L("Docker (\(engine.context)): \(what), dibuat lebih dari \(age.label) lalu",
                      "Docker (\(engine.context)): \(what) created over \(age.label) ago")
        let socket = URL(filePath: engine.host.replacingOccurrences(of: "unix://", with: ""))
        let item = CleanItem(url: socket, size: result.reclaimed, title: title)
        report.movedCount = 1
        report.movedSize = result.reclaimed
        report.removed = [RemovedItem(item, trashedTo: nil, memberPaths: [])]
        return report
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
        guard !isCleaning else { return }
        isCleaning = true
        defer { isCleaning = false }
        // An IDE or the Simulator may have been opened since the scan.
        refreshLocks()
        let cutoff = cutoff
        let chosen = allItems.filter { selected.contains($0.url) && isSelectable($0) }
        let simulatorItems = chosen.filter { $0.simulator != nil }
        let simulatorReport = await removeSimulators(simulatorItems)
        let trashItems = chosen.filter { $0.simulator == nil }.compactMap { Self.cleanItem(for: $0, cutoff: cutoff) }
        let report = trashItems.isEmpty ? CleanReport() : await Trasher.removeRecorded(trashItems, source: Module.developer.title)
        let failed = Set((report.unremoved + simulatorReport.failed).map(\.url))

        withAnimation(.snappy) {
            for category in DevCategory.allCases {
                result.items[category] = items(in: category).compactMap { item in
                    guard selected.contains(item.url), !failed.contains(item.url) else { return item }
                    guard item.isSmart else { return nil }
                    let gone = Set(item.staleEntries(before: cutoff).map(\.url))
                    let rest = item.removing(gone)
                    // Nothing left to offer: drop it rather than keep an empty folder in the list.
                    return rest.entries.isEmpty ? nil : rest
                }
            }
            selected = failed
        }
        let summary = [trashItems.isEmpty ? nil : report.summaryText, simulatorItems.isEmpty ? nil : simulatorReport.summaryText]
        toast = ToastMessage(text: summary.compactMap { $0 }.joined(separator: " · "),
                             symbol: failed.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                             colors: Module.developer.colors)
    }

    /// What removing `item` hands to the Trasher. An entry-only cache gives only its stale entries, or
    /// nothing at all: a CleanItem without members stands for the whole folder.
    nonisolated static func cleanItem(for item: DevItem, cutoff: Date) -> CleanItem? {
        guard item.isSmart else { return CleanItem(url: item.url, size: item.size) }
        let stale = item.staleEntries(before: cutoff)
        guard !stale.isEmpty else { return nil }
        return CleanItem(url: item.url, size: stale.reduce(0) { $0 + $1.size },
                         title: L("\(item.title) (tidak dipakai)", "\(item.title) (unused)"),
                         members: stale.map(\.url))
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
