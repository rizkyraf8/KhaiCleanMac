import AppKit
import SwiftUI

@MainActor @Observable
final class SmartScanModel {
    enum Phase { case idle, scanning, results, cleaning, done }

    private(set) var phase: Phase = .idle
    private(set) var categories: [JunkCategory] = []
    private(set) var currentKind: JunkKind?
    private(set) var report: CleanReport?
    /// Items that belong to an app that was open during the scan, keyed to that app's name.
    private(set) var inUseOwners: [URL: String] = [:]
    /// Open apps the user can quit to free their caches (system helpers are locked but not listed).
    private(set) var inUseApps: [String] = []
    private(set) var hasSystemOwners = false
    /// Apps whose items were skipped at clean time because they had been opened after the scan.
    private(set) var skippedApps: [String] = []
    /// Old Chrome versions waiting for a relaunch; shown as advice, never removed by the app.
    private(set) var chromeUpdate: ChromeUpdateInfo?
    private(set) var isChromeRunning = false
    private(set) var hasFullDiskAccess = true
    var selected: Set<URL> = []

    var totalSize: Int64 { categories.reduce(0) { $0 + $1.totalSize } }
    /// Selected items that are already in the Trash; cleaning deletes them for good.
    var selectedTrashCount: Int { category(.trash)?.items.count { selected.contains($0.url) } ?? 0 }
    var itemCount: Int { categories.reduce(0) { $0 + $1.items.count } }
    var selectedSize: Int64 { categories.reduce(0) { $0 + selectedSize(in: $1) } }

    func scan() async {
        phase = .scanning
        categories = []
        selected = []
        inUseOwners = [:]
        inUseApps = []
        hasSystemOwners = false
        report = nil
        let matcher = RunningAppMatcher.current()
        let scanner = JunkScanner(chromeMaxAgeDays: AppSettings.shared.chromeCacheAge.rawValue,
                                  downloadsMaxAgeDays: AppSettings.shared.downloadsAge.rawValue)
        isChromeRunning = matcher.apps.contains { Browser.chrome.bundleIDs.contains($0.bundleID) }
        hasFullDiskAccess = Permissions.hasFullDiskAccess
        chromeUpdate = nil
        var userApps = Set<String>()
        for kind in JunkKind.allCases {
            currentKind = kind
            let items = await Task.detached(priority: .userInitiated) { scanner.scan(kind) }.value
            if kind == .browsers {
                chromeUpdate = await Task.detached(priority: .userInitiated) { BrowserCacheScanner(maxAgeDays: 30).chromeUpdateInfo() }.value
            }
            for item in items {
                guard let owner = matcher.owner(of: item, kind: kind) else { continue }
                inUseOwners[item.url] = owner.name
                if owner.isUserApp { userApps.insert(owner.name) } else { hasSystemOwners = true }
            }
            inUseApps = userApps.sorted()
            withAnimation(.snappy) { categories.append(JunkCategory(kind: kind, items: items)) }
            if kind.selectedByDefault { selected.formUnion(items.filter { inUseOwners[$0.url] == nil }.map(\.url)) }
        }
        currentKind = nil
        withAnimation(.smooth) { phase = .results }
    }

    func clean() async {
        // Re-check right before cleaning: an app may have been opened since the scan.
        let matcher = RunningAppMatcher.current()
        var items: [CleanItem] = []
        var skipped = Set<String>()
        for category in categories {
            for item in category.items where selected.contains(item.url) {
                if let owner = matcher.owner(of: item, kind: category.kind) {
                    skipped.insert(owner.name)
                } else {
                    items.append(item)
                }
            }
        }
        skippedApps = skipped.sorted()
        withAnimation(.smooth) { phase = .cleaning }
        report = await Trasher.removeRecorded(items, source: Module.smartScan.title)
        withAnimation(.smooth) { phase = .done }
    }

    func owner(of item: CleanItem) -> String? {
        inUseOwners[item.url]
    }

    func inUseCount(in category: JunkCategory) -> Int {
        category.items.count { inUseOwners[$0.url] != nil }
    }

    private func selectableItems(in category: JunkCategory) -> [CleanItem] {
        category.items.filter { inUseOwners[$0.url] == nil }
    }

    func reset() {
        withAnimation(.smooth) {
            phase = .idle
            categories = []
            selected = []
        }
    }

    func category(_ kind: JunkKind) -> JunkCategory? {
        categories.first { $0.kind == kind }
    }

    func selectedSize(in category: JunkCategory) -> Int64 {
        category.items.reduce(0) { selected.contains($1.url) ? $0 + $1.size : $0 }
    }

    func selectionState(of category: JunkCategory) -> SelectionState {
        let selectable = selectableItems(in: category)
        let count = selectable.count { selected.contains($0.url) }
        if count == 0 { return .none }
        return count == selectable.count ? .all : .partial
    }

    func toggle(_ category: JunkCategory) {
        let urls = Set(selectableItems(in: category).map(\.url))
        if urls.isSubset(of: selected) { selected.subtract(urls) } else { selected.formUnion(urls) }
    }

    func toggle(_ item: CleanItem) {
        guard inUseOwners[item.url] == nil else { return }
        if selected.contains(item.url) { selected.remove(item.url) } else { selected.insert(item.url) }
    }
}

@MainActor @Observable
final class LargeFilesModel {
    enum Phase { case idle, scanning, results }
    enum Sort: String, CaseIterable, Identifiable {
        case size, lastUsed, name
        var id: String { rawValue }

        var title: String {
            switch self {
            case .size: L("Ukuran", "Size")
            case .lastUsed: L("Terakhir dipakai", "Last used")
            case .name: L("Nama", "Name")
            }
        }
    }

    private(set) var phase: Phase = .idle
    private(set) var files: [LargeFile] = []
    private(set) var visitedCount = 0
    var threshold: SizeThreshold = .mb100
    var location: ScanLocation = .home
    var filter: FileKind?
    var sort: Sort = .size
    var selected: Set<URL> = []
    var toast: ToastMessage?

    private var scanTask: Task<Void, Never>?

    var visibleFiles: [LargeFile] {
        let filtered = filter.map { kind in files.filter { $0.kind == kind } } ?? files
        switch sort {
        case .size: return filtered.sorted { $0.size > $1.size }
        case .lastUsed: return filtered.sorted { ($0.lastUsed ?? .distantPast) < ($1.lastUsed ?? .distantPast) }
        case .name: return filtered.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
    }

    var presentKinds: [FileKind] {
        FileKind.allCases.filter { kind in files.contains { $0.kind == kind } }
    }

    var selectedFiles: [LargeFile] { files.filter { selected.contains($0.url) } }
    var selectedSize: Int64 { selectedFiles.reduce(0) { $0 + $1.size } }
    var totalSize: Int64 { files.reduce(0) { $0 + $1.size } }

    func count(of kind: FileKind) -> Int { files.count { $0.kind == kind } }

    func scan() {
        scanTask?.cancel()
        withAnimation(.smooth) { phase = .scanning }
        visitedCount = 0
        selected = []
        filter = nil
        let minSize = threshold.rawValue
        let root = location.url
        scanTask = Task.detached(priority: .userInitiated) { [weak self] in
            let result = LargeFileScanner().scan(minSize: minSize, root: root) { visited in
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

    private func finish(_ result: [LargeFile]) {
        files = result
        withAnimation(.smooth) { phase = .results }
    }

    func toggle(_ file: LargeFile) {
        if selected.contains(file.url) { selected.remove(file.url) } else { selected.insert(file.url) }
    }

    func moveSelectedToTrash() async {
        let items = selectedFiles.map(\.item)
        let report = await Trasher.removeRecorded(items, source: Module.largeFiles.title)
        let failed = Set(report.failed.map(\.url))
        withAnimation(.snappy) {
            files.removeAll { selected.contains($0.url) && !failed.contains($0.url) }
            selected = failed
        }
        toast = ToastMessage(text: report.summaryText, symbol: report.failed.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill", colors: Module.largeFiles.colors)
    }
}

@MainActor @Observable
final class UninstallerModel {
    private(set) var apps: [InstalledApp] = []
    private(set) var sizes: [URL: Int64] = [:]
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    private(set) var selectedID: URL?
    private(set) var leftovers: [CleanItem] = []
    private(set) var isLoadingLeftovers = false
    private(set) var isUninstalling = false
    var selectedLeftovers: Set<URL> = []
    var search = ""
    var toast: ToastMessage?

    private var sizeTask: Task<Void, Never>?

    var filteredApps: [InstalledApp] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return apps }
        return apps.filter { $0.name.localizedCaseInsensitiveContains(query) || $0.bundleID.localizedCaseInsensitiveContains(query) }
    }

    var selectedApp: InstalledApp? { apps.first { $0.id == selectedID } }
    var leftoverSelectedSize: Int64 { leftovers.reduce(0) { selectedLeftovers.contains($1.url) ? $0 + $1.size : $0 } }

    func load() async {
        isLoading = true
        sizeTask?.cancel()
        let found = await Task.detached(priority: .userInitiated) { AppScanner().installedApps() }.value
        apps = found
        isLoading = false
        hasLoaded = true
        if let id = selectedID, !found.contains(where: { $0.id == id }) { selectedID = nil }

        // App sizes take a while (Xcode alone is huge), so fill them in progressively.
        let urls = found.map(\.url).filter { sizes[$0] == nil }
        sizeTask = Task.detached(priority: .utility) { [weak self] in
            for url in urls {
                if Task.isCancelled { return }
                let size = FileSizer.allocatedSize(of: url)
                await self?.setSize(size, for: url)
            }
        }
    }

    private func setSize(_ size: Int64, for url: URL) {
        sizes[url] = size
    }

    func select(_ app: InstalledApp) {
        guard selectedID != app.id else { return }
        selectedID = app.id
        leftovers = []
        selectedLeftovers = []
        isLoadingLeftovers = true
        Task {
            let found = await Task.detached(priority: .userInitiated) { AppScanner().leftovers(for: app) }.value
            guard selectedID == app.id else { return }
            withAnimation(.snappy) {
                leftovers = found
                // Name-based guesses stay unticked; the user opts in after reading the path.
                selectedLeftovers = Set(found.filter { !$0.isGuess }.map(\.url))
                isLoadingLeftovers = false
            }
        }
    }

    func toggle(_ item: CleanItem) {
        if selectedLeftovers.contains(item.url) { selectedLeftovers.remove(item.url) } else { selectedLeftovers.insert(item.url) }
    }

    func isRunning(_ app: InstalledApp) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID).isEmpty
    }

    func uninstall(_ app: InstalledApp) async {
        isUninstalling = true
        let appItem = CleanItem(url: app.url, size: sizes[app.url] ?? 0)
        let items = [appItem] + leftovers.filter { selectedLeftovers.contains($0.url) }
        let report = await Trasher.removeRecorded(items, source: Module.uninstaller.title)
        isUninstalling = false

        if report.failed.contains(where: { $0.url == app.url }) {
            toast = ToastMessage(text: L("\(app.name) tidak bisa dipindahkan. Coba hapus manual dari Finder (butuh izin admin).", "\(app.name) couldn't be moved. Try removing it in Finder (needs an admin password)."), symbol: "exclamationmark.triangle.fill", colors: Palette.berry)
            leftovers.removeAll { item in selectedLeftovers.contains(item.url) && !report.failed.contains(item) }
            return
        }
        withAnimation(.snappy) {
            apps.removeAll { $0.id == app.id }
            selectedID = nil
            leftovers = []
            selectedLeftovers = []
        }
        toast = ToastMessage(text: report.permanent
                ? L("\(app.name) dihapus permanen · \(report.movedSize.formattedBytes)", "\(app.name) deleted permanently · \(report.movedSize.formattedBytes)")
                : L("\(app.name) dihapus · \(report.movedSize.formattedBytes) dipindahkan ke Trash", "\(app.name) removed · \(report.movedSize.formattedBytes) moved to the Trash"), colors: Module.uninstaller.colors)
    }
}

extension CleanReport {
    var summaryText: String {
        var text = permanent
            ? L("\(movedCount) item (\(movedSize.formattedBytes)) dihapus permanen",
                "\(movedCount) \(movedCount == 1 ? "item" : "items") (\(movedSize.formattedBytes)) deleted permanently")
            : L("\(movedCount) item (\(movedSize.formattedBytes)) dipindahkan ke Trash",
                "\(movedCount) \(movedCount == 1 ? "item" : "items") (\(movedSize.formattedBytes)) moved to the Trash")
        if !failed.isEmpty { text += L(" · \(failed.count) gagal", " · \(failed.count) failed") }
        if !blocked.isEmpty { text += L(" · \(blocked.count) dilindungi, dilewati", " · \(blocked.count) protected, skipped") }
        return text
    }
}
