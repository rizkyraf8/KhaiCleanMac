import AppKit
import SwiftUI

@MainActor @Observable
final class SimilarPhotosModel {
    enum Phase { case idle, scanning, results }

    private(set) var phase: Phase = .idle
    private(set) var groups: [SimilarGroup] = []
    private(set) var progress: SimilarPhotoScanner.Progress?
    private(set) var isCleaning = false
    /// Nothing is preselected: similar isn't identical, and only the user knows which shot is the keeper.
    var selected: Set<URL> = []
    var toast: ToastMessage?
    private var task: Task<Void, Never>?

    var totalReclaimable: Int64 { groups.reduce(0) { $0 + $1.reclaimable } }
    var selectedSize: Int64 { groups.flatMap(\.photos).reduce(0) { selected.contains($1.url) ? $0 + $1.size : $0 } }

    func scan() {
        task?.cancel()
        withAnimation(.smooth) { phase = .scanning }
        progress = nil
        selected = []
        task = Task.detached(priority: .userInitiated) { [weak self] in
            let groups = SimilarPhotoScanner().scan { progress in
                Task { @MainActor in self?.progress = progress }
            }
            guard !Task.isCancelled else { return }
            await self?.finish(groups)
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        withAnimation(.smooth) { phase = .idle }
    }

    private func finish(_ groups: [SimilarGroup]) {
        self.groups = groups
        withAnimation(.smooth) { phase = .results }
    }

    /// Every photo but the first (most pixels, then biggest) in each group.
    func selectAllButBest() {
        selected = Set(groups.flatMap { $0.photos.dropFirst().map(\.url) })
    }

    func toggle(_ photo: SimilarPhoto, in group: SimilarGroup) {
        if selected.contains(photo.url) {
            selected.remove(photo.url)
        } else if group.photos.count(where: { selected.contains($0.url) }) < group.photos.count - 1 {
            selected.insert(photo.url)
        } else {
            toast = ToastMessage(text: L("Sisakan minimal satu foto di setiap grup", "Keep at least one photo in every group"),
                                 symbol: "hand.raised.fill", colors: Module.similarPhotos.colors)
        }
    }

    func moveSelectedToTrash() async {
        guard !isCleaning else { return }
        isCleaning = true
        defer { isCleaning = false }
        let groups = groups
        let selected = selected
        let photos = await Task.detached(priority: .userInitiated) {
            groups.flatMap { SimilarPhotoScanner.verifiedRemovals(in: $0, selected: selected) }
        }.value
        let skipped = selected.count - photos.count
        let items = photos.map { CleanItem(url: $0.url, size: $0.size) }
        let report = items.isEmpty ? CleanReport() : await Trasher.removeRecorded(items, source: Module.similarPhotos.title)
        let failed = Set(report.unremoved.map(\.url))
        let removed = Set(items.map(\.url)).subtracting(failed)
        withAnimation(.snappy) {
            self.groups = groups.compactMap { group in
                var group = group
                group.photos.removeAll { removed.contains($0.url) }
                return group.photos.count > 1 ? group : nil
            }
            self.selected = failed
        }
        var text = report.summaryText
        if skipped > 0 {
            text += L(" · \(skipped) dilewati karena berubah sejak dipindai", " · \(skipped) skipped because they changed since the scan")
        }
        toast = ToastMessage(text: text, symbol: report.isComplete && skipped == 0 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                             colors: Module.similarPhotos.colors)
    }
}

@MainActor @Observable
final class SecurityScanModel {
    enum Phase { case idle, scanning, results }

    private(set) var phase: Phase = .idle
    private(set) var findings: [SecurityFinding] = []
    private(set) var visitedCount = 0
    private(set) var isCleaning = false
    var selected: Set<URL> = []
    var toast: ToastMessage?
    private var task: Task<Void, Never>?

    var removable: [SecurityFinding] { findings.filter { $0.kind != .loosePermissions } }
    var selectedSize: Int64 { findings.reduce(0) { selected.contains($1.url) ? $0 + $1.size : $0 } }

    func findings(of kind: SecurityFinding.Kind) -> [SecurityFinding] { findings.filter { $0.kind == kind } }
    var kinds: [SecurityFinding.Kind] { SecurityFinding.Kind.allCases.filter { !findings(of: $0).isEmpty } }

    func scan() {
        task?.cancel()
        withAnimation(.smooth) { phase = .scanning }
        visitedCount = 0
        selected = []
        task = Task.detached(priority: .userInitiated) { [weak self] in
            let findings = SecurityScanner().scan { visited in
                Task { @MainActor in self?.visitedCount = visited }
            }
            guard !Task.isCancelled else { return }
            await self?.finish(findings)
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        withAnimation(.smooth) { phase = .idle }
    }

    private func finish(_ findings: [SecurityFinding]) {
        self.findings = findings
        withAnimation(.smooth) { phase = .results }
    }

    func toggle(_ finding: SecurityFinding) {
        guard finding.kind != .loosePermissions else { return }
        if selected.contains(finding.url) { selected.remove(finding.url) } else { selected.insert(finding.url) }
    }

    /// Makes a private key readable only by its owner, as ssh requires.
    func fixPermissions(_ finding: SecurityFinding) {
        guard SecurityScanner.restrictPermissions(finding.url) else {
            toast = ToastMessage(text: L("Izin file tidak bisa diubah", "Couldn't change the file's permissions"),
                                 symbol: "exclamationmark.triangle.fill", colors: Module.security.colors)
            return
        }
        withAnimation(.snappy) { findings.removeAll { $0.id == finding.id } }
        toast = ToastMessage(text: L("\(finding.name) sekarang hanya bisa dibaca olehmu", "\(finding.name) is now readable only by you"),
                             symbol: "checkmark.circle.fill", colors: Module.security.colors)
    }

    func moveSelectedToTrash() async {
        guard !isCleaning else { return }
        isCleaning = true
        defer { isCleaning = false }
        let items = findings.filter { selected.contains($0.url) && $0.kind != .loosePermissions }.map { CleanItem(url: $0.url, size: $0.size) }
        let report = await Trasher.removeRecorded(items, source: Module.security.title)
        let failed = Set(report.unremoved.map(\.url))
        withAnimation(.snappy) {
            findings.removeAll { selected.contains($0.url) && !failed.contains($0.url) && $0.kind != .loosePermissions }
            selected = failed
        }
        toast = ToastMessage(text: report.summaryText, symbol: report.isComplete ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                             colors: Module.security.colors)
    }
}
