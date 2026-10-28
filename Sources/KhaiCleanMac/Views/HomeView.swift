import SwiftUI

/// The starting point: how the Mac is doing, a one-click Smart Scan, and every feature.
struct HomeView: View {
    let smartScan: SmartScanModel
    let onOpen: (Module) -> Void
    let onQuickScan: () -> Void

    @State private var disk: DiskInfo?
    @State private var memory: MemoryStats?
    @State private var hasAccess = true

    private var settings: AppSettings { .shared }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                if settings.deletesPermanently { permanentBanner }
                HStack(alignment: .top, spacing: 16) {
                    scanCard
                    VStack(spacing: 16) {
                        diskCard
                        memoryCard
                    }
                    .frame(width: 300)
                }
                if !hasAccess { accessCard }
                Text(L("Semua fitur", "All features"))
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .padding(.top, 4)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                    ForEach(Module.allCases.filter { $0 != .home }) { module in
                        FeatureCard(module: module) { onOpen(module) }
                    }
                }
            }
            .padding(4)
        }
        .scrollIndicators(.never)
        .task {
            while !Task.isCancelled {
                let (disk, memory, access) = await Task.detached(priority: .utility) {
                    (DiskInfo.current(), MemoryStats.read(), Permissions.hasFullDiskAccess)
                }.value
                withAnimation(.smooth) {
                    self.disk = disk
                    self.memory = memory
                    hasAccess = access
                }
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 14) {
            AppLogo(size: 50)
            VStack(alignment: .leading, spacing: 2) {
                Text(greeting)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                Text(L("Ini kondisi Mac kamu hari ini.", "Here's how your Mac is doing today."))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 4..<11: L("Selamat pagi!", "Good morning!")
        case 11..<15: L("Selamat siang!", "Good afternoon!")
        case 15..<18: L("Selamat sore!", "Good afternoon!")
        default: L("Selamat malam!", "Good evening!")
        }
    }

    // MARK: Cards

    private var scanCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            GradientIcon(symbol: "sparkles", colors: Module.smartScan.colors, size: 52)
            Text(L("Bersihkan Mac dalam satu klik", "Clean your Mac in one click"))
                .font(.system(size: 22, weight: .heavy, design: .rounded))
            Text(scanSummary)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            HStack(spacing: 10) {
                Button(action: onQuickScan) {
                    Label(L("Jalankan Smart Scan", "Run Smart Scan"), systemImage: "sparkles")
                }
                .buttonStyle(GradientButtonStyle(colors: Module.smartScan.colors))
                .disabled(smartScan.phase == .scanning || smartScan.phase == .cleaning)
                if smartScan.phase == .results {
                    Button(L("Lihat hasil", "See results")) { onOpen(.smartScan) }
                        .buttonStyle(SoftButtonStyle())
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .softCard(padding: 22)
    }

    private var scanSummary: String {
        switch smartScan.phase {
        case .results:
            L("Pemindaian terakhir menemukan \(smartScan.totalSize.formattedBytes) yang bisa dibersihkan.",
              "The last scan found \(smartScan.totalSize.formattedBytes) you can clean up.")
        case .scanning:
            L("Sedang memindai…", "Scanning…")
        default:
            L("Cache, log, sisa browser, installer lama, dan lainnya. Kamu tetap memilih apa yang dihapus.",
              "Caches, logs, browser leftovers, old installers and more. You still pick what goes.")
        }
    }

    private var diskCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Macintosh HD", systemImage: "internaldrive")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
            if let disk {
                Text(L("\(disk.available.formattedBytes) tersedia", "\(disk.available.formattedBytes) free"))
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
                Meter(fraction: disk.usedFraction, colors: Palette.logo)
                Text(L("dari \(disk.total.formattedBytes)", "of \(disk.total.formattedBytes)"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .softCard(padding: 16)
        .onTapGesture { onOpen(.spaceLens) }
    }

    private var memoryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(L("Memori", "Memory"), systemImage: "memorychip")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
            if let memory {
                Text(pressureTitle(memory.pressure))
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(LinearGradient.soft(pressureColors(memory.pressure)))
                Meter(fraction: Double(memory.used) / Double(max(memory.total, 1)), colors: pressureColors(memory.pressure))
                Text(L("\(memory.used.formattedMemory) dari \(memory.total.formattedMemory) terpakai", "\(memory.used.formattedMemory) of \(memory.total.formattedMemory) in use"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .softCard(padding: 16)
        .onTapGesture { onOpen(.memory) }
    }

    private var accessCard: some View {
        HStack(spacing: 14) {
            GradientIcon(symbol: "lock.shield.fill", colors: Palette.peach, size: 40, corner: 12)
            VStack(alignment: .leading, spacing: 2) {
                Text(L("Akses Disk Penuh belum aktif", "Full Disk Access is off"))
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                Text(L("Trash, backup iOS, dan cache Safari belum bisa diperiksa. Panduannya hanya butuh satu menit.",
                       "The Trash, iOS backups and Safari's cache can't be checked yet. The guide takes about a minute."))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button(L("Buka panduan", "Open guide")) { AppRouter.shared.showOnboarding(at: .access) }
                .buttonStyle(GradientButtonStyle(colors: Palette.peach))
        }
        .softCard(padding: 16)
    }

    private var permanentBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Palette.berry[1])
            Text(L("Mode hapus permanen aktif. File yang dibersihkan tidak masuk Trash.", "Delete permanently is on. Cleaned files skip the Trash."))
                .font(.system(size: 12, weight: .semibold))
            Spacer()
            SettingsLink {
                Text(L("Ubah", "Change"))
            }
            .buttonStyle(.link)
            .font(.system(size: 12, weight: .semibold))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Palette.berry[0].opacity(0.18)))
    }

    private func pressureTitle(_ pressure: MemoryPressure) -> String {
        switch pressure {
        case .normal: L("Lega", "Comfortable")
        case .warning: L("Mulai penuh", "Getting full")
        case .critical: L("Kritis", "Critical")
        }
    }

    private func pressureColors(_ pressure: MemoryPressure) -> [Color] {
        switch pressure {
        case .normal: Palette.mint
        case .warning: Palette.sunny
        case .critical: Palette.berry
        }
    }
}

private struct Meter: View {
    let fraction: Double
    let colors: [Color]

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
                    .frame(width: geo.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(height: 7)
    }
}

private struct FeatureCard: View {
    let module: Module
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    GradientIcon(symbol: module.symbol, colors: module.colors, size: 40, corner: 12)
                    Spacer()
                    Image(systemName: "arrow.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .offset(x: isHovering ? 3 : 0)
                }
                Text(module.title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                Text(module.subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2, reservesSpace: true)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .softCard(padding: 16, radius: 18)
            .scaleEffect(isHovering ? 1.015 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in withAnimation(.snappy(duration: 0.2)) { isHovering = hovering } }
    }
}
