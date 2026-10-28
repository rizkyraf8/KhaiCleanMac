import SwiftUI

enum AppInfo {
    static let bundleID = "com.khai.KhaiCleanMac"
    static let name = "KhaiCleanMac"
}

@main
struct KhaiCleanMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var monitor = SystemMonitor()

    var body: some Scene {
        Window(AppInfo.name, id: "main") {
            ContentView()
                .environment(\.locale, Locale(identifier: "id_ID"))
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .windowBackgroundDragBehavior(.enabled)
        .defaultSize(width: 1120, height: 760)

        MenuBarExtra {
            MenuBarView(monitor: monitor)
                .environment(\.locale, Locale(identifier: "id_ID"))
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
        NSApp.activate()
        #if DEBUG
        Snapshot.runIfRequested()
        #endif
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
