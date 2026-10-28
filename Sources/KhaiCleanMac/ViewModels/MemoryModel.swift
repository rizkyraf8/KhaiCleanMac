import SwiftUI

@MainActor @Observable
final class MemoryModel {
    private(set) var stats: MemoryStats?
    private(set) var apps: [AppMemoryUsage] = []
    private(set) var quittable: Set<URL> = []
    private(set) var isPurging = false
    var toast: ToastMessage?

    /// Refreshes every few seconds while the module is on screen; the caller's task stops it.
    func monitor() async {
        while !Task.isCancelled {
            await refresh()
            try? await Task.sleep(for: .seconds(3))
        }
    }

    func refresh() async {
        let (stats, apps) = await Task.detached(priority: .utility) {
            (MemoryStats.read(), AppMemoryScanner.topApps())
        }.value
        withAnimation(.smooth) {
            self.stats = stats
            self.apps = apps
            quittable = Set(apps.filter(MemoryActions.canQuit).map(\.bundleURL))
        }
    }

    func quit(_ app: AppMemoryUsage) async {
        if MemoryActions.quit(app) {
            toast = ToastMessage(
                text: L("\(app.name) diminta keluar. Kalau ada pekerjaan yang belum disimpan, app itu akan bertanya dulu.",
                        "Asked \(app.name) to quit. If it has unsaved work, it will ask you first."),
                symbol: "power", colors: Module.memory.colors
            )
        }
        try? await Task.sleep(for: .seconds(1.5))
        await refresh()
    }

    func purge() async {
        isPurging = true
        let before = stats?.cached ?? 0
        let succeeded = await Task.detached(priority: .userInitiated) { MemoryActions.purgeCachedFiles() }.value
        await refresh()
        isPurging = false
        let released = before > (stats?.cached ?? 0) ? before - (stats?.cached ?? 0) : 0
        toast = succeeded
            ? ToastMessage(
                text: L("\(released.formattedMemory) cache file dilepas", "Released \(released.formattedMemory) of cached files"),
                colors: Module.memory.colors)
            : ToastMessage(
                text: L("Dibatalkan. Tidak ada yang berubah.", "Cancelled. Nothing changed."),
                symbol: "xmark.circle.fill", colors: Palette.slate)
    }
}
