import SwiftUI

enum AppInfo {
    static let bundleID = "id.rizkyraf.KhaiCleanMac"
    static let name = "KhaiCleanMac"
    static let repository = URL(string: "https://github.com/rizkyraf8/KhaiCleanMac")!

    /// Comes from Info.plist. A bare `swift run` binary has no Info.plist, so it shows "dev".
    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }

    /// Debug snapshots render windows offscreen; they must not pop up the first-run guide.
    static var isSnapshot: Bool { CommandLine.arguments.contains("--snapshot") }

    static var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
    }
}

@main
struct KhaiCleanMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var monitor = SystemMonitor()

    var body: some Scene {
        Window(AppInfo.name, id: "main") {
            LocalizedRoot { ContentView() }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .windowBackgroundDragBehavior(.enabled)
        .defaultSize(width: 1120, height: 760)

        Settings {
            LocalizedRoot { SettingsView() }
        }

        MenuBarExtra {
            LocalizedRoot { MenuBarView(monitor: monitor, scan: .shared) }
        } label: {
            MenuBarLabel(monitor: monitor, scan: .shared)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when launched as a bare SwiftPM executable (swift run).
        NSApp.setActivationPolicy(.regular)
        NSApp.appearance = AppSettings.shared.appearance.nsAppearance
        NSApp.activate()
        #if DEBUG
        if CommandLine.arguments.contains("--snapshot") {
            Snapshot.runIfRequested()
            return
        }
        #endif
        ReminderService.shared.start()
        Task { await UpdateChecker.shared.checkIfDue() }
    }

    /// The app can stay open in the menu bar for days, so the daily check also runs on return.
    func applicationDidBecomeActive(_ notification: Notification) {
        Task { await UpdateChecker.shared.checkIfDue() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        guard !AppSettings.shared.keepInMenuBar else { return false }
        // Quitting here would quietly throw a running scan away, so ask first.
        guard SmartScanModel.shared.phase == .scanning else { return true }
        let alert = NSAlert()
        alert.messageText = L("Smart Scan masih berjalan", "Smart Scan is still running")
        alert.informativeText = L("Menutup jendela akan menutup KhaiCleanMac dan menghentikan pemindaian. Biarkan berjalan, lalu klik ikon Dock untuk melihat hasilnya. Aktifkan \"Tetap di menu bar\" di Pengaturan agar pemindaian bisa berlanjut di menu bar.",
                                  "Closing the window quits KhaiCleanMac and stops the scan. Keep it running and click the Dock icon to see the results. Turn on \"Keep running in the menu bar\" in Settings to let scans carry on from the menu bar.")
        alert.addButton(withTitle: L("Lanjutkan Pemindaian", "Keep Scanning"))
        alert.addButton(withTitle: L("Hentikan dan Keluar", "Stop and Quit"))
        return alert.runModal() == .alertSecondButtonReturn
    }

    /// Clicking the Dock icon (or opening the app again) while only the menu bar is left brings the window back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows { AppWindow.show() }
        return true
    }
}
