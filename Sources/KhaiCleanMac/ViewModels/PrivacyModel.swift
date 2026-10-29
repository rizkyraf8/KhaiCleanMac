import AppKit
import SwiftUI

@MainActor @Observable
final class PrivacyModel {
    private(set) var browsers: [BrowserPrivacy] = []
    /// Names of browsers that were open at the last check; their data stays locked.
    private(set) var runningBrowsers: Set<String> = []
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    private(set) var isCleaning = false
    private(set) var hasFullDiskAccess = true
    /// Nothing is ever picked for the user: every item starts unticked.
    var selected: Set<String> = []
    var toast: ToastMessage?

    var selectedItems: [PrivacyItem] {
        browsers.flatMap(\.items).filter { selected.contains($0.id) && $0.isSupported && !runningBrowsers.contains($0.browserName) }
    }

    var selectedSize: Int64 { selectedItems.reduce(0) { $0 + $1.size } }
    /// Form data is deleted from inside a database, so it can't go to the Trash.
    var selectionIncludesPermanent: Bool {
        selectedItems.contains { if case .clearAutofill = $0.action { true } else { false } }
    }

    func load() async {
        isLoading = true
        refreshRunning()
        hasFullDiskAccess = Permissions.hasFullDiskAccess
        let found = await Task.detached(priority: .userInitiated) { PrivacyScanner().scan() }.value
        withAnimation(.smooth) {
            browsers = found
            selected = selected.filter { id in found.contains { $0.items.contains { $0.id == id } } }
            isLoading = false
            hasLoaded = true
        }
    }

    func refreshRunning() {
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        runningBrowsers = Set(Browser.all.filter { !running.isDisjoint(with: $0.bundleIDs) }.map(\.name))
    }

    func isLocked(_ item: PrivacyItem) -> Bool {
        !item.isSupported || runningBrowsers.contains(item.browserName)
    }

    func toggle(_ item: PrivacyItem) {
        guard !isLocked(item) else { return }
        if selected.contains(item.id) { selected.remove(item.id) } else { selected.insert(item.id) }
    }

    func clean() async {
        // A browser opened after the scan would rewrite or lock its files mid-way, so check again.
        refreshRunning()
        let items = selectedItems
        guard !items.isEmpty else {
            toast = ToastMessage(text: L("Tutup browser-nya dulu, lalu coba lagi", "Quit the browser first, then try again"),
                                 symbol: "lock.fill", colors: Palette.berry)
            return
        }
        isCleaning = true
        let result = await PrivacyCleaner.clean(items, source: Module.privacy.title)
        isCleaning = false
        selected = []

        var text = result.report.movedCount > 0 ? result.report.summaryText : ""
        if result.clearedEntries > 0 || items.contains(where: { if case .clearAutofill = $0.action { true } else { false } }) {
            let forms = L("\(result.clearedEntries) isian formulir dihapus", "\(result.clearedEntries) form entries cleared")
            text = text.isEmpty ? forms : "\(text) · \(forms)"
        }
        if result.failedDatabases > 0 {
            text += L(" · \(result.failedDatabases) database terkunci", " · \(result.failedDatabases) databases locked")
        }
        let problem = !result.report.failed.isEmpty || !result.report.blocked.isEmpty || result.failedDatabases > 0
        toast = ToastMessage(text: text, symbol: problem ? "exclamationmark.triangle.fill" : "checkmark.circle.fill", colors: Module.privacy.colors)
        await load()
    }
}
