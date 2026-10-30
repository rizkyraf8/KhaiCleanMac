import SwiftUI

struct MenuBarLabel: View {
    let monitor: SystemMonitor
    let scan: SmartScanModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        HStack(spacing: 3) {
            Image(nsImage: LogoArtwork.menuBarImage())
            // A running scan, and then its unopened results, take the place of the CPU reading.
            if scan.phase == .scanning {
                Image(systemName: "sparkle.magnifyingglass")
                Text("\(Int(scan.progress * 100))%")
                    .monospacedDigit()
            } else if scan.phase == .results && scan.hasUnseenResults {
                Image(systemName: "checkmark.circle.fill")
                Text(scan.totalSize.formattedBytes)
                    .monospacedDigit()
            } else {
                Text("\(Int(monitor.cpu * 100))%")
                    .monospacedDigit()
            }
        }
        // The label lives as long as the app, so it hands out the way to reopen the window.
        .onAppear { AppWindow.openMain = { openWindow(id: "main") } }
    }
}

struct MenuBarView: View {
    let monitor: SystemMonitor
    let scan: SmartScanModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                AppLogo(size: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(AppInfo.name)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                    Text(L("Kondisi Mac kamu saat ini", "How your Mac is doing"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            MeterRow(title: "CPU", symbol: "cpu", value: "\(Int(monitor.cpu * 100))%", fraction: monitor.cpu, colors: Palette.mint)
            MeterRow(
                title: L("Memori", "Memory"), symbol: "memorychip",
                value: "\(Self.memory(monitor.memoryUsed)) / \(Self.memory(monitor.memoryTotal))",
                fraction: monitor.memoryFraction, colors: Palette.lavender
            )
            if let disk = monitor.disk {
                MeterRow(
                    title: "Disk", symbol: "internaldrive",
                    value: L("\(disk.available.formattedBytes) tersedia", "\(disk.available.formattedBytes) free"),
                    fraction: disk.usedFraction, colors: Palette.peach
                )
            }
            if let battery = monitor.battery {
                MeterRow(
                    title: L("Baterai", "Battery"), symbol: battery.isCharging ? "battery.100percent.bolt" : "battery.75percent",
                    value: "\(battery.percent)%" + (battery.isCharging ? L(" · mengisi", " · charging") : ""),
                    fraction: Double(battery.percent) / 100, colors: Palette.leaf
                )
            }
            HealthSummaryRow()

            Divider()

            ScanStatusCard(scan: scan)

            Divider()

            HStack {
                Button {
                    AppWindow.show()
                } label: {
                    Label(L("Buka KhaiCleanMac", "Open KhaiCleanMac"), systemImage: "macwindow")
                }
                .buttonStyle(GradientButtonStyle(colors: Palette.lavender))
                Spacer()
                Button(L("Keluar", "Quit")) { NSApp.terminate(nil) }
                    .buttonStyle(SoftButtonStyle())
            }
        }
        .padding(18)
        .frame(width: 320)
    }

    private static func memory(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .memory)
    }
}

/// The Smart Scan shared with the main window: start one, follow it, and open its results.
/// It only ever scans; cleaning stays in the window, behind the usual confirmation.
private struct ScanStatusCard: View {
    let scan: SmartScanModel
    private let colors = Module.smartScan.colors

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                GradientIcon(symbol: "sparkles", colors: colors, size: 30, corner: 9)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                    Text(caption)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            switch scan.phase {
            case .scanning:
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.08))
                        Capsule()
                            .fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
                            .frame(width: geo.size.width * scan.progress)
                    }
                }
                .frame(height: 6)
                .animation(.smooth, value: scan.progress)
            case .cleaning:
                ProgressView()
                    .progressViewStyle(.linear)
                    .tint(colors[1])
            default:
                EmptyView()
            }

            HStack(spacing: 8) {
                switch scan.phase {
                case .idle, .done:
                    Button {
                        scan.start()
                    } label: {
                        Label("Smart Scan", systemImage: "sparkles")
                    }
                    .buttonStyle(GradientButtonStyle(colors: colors))
                case .scanning:
                    Button(L("Hentikan", "Stop")) { scan.cancel() }
                        .buttonStyle(SoftButtonStyle())
                    Button(L("Tampilkan", "Show")) { AppRouter.shared.show(.smartScan) }
                        .buttonStyle(SoftButtonStyle())
                case .results:
                    Button {
                        AppRouter.shared.show(.smartScan)
                    } label: {
                        Label(L("Lihat hasil", "See results"), systemImage: "list.bullet.rectangle")
                    }
                    .buttonStyle(GradientButtonStyle(colors: colors))
                    Button(L("Pindai Ulang", "Scan Again")) { scan.start() }
                        .buttonStyle(SoftButtonStyle())
                case .cleaning:
                    Button(L("Tampilkan", "Show")) { AppRouter.shared.show(.smartScan) }
                        .buttonStyle(SoftButtonStyle())
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var title: String {
        switch scan.phase {
        case .idle, .done: "Smart Scan"
        case .scanning: L("Memindai… \(scan.categories.count) dari \(JunkKind.allCases.count)", "Scanning… \(scan.categories.count) of \(JunkKind.allCases.count)")
        case .results: L("Pemindaian selesai", "Scan finished")
        case .cleaning: L("Membersihkan…", "Cleaning…")
        }
    }

    private var caption: String {
        switch scan.phase {
        case .idle, .done:
            L("Cari file sampah tanpa membuka jendela. Tidak ada yang dihapus sebelum kamu menyetujuinya.",
              "Look for junk without opening the window. Nothing is removed until you approve it.")
        case .scanning:
            scan.currentKind.map { L("Memeriksa \($0.title.lowercased())…", "Checking \($0.title.lowercased())…") } ?? L("Menyiapkan…", "Getting ready…")
        case .results:
            L("Pemindaian terakhir menemukan \(scan.totalSize.formattedBytes) yang bisa dibersihkan.",
              "The last scan found \(scan.totalSize.formattedBytes) you can clean up.")
        case .cleaning:
            L("Buka jendela untuk melihat hasilnya.", "Open the window to see how it went.")
        }
    }
}

private struct MeterRow: View {
    let title: String
    let symbol: String
    let value: String
    let fraction: Double
    let colors: [Color]

    var body: some View {
        HStack(spacing: 12) {
            GradientIcon(symbol: symbol, colors: colors, size: 30, corner: 9)
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                    Spacer()
                    Text(value)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.08))
                        Capsule()
                            .fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
                            .frame(width: geo.size.width * min(max(fraction, 0), 1))
                    }
                }
                .frame(height: 6)
                .animation(.smooth, value: fraction)
            }
        }
    }
}
