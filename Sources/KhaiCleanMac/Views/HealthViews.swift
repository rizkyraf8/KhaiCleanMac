import SwiftUI

extension BatteryHealth {
    var conditionTitle: String {
        switch condition {
        case .normal: L("Normal", "Normal")
        case .serviceRecommended: L("Perlu servis", "Service recommended")
        case .other(let text): text
        }
    }

    var colors: [Color] {
        switch condition {
        case .serviceRecommended: Palette.berry
        case .other: Palette.sunny
        case .normal: (maximumCapacity ?? 100) < 80 ? Palette.sunny : Palette.leaf
        }
    }

    var cyclesText: String {
        if let design = designCycleCount {
            return L("\(cycleCount) dari \(design) siklus", "\(cycleCount) of \(design) cycles")
        }
        return L("\(cycleCount) siklus", "\(cycleCount) cycles")
    }
}

extension DiskHealth {
    var statusTitle: String {
        switch status {
        case .verified: L("Sehat", "Healthy")
        case .failing: L("Bermasalah", "Failing")
        case .notSupported: L("Tidak diketahui", "Unknown")
        }
    }

    var statusDetail: String {
        switch status {
        case .verified: L("Pemeriksaan S.M.A.R.T. lolos", "S.M.A.R.T. check passed")
        case .failing: L("Segera backup datamu dan bawa ke servis", "Back up your data now and get it serviced")
        case .notSupported: L("Disk ini tidak melaporkan S.M.A.R.T.", "This disk doesn't report S.M.A.R.T.")
        }
    }

    var colors: [Color] {
        switch status {
        case .verified: Palette.mint
        case .failing: Palette.berry
        case .notSupported: Palette.slate
        }
    }
}

/// Battery wear and startup disk health, read once: neither changes from minute to minute.
@MainActor @Observable
final class HealthModel {
    static let shared = HealthModel()

    private(set) var battery: BatteryHealth?
    private(set) var disk: DiskHealth?
    private(set) var hasLoaded = false
    private var lastLoad: Date?

    /// Reads again only when the last reading is over an hour old.
    func refreshIfNeeded() async {
        if let lastLoad, Date().timeIntervalSince(lastLoad) < 60 * 60 { return }
        lastLoad = Date()
        let (battery, disk) = await Task.detached(priority: .utility) {
            (HealthReader.battery(), HealthReader.startupDisk())
        }.value
        withAnimation(.smooth) {
            self.battery = battery
            self.disk = disk
            hasLoaded = true
        }
    }
}

/// The Home card: battery wear on the left (laptops only), the startup disk on the right.
struct HealthCard: View {
    private var model: HealthModel { .shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(L("Kesehatan Mac", "Mac health"), systemImage: "heart.text.square")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
            if !model.hasLoaded {
                ProgressView().controlSize(.small)
            } else {
                HStack(alignment: .top, spacing: 16) {
                    if let battery = model.battery {
                        batteryPart(battery)
                    }
                    if model.battery != nil && model.disk != nil {
                        Rectangle().fill(Color.primary.opacity(0.06)).frame(width: 1)
                    }
                    if let disk = model.disk {
                        diskPart(disk)
                    }
                    if model.battery == nil && model.disk == nil {
                        Text(L("Info kesehatan tidak tersedia di Mac ini.", "Health info isn't available on this Mac."))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .softCard(padding: 16)
        .task { await model.refreshIfNeeded() }
    }

    private func batteryPart(_ battery: BatteryHealth) -> some View {
        HStack(alignment: .top, spacing: 12) {
            GradientIcon(symbol: "battery.100percent", colors: battery.colors, size: 38, corner: 11)
            VStack(alignment: .leading, spacing: 4) {
                Text(L("Baterai", "Battery"))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(battery.maximumCapacity.map { "\($0)%" } ?? "—")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                    Text(battery.conditionTitle)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(battery.colors[1])
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(battery.colors[1].opacity(0.15)))
                }
                Text(L("Kapasitas maksimum dibanding saat baru · \(battery.cyclesText)",
                       "Maximum capacity compared to new · \(battery.cyclesText)"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .help(L("Angka yang sama dengan Pengaturan Sistem › Baterai. Di bawah 80%, baterai mulai terasa cepat habis.",
                "The same figure as System Settings › Battery. Below 80%, the battery starts to run down noticeably faster."))
    }

    private func diskPart(_ disk: DiskHealth) -> some View {
        HStack(alignment: .top, spacing: 12) {
            GradientIcon(symbol: disk.isSolidState ? "internaldrive.fill" : "externaldrive.fill", colors: disk.colors, size: 38, corner: 11)
            VStack(alignment: .leading, spacing: 4) {
                Text(disk.isSolidState ? "SSD" : "Disk")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Text(disk.statusTitle)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(LinearGradient.soft(disk.colors))
                Text("\(disk.statusDetail) · \(disk.name)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One compact line for the menu bar panel.
struct HealthSummaryRow: View {
    private var model: HealthModel { .shared }

    var body: some View {
        Group {
            if model.battery != nil || model.disk != nil {
                HStack(spacing: 14) {
                    if let battery = model.battery {
                        item(symbol: "heart.fill", colors: battery.colors,
                             text: L("Baterai \(battery.maximumCapacity.map { "\($0)%" } ?? battery.conditionTitle) · \(battery.cycleCount) siklus",
                                     "Battery \(battery.maximumCapacity.map { "\($0)%" } ?? battery.conditionTitle) · \(battery.cycleCount) cycles"))
                    }
                    if let disk = model.disk {
                        item(symbol: "internaldrive", colors: disk.colors,
                             text: "\(disk.isSolidState ? "SSD" : "Disk") \(disk.statusTitle.lowercased())")
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .task { await model.refreshIfNeeded() }
    }

    private func item(symbol: String, colors: [Color], text: String) -> some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: symbol).foregroundStyle(LinearGradient.soft(colors))
        }
        .font(.system(size: 11, weight: .medium, design: .rounded))
        .foregroundStyle(.secondary)
    }
}
