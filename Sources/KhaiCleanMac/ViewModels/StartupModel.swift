import SwiftUI

@MainActor @Observable
final class StartupModel {
    private(set) var userAgents: [StartupItem] = []
    private(set) var systemItems: [StartupItem] = []
    /// `nil` until the user asks to load them, because that triggers a macOS permission prompt.
    private(set) var loginItems: [StartupItem]?
    private(set) var loginItemsDenied = false
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    private(set) var busyIDs: Set<String> = []
    var toast: ToastMessage?

    var orphanCount: Int { (userAgents + systemItems + (loginItems ?? [])).count(where: \.isOrphan) }
    var activeUserAgentCount: Int { userAgents.count { !$0.isDisabled } }

    func load() async {
        isLoading = true
        let (user, system) = await Task.detached(priority: .userInitiated) {
            let guiDomain = "gui/\(getuid())"
            let userDisabled = StartupScanner.disabledLabels(domain: guiDomain)
            let systemDisabled = StartupScanner.disabledLabels(domain: "system")
            let user = StartupScanner.launchdItems(in: StartupScanner.userAgentsFolder, kind: .userAgent, disabled: userDisabled)
            let system = StartupScanner.launchdItems(in: StartupScanner.systemAgentsFolder, kind: .systemAgent, disabled: userDisabled)
                + StartupScanner.launchdItems(in: StartupScanner.systemDaemonsFolder, kind: .systemDaemon, disabled: systemDisabled)
            return (user, system)
        }.value
        withAnimation(.smooth) {
            userAgents = user
            systemItems = system
            isLoading = false
            hasLoaded = true
        }
        if loginItems != nil { await loadLoginItems() }
    }

    func loadLoginItems() async {
        let items = await Task.detached(priority: .userInitiated) { StartupScanner.loginItems() }.value
        withAnimation(.smooth) {
            loginItems = items
            loginItemsDenied = items == nil
        }
    }

    func toggle(_ item: StartupItem) async {
        busyIDs.insert(item.id)
        let disable = !item.isDisabled
        let succeeded = await Task.detached(priority: .userInitiated) { StartupActions.setDisabled(item, disable) }.value
        busyIDs.remove(item.id)
        if succeeded, let index = userAgents.firstIndex(where: { $0.id == item.id }) {
            withAnimation(.snappy) { userAgents[index].isDisabled = disable }
            toast = ToastMessage(
                text: disable
                    ? L("\(item.name) dimatikan dan tidak akan jalan lagi saat login", "\(item.name) is off and won't start at login")
                    : L("\(item.name) dinyalakan lagi", "\(item.name) is back on"),
                symbol: disable ? "pause.circle.fill" : "play.circle.fill", colors: Module.startup.colors)
        } else if !succeeded {
            toast = ToastMessage(text: L("Gagal mengubah \(item.name)", "Couldn't change \(item.name)"),
                                 symbol: "exclamationmark.triangle.fill", colors: Palette.berry)
        }
    }

    func remove(_ item: StartupItem) async {
        busyIDs.insert(item.id)
        if item.kind == .loginItem {
            let succeeded = await Task.detached(priority: .userInitiated) { StartupActions.removeLoginItem(item) }.value
            busyIDs.remove(item.id)
            toast = succeeded
                ? ToastMessage(text: L("\(item.name) tidak lagi dibuka saat login", "\(item.name) no longer opens at login"), colors: Module.startup.colors)
                : ToastMessage(text: L("Gagal menghapus \(item.name)", "Couldn't remove \(item.name)"), symbol: "exclamationmark.triangle.fill", colors: Palette.berry)
            await loadLoginItems()
        } else {
            let report = await Task.detached(priority: .userInitiated) { StartupActions.remove(item) }.value
            CleanHistory.shared.record(report, source: Module.startup.title)
            busyIDs.remove(item.id)
            toast = ToastMessage(text: report.summaryText,
                                 symbol: report.isComplete ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                                 colors: Module.startup.colors)
            await load()
        }
    }
}
