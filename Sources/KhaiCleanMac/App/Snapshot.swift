#if DEBUG
import SwiftUI

/// Debug-only: `KhaiCleanMac --snapshot <folder>` renders every module to PNG and quits.
/// Handy for checking the UI without Screen Recording permission.
@MainActor
enum Snapshot {
    static func runIfRequested() {
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: "--snapshot"), index + 1 < args.count else { return }
        let folder = URL(filePath: args[index + 1])
        let scheme: NSAppearance.Name = args.contains("--dark") ? .darkAqua : .aqua
        if let langIndex = args.firstIndex(of: "--lang"), langIndex + 1 < args.count,
           let language = AppLanguage(rawValue: args[langIndex + 1]) {
            AppSettings.shared.persists = false
            AppSettings.shared.language = language
        }

        Task {
            await render(SettingsView(), name: "settings", scheme: scheme, folder: folder,
                         settle: 1, size: NSSize(width: 540, height: 560))
            for module in Module.allCases {
                await render(ContentView(selection: module), name: module.rawValue, scheme: scheme, folder: folder,
                             settle: module == .uninstaller || module == .spaceLens ? 8 : 1.5)
            }
            await render(MenuBarView(monitor: SystemMonitor()).background(.background), name: "menubar", scheme: scheme, folder: folder,
                         settle: 4.5, size: NSSize(width: 320, height: 330))
            if args.contains("--results") {
                // Read-only: scans and leftover lookups never touch files.
                let smartScan = SmartScanModel()
                await smartScan.scan()
                await render(ContentView(selection: .smartScan, smartScan: smartScan), name: "smartScan-results", scheme: scheme, folder: folder, settle: 1.5)

                let uninstaller = UninstallerModel()
                await uninstaller.load()
                if let app = uninstaller.apps.first(where: { $0.name == "Docker" }) ?? uninstaller.apps.first {
                    uninstaller.select(app)
                }
                await render(ContentView(selection: .uninstaller, uninstaller: uninstaller), name: "uninstaller-detail", scheme: scheme, folder: folder, settle: 5)

                let duplicates = DuplicatesModel()
                duplicates.minSize = .mb10
                duplicates.scan()
                while duplicates.phase == .scanning { try? await Task.sleep(for: .milliseconds(300)) }
                await render(ContentView(selection: .duplicates, duplicates: duplicates), name: "duplicates-results", scheme: scheme, folder: folder, settle: 1.5)
            }
            NSApp.terminate(nil)
        }
    }

    private static func render(_ view: some View, name: String, scheme: NSAppearance.Name, folder: URL, settle: Double,
                               size: NSSize = NSSize(width: 1120, height: 740)) async {
                let window = NSWindow(
                    contentRect: NSRect(origin: .zero, size: size),
                    styleMask: [.titled, .fullSizeContentView],
                    backing: .buffered,
                    defer: false
                )
                window.isReleasedWhenClosed = false
                window.appearance = NSAppearance(named: scheme)
                window.titlebarAppearsTransparent = true
                let host = NSHostingView(rootView: LocalizedRoot { view })
                window.contentView = host
                window.orderBack(nil)
                // Give async loaders (app list, disk info) a moment to settle.
                try? await Task.sleep(for: .seconds(settle))
                host.layoutSubtreeIfNeeded()
                if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                    host.cacheDisplay(in: host.bounds, to: rep)
                    let language = AppSettings.shared.language == .english ? "-en" : ""
                    let suffix = language + (scheme == .darkAqua ? "-dark" : "")
                    try? rep.representation(using: .png, properties: [:])?
                        .write(to: folder.appending(path: "\(name)\(suffix).png"))
                }
                window.close()
    }
}
#endif
