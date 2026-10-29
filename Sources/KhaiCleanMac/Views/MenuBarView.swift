import SwiftUI

struct MenuBarLabel: View {
    let monitor: SystemMonitor
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        HStack(spacing: 3) {
            Image(nsImage: LogoArtwork.menuBarImage())
            Text("\(Int(monitor.cpu * 100))%")
                .monospacedDigit()
        }
        // The label lives as long as the app, so it hands out the way to reopen the window.
        .onAppear { AppWindow.openMain = { openWindow(id: "main") } }
    }
}

struct MenuBarView: View {
    let monitor: SystemMonitor
    @Environment(\.openWindow) private var openWindow

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

            HStack {
                Button {
                    NSApp.setActivationPolicy(.regular)
                    openWindow(id: "main")
                    NSApp.activate()
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
