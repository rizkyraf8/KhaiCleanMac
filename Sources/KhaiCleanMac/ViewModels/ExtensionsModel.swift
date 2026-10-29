import SwiftUI

@MainActor @Observable
final class ExtensionsModel {
    private(set) var extensions: [AppExtension] = []
    private(set) var plugins: [LegacyPlugin] = []
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    private(set) var busy: Set<String> = []
    var toast: ToastMessage?

    var enabledCount: Int { extensions.count(where: \.isEnabled) }
    var userPlugins: [LegacyPlugin] { plugins.filter { !$0.isSystem } }
    var systemPlugins: [LegacyPlugin] { plugins.filter(\.isSystem) }

    /// Extensions grouped by kind, in a stable order.
    var groups: [(kind: ExtensionKind, items: [AppExtension])] {
        ExtensionKind.allCases.compactMap { kind in
            let items = extensions.filter { $0.kind == kind }
            return items.isEmpty ? nil : (kind, items)
        }
    }

    func load() async {
        isLoading = true
        let (extensions, plugins) = await Task.detached(priority: .userInitiated) {
            (ExtensionScanner.appExtensions(), ExtensionScanner.legacyPlugins())
        }.value
        withAnimation(.smooth) {
            self.extensions = extensions
            self.plugins = plugins
            isLoading = false
            hasLoaded = true
        }
    }

    func toggle(_ ext: AppExtension) async {
        busy.insert(ext.id)
        let enable = !ext.isEnabled
        let succeeded = await Task.detached(priority: .userInitiated) { ExtensionActions.setEnabled(ext, enable) }.value
        busy.remove(ext.id)
        if succeeded, let index = extensions.firstIndex(where: { $0.id == ext.id }) {
            withAnimation(.snappy) { extensions[index].election = enable ? .enabled : .disabled }
            toast = ToastMessage(
                text: enable ? L("\(ext.name) dinyalakan", "\(ext.name) is on") : L("\(ext.name) dimatikan", "\(ext.name) is off"),
                symbol: enable ? "checkmark.circle.fill" : "pause.circle.fill", colors: Module.extensions.colors)
        } else if !succeeded {
            toast = ToastMessage(text: L("Gagal mengubah \(ext.name)", "Couldn't change \(ext.name)"),
                                 symbol: "exclamationmark.triangle.fill", colors: Palette.berry)
        }
    }

    func remove(_ plugin: LegacyPlugin) async {
        guard !plugin.isSystem else { return }
        busy.insert(plugin.url.path)
        let report = await Trasher.removeRecorded([CleanItem(url: plugin.url, size: plugin.size)], source: Module.extensions.title)
        busy.remove(plugin.url.path)
        toast = ToastMessage(text: report.summaryText,
                             symbol: report.failed.isEmpty && report.blocked.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                             colors: Module.extensions.colors)
        await load()
    }
}
