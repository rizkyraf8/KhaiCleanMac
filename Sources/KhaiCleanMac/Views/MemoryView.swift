import SwiftUI

struct MemoryView: View {
    @Bindable var model: MemoryModel
    @State private var pendingQuit: AppMemoryUsage?
    @State private var confirmPurge = false
    private let module = Module.memory

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ModuleHeader(module: module) {
                Button {
                    Task { await model.refresh() }
                } label: {
                    Label(L("Segarkan", "Refresh"), systemImage: "arrow.clockwise")
                }
                .buttonStyle(SoftButtonStyle())
            }

            if let stats = model.stats {
                HStack(alignment: .top, spacing: 16) {
                    PressureCard(stats: stats)
                        .frame(width: 300)
                    BreakdownCard(stats: stats)
                }
                .fixedSize(horizontal: false, vertical: true)

                HStack(alignment: .top, spacing: 16) {
                    appList
                    purgeCard(stats: stats)
                        .frame(width: 300)
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .toast($model.toast)
        .task { await model.monitor() }
        .alert(
            L("Keluar dari \(pendingQuit?.name ?? "")?", "Quit \(pendingQuit?.name ?? "")?"),
            isPresented: Binding(get: { pendingQuit != nil }, set: { if !$0 { pendingQuit = nil } }),
            presenting: pendingQuit
        ) { app in
            Button(L("Keluar", "Quit")) { Task { await model.quit(app) } }
            Button(L("Batal", "Cancel"), role: .cancel) {}
        } message: { app in
            Text(L("\(app.name) ditutup dengan cara biasa dan melepas sekitar \(app.footprint.formattedMemory). Kalau ada pekerjaan yang belum disimpan, app itu akan bertanya dulu.",
                   "\(app.name) quits the normal way and frees about \(app.footprint.formattedMemory). If it has unsaved work, it will ask you first."))
        }
        .alert(L("Lepas cache file dari RAM?", "Release cached files from RAM?"), isPresented: $confirmPurge) {
            Button(L("Lanjutkan", "Continue")) { Task { await model.purge() } }
            Button(L("Batal", "Cancel"), role: .cancel) {}
        } message: {
            Text(L("macOS akan meminta password admin. App mungkin terasa sedikit lambat sebentar karena file dibaca ulang dari disk. Swap tidak berkurang.",
                   "macOS will ask for an administrator password. Apps may feel slower for a moment while files are read from disk again. Swap is not reduced."))
        }
    }

    // MARK: App list

    private var appList: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L("App paling boros", "Top memory users"))
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                Spacer()
                Text(L("termasuk proses pembantunya", "including helper processes"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            ScrollView {
                LazyVStack(spacing: 2) {
                    let largest = Double(model.apps.first?.footprint ?? 1)
                    ForEach(model.apps) { app in
                        AppMemoryRow(
                            app: app,
                            share: Double(app.footprint) / max(largest, 1),
                            canQuit: model.quittable.contains(app.bundleURL),
                            onQuit: { pendingQuit = app }
                        )
                    }
                }
            }
            .scrollIndicators(.never)
        }
        .softCard(padding: 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Purge

    private func purgeCard(stats: MemoryStats) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                GradientIcon(symbol: "wind", colors: Palette.sky, size: 34, corner: 10)
                Text(L("Bebaskan RAM", "Free up RAM"))
                    .font(.system(size: 14, weight: .bold, design: .rounded))
            }
            Text(L("Melepas \(stats.cached.formattedMemory) cache file dari RAM. macOS sebenarnya melepasnya sendiri saat ada app yang butuh, jadi ini jarang diperlukan.",
                   "Releases \(stats.cached.formattedMemory) of cached files from RAM. macOS already releases it on its own when an app needs memory, so this is rarely needed."))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(L("Yang benar-benar mengurangi pemakaian RAM dan swap: tutup app yang boros di daftar sebelah.",
                   "What really lowers RAM and swap use: quit the heavy apps in the list."))
                .font(.system(size: 12, weight: .medium))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button {
                confirmPurge = true
            } label: {
                Label(model.isPurging ? L("Melepas…", "Releasing…") : L("Lepas cache file", "Release cached files"), systemImage: "lock.shield")
            }
            .buttonStyle(GradientButtonStyle(colors: Palette.sky))
            .disabled(model.isPurging)
            Text(L("Butuh password admin", "Needs an administrator password"))
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .softCard(padding: 16)
        .frame(maxHeight: .infinity)
    }
}

// MARK: - Cards

private struct PressureCard: View {
    let stats: MemoryStats

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("Tekanan memori", "Memory pressure"))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                GradientIcon(symbol: symbol, colors: colors, size: 40, corner: 12)
                Text(title)
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                    .foregroundStyle(LinearGradient.soft(colors))
            }
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if stats.swapTotal > 0 {
                Divider()
                HStack {
                    Text("Swap")
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Text("\(stats.swapUsed.formattedMemory) / \(stats.swapTotal.formattedMemory)")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }
                if stats.swapUsed > stats.swapTotal / 2 {
                    Text(L("Swap tinggi berarti RAM sempat penuh. Swap baru turun setelah app besar ditutup atau Mac di-restart.",
                           "High swap means RAM ran short at some point. It only drops after big apps quit or the Mac restarts."))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .softCard(padding: 18)
    }

    private var title: String {
        switch stats.pressure {
        case .normal: L("Normal", "Normal")
        case .warning: L("Mulai penuh", "Getting full")
        case .critical: L("Kritis", "Critical")
        }
    }

    private var message: String {
        switch stats.pressure {
        case .normal:
            L("RAM cukup. macOS memakai sisa RAM untuk cache supaya app tetap cepat, jadi RAM yang terlihat penuh itu wajar.",
              "There's enough RAM. macOS uses spare RAM as cache to keep apps fast, so RAM that looks full is normal.")
        case .warning:
            L("Mac mulai memadatkan memori. Tutup app yang tidak dipakai supaya tetap lancar.",
              "Your Mac has started compressing memory. Quit apps you aren't using to keep things smooth.")
        case .critical:
            L("RAM hampir habis dan Mac bisa melambat. Tutup app besar di bawah sekarang.",
              "RAM is nearly exhausted and your Mac may slow down. Quit a big app below now.")
        }
    }

    private var symbol: String {
        switch stats.pressure {
        case .normal: "checkmark"
        case .warning: "exclamationmark"
        case .critical: "exclamationmark.triangle.fill"
        }
    }

    private var colors: [Color] {
        switch stats.pressure {
        case .normal: Palette.mint
        case .warning: Palette.sunny
        case .critical: Palette.berry
        }
    }
}

private struct BreakdownCard: View {
    let stats: MemoryStats

    private var segments: [(title: String, bytes: UInt64, colors: [Color])] {
        [
            (L("Aplikasi", "Apps"), stats.app, Palette.lavender),
            (L("Wired", "Wired"), stats.wired, Palette.ocean),
            (L("Terkompresi", "Compressed"), stats.compressed, Palette.candy),
            (L("Cache file", "Cached files"), stats.cached, Palette.sky),
            (L("Bebas", "Free"), stats.free, Palette.slate),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .lastTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("Terpakai", "In use"))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Text(stats.used.formattedMemory)
                        .font(.system(size: 30, weight: .heavy, design: .rounded))
                        .contentTransition(.numericText())
                }
                Text(L("dari \(stats.total.formattedMemory)", "of \(stats.total.formattedMemory)"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
            }

            GeometryReader { geo in
                HStack(spacing: 3) {
                    ForEach(segments, id: \.title) { segment in
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(LinearGradient(colors: segment.colors, startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(0, (geo.size.width - 12) * Double(segment.bytes) / Double(max(stats.total, 1))))
                    }
                }
            }
            .frame(height: 16)
            .animation(.smooth, value: stats.used)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 10) {
                ForEach(segments, id: \.title) { segment in
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(LinearGradient.soft(segment.colors))
                            .frame(width: 10, height: 10)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(segment.title)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                            Text(segment.bytes.formattedMemory)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .softCard(padding: 18)
    }
}

private struct AppMemoryRow: View {
    let app: AppMemoryUsage
    let share: Double
    let canQuit: Bool
    let onQuit: () -> Void
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: FileIcon.image(for: app.bundleURL, size: 30))
                .resizable()
                .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 4) {
                Text(app.name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                // The count sits next to the bar, so on a narrow window the name keeps the whole line.
                HStack(spacing: 6) {
                    GeometryReader { geo in
                        Capsule().fill(Color.primary.opacity(0.06))
                            .overlay(alignment: .leading) {
                                Capsule()
                                    .fill(LinearGradient(colors: Module.memory.colors, startPoint: .leading, endPoint: .trailing))
                                    .frame(width: geo.size.width * share)
                            }
                    }
                    .frame(height: 4)
                    if app.processCount > 1 {
                        Text(L("\(app.processCount) proses", "\(app.processCount) processes"))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .fixedSize()
                    }
                }
            }
            Text(app.footprint.formattedMemory)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .monospacedDigit()
                .frame(width: 80, alignment: .trailing)
            Group {
                if canQuit {
                    Button(L("Keluar", "Quit"), action: onQuit)
                        .buttonStyle(SoftButtonStyle())
                } else {
                    Color.clear
                }
            }
            .frame(width: 86)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isHovering ? Color.primary.opacity(0.04) : .clear)
        )
        .onHover { isHovering = $0 }
    }
}
