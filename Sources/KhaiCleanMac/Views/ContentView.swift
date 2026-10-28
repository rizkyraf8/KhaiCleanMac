import SwiftUI

struct ContentView: View {
    @State private var selection: Module
    @State private var smartScan: SmartScanModel
    @State private var largeFiles = LargeFilesModel()
    @State private var duplicates: DuplicatesModel
    @State private var spaceLens = SpaceLensModel()
    @State private var uninstaller: UninstallerModel

    init(
        selection: Module = .smartScan,
        smartScan: SmartScanModel = SmartScanModel(),
        duplicates: DuplicatesModel = DuplicatesModel(),
        uninstaller: UninstallerModel = UninstallerModel()
    ) {
        _selection = State(initialValue: selection)
        _smartScan = State(initialValue: smartScan)
        _duplicates = State(initialValue: duplicates)
        _uninstaller = State(initialValue: uninstaller)
    }

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(selection: $selection)
                .frame(width: 248)

            Group {
                switch selection {
                case .smartScan: SmartScanView(model: smartScan)
                case .largeFiles: LargeFilesView(model: largeFiles)
                case .duplicates: DuplicatesView(model: duplicates)
                case .spaceLens: SpaceLensView(model: spaceLens)
                case .uninstaller: UninstallerView(model: uninstaller)
                }
            }
            .padding(.horizontal, 30)
            .padding(.top, 34)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.opacity)
            .id(selection)
        }
        .background(SoftBackground(colors: selection.colors))
        .frame(minWidth: 1000, minHeight: 720)
    }
}

struct SidebarView: View {
    @Binding var selection: Module
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 11) {
                AppLogo(size: 38)
                VStack(alignment: .leading, spacing: 1) {
                    Text(AppInfo.name)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                    Text(L("Mac bersih, hati tenang", "Clean Mac, calm mind"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 6)
            .padding(.top, 46)
            .padding(.bottom, 14)

            ForEach(Module.Section.allCases, id: \.self) { section in
                Text(section.title)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 10)
                    .padding(.top, 8)
                    .padding(.bottom, 2)

                ForEach(Module.allCases.filter { $0.section == section }) { module in
                    SidebarRow(module: module, isSelected: selection == module) {
                        withAnimation(.snappy) { selection = module }
                    }
                }
            }

            Spacer()

            DiskCard()
            AccessCard()
            SidebarFooter()
        }
        .padding(14)
        .frame(maxHeight: .infinity)
        .background(scheme == .dark ? Color.white.opacity(0.03) : Color.white.opacity(0.35))
        .overlay(alignment: .trailing) {
            Rectangle().fill(Color.primary.opacity(0.06)).frame(width: 1)
        }
    }
}

private struct SidebarRow: View {
    let module: Module
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovering = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                GradientIcon(symbol: module.symbol, colors: module.colors, size: 34, corner: 10)
                VStack(alignment: .leading, spacing: 1) {
                    Text(module.title)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                    Text(module.tagline)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(background)
                    .shadow(color: .black.opacity(isSelected ? 0.07 : 0), radius: 10, y: 4)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }

    private var background: Color {
        if isSelected { return scheme == .dark ? Color.white.opacity(0.1) : Color.white.opacity(0.92) }
        return isHovering ? Color.primary.opacity(0.04) : .clear
    }
}

private struct DiskCard: View {
    @State private var info: DiskInfo?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Macintosh HD", systemImage: "internaldrive")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                Spacer()
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08))
                    Capsule()
                        .fill(LinearGradient(colors: Palette.logo, startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * (info?.usedFraction ?? 0))
                }
            }
            .frame(height: 7)
            Text(info.map { L("\($0.available.formattedBytes) tersedia dari \($0.total.formattedBytes)", "\($0.available.formattedBytes) free of \($0.total.formattedBytes)") } ?? L("Membaca disk…", "Reading disk…"))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .softCard(padding: 12, radius: 16)
        .task {
            while !Task.isCancelled {
                let current = await Task.detached { DiskInfo.current() }.value
                withAnimation(.smooth) { info = current }
                try? await Task.sleep(for: .seconds(10))
            }
        }
    }
}

private struct SidebarFooter: View {
    @State private var isHovering = false

    var body: some View {
        HStack {
            SettingsLink {
                Label(L("Pengaturan", "Settings"), systemImage: "gearshape.fill")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(isHovering ? .primary : .secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.primary.opacity(isHovering ? 0.08 : 0.05)))
            }
            .buttonStyle(.plain)
            .onHover { isHovering = $0 }
            .help(L("Bahasa, tampilan, dan info aplikasi (⌘,)", "Language, appearance and app info (⌘,)"))
            Spacer()
            Text("v\(AppInfo.version)")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.tertiary)
                .help(L("Versi \(AppInfo.version) (build \(AppInfo.build))", "Version \(AppInfo.version) (build \(AppInfo.build))"))
        }
        .padding(.top, 6)
    }
}

private struct AccessCard: View {
    @State private var granted = Permissions.hasFullDiskAccess
    @State private var showStaleHint = false

    var body: some View {
        Group {
            if granted {
                Label(L("Akses Disk Penuh aktif", "Full Disk Access on"), systemImage: "checkmark.shield.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color(hex: 0x10B981))
                    .padding(.horizontal, 6)
                    .padding(.top, 4)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Label(L("Akses Disk Penuh", "Full Disk Access"), systemImage: "lock.shield.fill")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(LinearGradient.soft(Palette.peach))
                    Text(L("Izinkan agar pemindaian dan uninstall lebih lengkap.", "Allow it for more thorough scans and uninstalls."))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 12) {
                        Button(L("Buka Pengaturan", "Open Settings")) { Permissions.openFullDiskAccessSettings() }
                        Button(L("Cek Lagi", "Check Again")) {
                            withAnimation(.snappy) {
                                granted = Permissions.hasFullDiskAccess
                                showStaleHint = !granted
                            }
                        }
                    }
                    .buttonStyle(.link)
                    .font(.system(size: 11, weight: .semibold))
                    // Only worth the space once the user believes they already allowed it.
                    if showStaleHint {
                        Text(L("Sudah diizinkan tapi masih muncul? Di Pengaturan, hapus KhaiCleanMac dengan tombol −, tambahkan lagi, lalu buka ulang aplikasi.",
                               "Already allowed but still showing? In Settings, remove KhaiCleanMac with the − button, add it again, then reopen the app."))
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .softCard(padding: 12, radius: 16)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            granted = Permissions.hasFullDiskAccess
        }
    }
}
