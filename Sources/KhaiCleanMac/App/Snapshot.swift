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
            // The menu bar glyph, enlarged so its details can be checked.
            await render(
                HStack(spacing: 40) {
                    Image(nsImage: LogoArtwork.menuBarImage()).resizable().frame(width: 160, height: 144)
                    Image(nsImage: LogoArtwork.menuBarImage()).frame(width: 20, height: 18)
                }
                .padding(40)
                .background(.background),
                name: "menubar-icon", scheme: scheme, folder: folder, settle: 0.5, size: NSSize(width: 360, height: 240)
            )
            for tab in SettingsTab.allCases {
                await render(SettingsView(tab: tab), name: "settings-\(tab.rawValue)", scheme: scheme, folder: folder,
                             settle: 1, size: NSSize(width: 560, height: 600))
            }
            for step in OnboardingStep.allCases {
                await render(OnboardingView(step: step, onFinish: {}), name: "onboarding-\(step)", scheme: scheme, folder: folder,
                             settle: 1, size: NSSize(width: 760, height: 640))
            }
            for module in Module.allCases {
                await render(ContentView(selection: module), name: module.rawValue, scheme: scheme, folder: folder,
                             settle: module == .uninstaller || module == .spaceLens ? 8 : (module == .memory || module == .home || module == .startup ? 3 : 1.5))
            }
            await render(MenuBarView(monitor: SystemMonitor()).background(.background), name: "menubar", scheme: scheme, folder: folder,
                         settle: 4.5, size: NSSize(width: 320, height: 330))
            if args.contains("--updates") {
                // Real request to rizkyraf.id, then a pretend 0.5.0 to show the "available" screens.
                await UpdateChecker.shared.check()
                await render(SettingsView(tab: .about), name: "update-live", scheme: scheme, folder: folder,
                             settle: 1, size: NSSize(width: 560, height: 600))
                UpdateChecker.shared.preview(LatestRelease(
                    version: AppVersion("0.5.0")!, notes: "Pembersihan Mail, riwayat pembersihan, dan perbaikan kecil.",
                    fileName: "KhaiCleanMac-0.5.0.dmg", size: 2_412_000, downloadURL: UpdateAPI.projectPage, releasedAt: Date(),
                    sha256: String(repeating: "0", count: 64)
                ), installed: AppVersion("0.4.0"))
                await render(SettingsView(tab: .about), name: "update-available", scheme: scheme, folder: folder,
                             settle: 1, size: NSSize(width: 560, height: 600))
                await render(ContentView(selection: .home), name: "update-home", scheme: scheme, folder: folder, settle: 2)
                if let latest = UpdateChecker.shared.latest {
                    UpdateChecker.shared.preview(latest, installed: AppVersion("0.4.0"), step: .verifying)
                    await render(ContentView(selection: .home), name: "update-verifying", scheme: scheme, folder: folder, settle: 2)
                    UpdateChecker.shared.preview(latest, installed: AppVersion("0.4.0"), step: .failed(.checksumMismatch))
                    await render(SettingsView(tab: .about), name: "update-failed", scheme: scheme, folder: folder,
                                 settle: 1, size: NSSize(width: 560, height: 600))
                }
                UpdateChecker.shared.preview(nil, installed: nil)
            }
            if args.contains("--results") {
                // Mid-progress states, caught while the read-only work is still running.
                let scanning = SmartScanModel()
                Task { await scanning.scan() }
                await render(ContentView(selection: .smartScan, smartScan: scanning), name: "smartScan-scanning", scheme: scheme, folder: folder, settle: 2)
                await render(ContentView(selection: .spaceLens), name: "spaceLens-measuring", scheme: scheme, folder: folder, settle: 2.5)
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

                let developer = DeveloperModel()
                developer.scan()
                while developer.phase == .scanning { try? await Task.sleep(for: .milliseconds(300)) }
                await render(ContentView(selection: .developer, developer: developer), name: "developer-results", scheme: scheme, folder: folder, settle: 1.5)
            }
            NSApp.terminate(nil)
        }
    }

    private static func render(_ view: some View, name: String, scheme: NSAppearance.Name, folder: URL, settle: Double,
                               size: NSSize = NSSize(width: 1120, height: 860)) async {
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
