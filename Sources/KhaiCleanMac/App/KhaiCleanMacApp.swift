import SwiftUI

enum AppInfo {
    static let bundleID = "com.khai.KhaiCleanMac"
    static let name = "KhaiCleanMac"
    static let repository = URL(string: "https://github.com/rizkyraf8/KhaiCleanMac")!

    /// Comes from Info.plist. A bare `swift run` binary has no Info.plist, so it shows "dev".
    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }

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
        Snapshot.runIfRequested()
        #endif
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
