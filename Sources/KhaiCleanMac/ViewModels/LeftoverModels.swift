import SwiftUI

@MainActor @Observable
final class OrphanLeftoversModel {
    enum Phase { case idle, scanning, results }

    private(set) var phase: Phase = .idle
    private(set) var leftovers: [OrphanLeftover] = []
    private(set) var isCleaning = false
    /// Nothing is preselected: an ID without an app is a strong hint, not proof.
    var selected: Set<URL> = []
    var toast: ToastMessage?
    private var task: Task<Void, Never>?

    var totalSize: Int64 { leftovers.reduce(0) { $0 + $1.size } }
    var selectedSize: Int64 { leftovers.reduce(0) { selected.contains($1.url) ? $0 + $1.size : $0 } }

    func scan() {
        task?.cancel()
        withAnimation(.smooth) { phase = .scanning }
        selected = []
        task = Task.detached(priority: .userInitiated) { [weak self] in
            let found = OrphanScanner().scan()
            guard !Task.isCancelled else { return }
            await self?.finish(found)
        }
    }

    private func finish(_ found: [OrphanLeftover]) {
        leftovers = found
        withAnimation(.smooth) { phase = .results }
    }

    func toggle(_ leftover: OrphanLeftover) {
        if selected.contains(leftover.url) { selected.remove(leftover.url) } else { selected.insert(leftover.url) }
    }

    func moveSelectedToTrash() async {
        guard !isCleaning else { return }
        isCleaning = true
        defer { isCleaning = false }
        let items = leftovers.filter { selected.contains($0.url) }.map(\.item)
        let report = await Trasher.removeRecorded(items, source: L("Sisa app terhapus", "Leftovers of removed apps"))
        let failed = Set(report.unremoved.map(\.url))
        withAnimation(.snappy) {
            leftovers.removeAll { selected.contains($0.url) && !failed.contains($0.url) }
            selected = failed
        }
        toast = ToastMessage(text: report.summaryText, symbol: report.isComplete ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                             colors: Module.uninstaller.colors)
    }
}

@MainActor @Observable
final class LanguageReportModel {
    private(set) var apps: [AppLanguages] = []
    private(set) var isMeasuring = false
    /// The apps the report is for; a different list (an uninstall, a reload) measures again.
    private var measuredFor: Set<URL> = []
    private var task: Task<Void, Never>?

    var totalSize: Int64 { apps.reduce(0) { $0 + $1.unusedSize } }

    func measureIfChanged(_ installed: [InstalledApp]) {
        let urls = Set(installed.map(\.url))
        guard !urls.isEmpty, urls != measuredFor else { return }
        measure(installed)
    }

    func measure(_ installed: [InstalledApp]) {
        task?.cancel()
        isMeasuring = true
        measuredFor = Set(installed.map(\.url))
        apps = []
        let used = LanguageReport.usedLanguages()
        task = Task { [weak self] in
            for app in installed {
                guard !Task.isCancelled else { return }
                if let report = await Task.detached(priority: .utility, operation: { LanguageReport.report(for: app, used: used) }).value {
                    guard !Task.isCancelled else { return }
                    withAnimation(.snappy) { self?.apps.append(report) }
                }
            }
            self?.apps.sort { $0.unusedSize > $1.unusedSize }
            self?.isMeasuring = false
        }
    }
}
