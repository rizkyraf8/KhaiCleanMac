import AppKit
import ServiceManagement
import UserNotifications

/// Lets code outside the main window (menu bar, notifications) bring that window back.
@MainActor
enum AppWindow {
    /// Set by the always-present menu bar label, which has SwiftUI's `openWindow` action.
    static var openMain: (() -> Void)?

    static func show() {
        NSApp.setActivationPolicy(.regular)
        openMain?()
        NSApp.activate()
    }
}

enum LoginItem {
    static var status: SMAppService.Status { SMAppService.mainApp.status }

    static var isEnabled: Bool { status == .enabled }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

/// Measures junk in the background and sends a notification when it piles up.
/// It only ever reads sizes: cleaning always happens in the app, with the user's approval.
@MainActor
final class ReminderService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = ReminderService()

    private var loop: Task<Void, Never>?

    /// Notifications need a real app bundle; a bare `swift run` binary has none and would crash.
    var isAvailable: Bool { Bundle.main.bundleIdentifier != nil }

    func start() {
        guard isAvailable, loop == nil else { return }
        UNUserNotificationCenter.current().delegate = self
        loop = Task {
            while !Task.isCancelled {
                await checkIfDue()
                try? await Task.sleep(for: .seconds(60 * 60))
            }
        }
    }

    func requestPermission() async -> Bool {
        guard isAvailable else { return false }
        return (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    private func checkIfDue() async {
        let settings = AppSettings.shared
        guard settings.remindersEnabled else { return }
        if let last = settings.lastReminderCheck, Date().timeIntervalSince(last) < settings.reminderFrequency.interval { return }
        await check(notify: true)
    }

    /// Returns the junk total; posts a notification when `notify` is set and the total passes the threshold.
    @discardableResult
    func check(notify: Bool) async -> Int64 {
        let chromeMaxAgeDays = AppSettings.shared.chromeCacheAge.rawValue
        let total = await Task.detached(priority: .utility) {
            let scanner = JunkScanner(chromeMaxAgeDays: chromeMaxAgeDays)
            return [JunkKind.userCache, .browsers, .userLogs, .developer].reduce(Int64(0)) { sum, kind in
                sum + scanner.scan(kind).reduce(0) { $0 + $1.size }
            }
        }.value
        AppSettings.shared.lastReminderCheck = Date()
        if notify, total >= AppSettings.shared.reminderThreshold.rawValue {
            await post(total)
        }
        return total
    }

    private func post(_ total: Int64) async {
        guard isAvailable else { return }
        let content = UNMutableNotificationContent()
        content.title = L("Saatnya bersih-bersih Mac", "Time to tidy up your Mac")
        content.body = L("Ada sekitar \(total.formattedBytes) sampah yang bisa dibersihkan. Buka KhaiCleanMac untuk melihat dan memilihnya.",
                         "About \(total.formattedBytes) of junk can be cleaned. Open KhaiCleanMac to review and pick what goes.")
        content.sound = .default
        let request = UNNotificationRequest(identifier: "junk-reminder", content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        await MainActor.run { AppWindow.show() }
    }
}
