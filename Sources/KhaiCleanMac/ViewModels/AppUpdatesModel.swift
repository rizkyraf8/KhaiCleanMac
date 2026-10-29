import AppKit
import SwiftUI

@MainActor @Observable
final class AppUpdatesModel {
    enum Phase { case idle, checking, results }

    private(set) var phase: Phase = .idle
    private(set) var updates: [AvailableUpdate] = []
    private(set) var upToDate: [UpdatableApp] = []
    /// Apps whose feed couldn't be reached or read.
    private(set) var unreachable: [UpdatableApp] = []
    private(set) var appStoreApps: [UpdatableApp] = []
    private(set) var otherApps: [UpdatableApp] = []
    private(set) var checkedCount = 0
    private(set) var feedCount = 0
    private(set) var lastChecked: Date?

    private var task: Task<Void, Never>?
    /// Feeds are fetched a few at a time, so one slow server doesn't hold up the rest.
    private static let parallelFeeds = 8

    func check() {
        task?.cancel()
        withAnimation(.smooth) { phase = .checking }
        updates = []
        upToDate = []
        unreachable = []
        checkedCount = 0
        feedCount = 0
        task = Task { [weak self] in
            let apps = await Task.detached(priority: .userInitiated) {
                AppUpdateScanner.updatableApps(AppScanner().installedApps())
            }.value
            guard let self, !Task.isCancelled else { return }
            appStoreApps = apps.filter { $0.source == .appStore }
            otherApps = apps.filter { $0.source == .unknown }
            let feeds = apps.compactMap { app -> (UpdatableApp, URL)? in
                if case .sparkle(let feed) = app.source { return (app, feed) }
                return nil
            }
            feedCount = feeds.count

            // No cookies or cache: every check is a plain, fresh request for the feed.
            let session = URLSession(configuration: .ephemeral)
            defer { session.invalidateAndCancel() }
            await withTaskGroup(of: (UpdatableApp, AppcastRelease?).self) { group in
                var pending = feeds.makeIterator()
                func addNext() {
                    guard let (app, feed) = pending.next() else { return }
                    group.addTask { (app, await AppUpdateScanner.fetchRelease(feed: feed, session: session)) }
                }
                for _ in 0..<Self.parallelFeeds { addNext() }
                for await (app, release) in group {
                    if Task.isCancelled { group.cancelAll(); return }
                    checkedCount += 1
                    if let release {
                        if let update = AppUpdateScanner.update(for: app, release: release) {
                            withAnimation(.snappy) { updates.append(update) }
                        } else {
                            upToDate.append(app)
                        }
                    } else {
                        unreachable.append(app)
                    }
                    addNext()
                }
            }
            guard !Task.isCancelled else { return }
            updates.sort { $0.app.app.name.localizedCaseInsensitiveCompare($1.app.app.name) == .orderedAscending }
            upToDate.sort { $0.app.name.localizedCaseInsensitiveCompare($1.app.name) == .orderedAscending }
            lastChecked = Date()
            withAnimation(.smooth) { phase = .results }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        withAnimation(.smooth) { phase = .idle }
    }

    /// The app installs its own update: Sparkle checks the signature of what it downloads,
    /// which is safer than KhaiCleanMac fetching installers on its behalf.
    func open(_ app: UpdatableApp) {
        NSWorkspace.shared.openApplication(at: app.app.url, configuration: NSWorkspace.OpenConfiguration())
    }

    func openAppStoreUpdates() {
        if let url = URL(string: "macappstore://showUpdatesPage") { NSWorkspace.shared.open(url) }
    }
}
