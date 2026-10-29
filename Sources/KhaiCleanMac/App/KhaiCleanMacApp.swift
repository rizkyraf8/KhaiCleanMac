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
            LocalizedRoot { MenuBarView(monitor: monitor) }
        } label: {
            MenuBarLabel(monitor: monitor)
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
        !AppSettings.shared.keepInMenuBar
    }

    /// Clicking the Dock icon (or opening the app again) while only the menu bar is left brings the window back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows { AppWindow.show() }
        return true
    }
}
