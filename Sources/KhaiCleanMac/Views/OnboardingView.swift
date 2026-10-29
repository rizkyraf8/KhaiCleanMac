import SwiftUI
import UniformTypeIdentifiers

/// First-run guide: what the app promises, Full Disk Access with a step-by-step tutorial, and a send-off.
struct OnboardingView: View {
    @State var step: OnboardingStep
    let onFinish: () -> Void

    @Bindable private var settings = AppSettings.shared
    @State private var hasAccess = Permissions.hasFullDiskAccess

    private var colors: [Color] {
        switch step {
        case .welcome: Palette.logo
        case .access: Palette.peach
        case .ready: Palette.mint
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            progress
                .padding(.top, 22)

            Group {
                switch step {
                case .welcome: welcome
                case .access: access
                case .ready: ready
                }
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
            .id(step)

            footer
                .padding(.horizontal, 32)
                .padding(.bottom, 24)
        }
        .frame(width: 760, height: 640)
        .background(SoftBackground(colors: colors))
        .animation(.snappy, value: step)
        .task(id: step) {
            // Watch for the permission while the access page is open, so it ticks green right away.
            guard step == .access else { return }
            while !Task.isCancelled {
                let granted = Permissions.hasFullDiskAccess
                if granted != hasAccess { withAnimation(.snappy) { hasAccess = granted } }
                try? await Task.sleep(for: .seconds(1.5))
            }
        }
    }

    // MARK: Progress & footer

    private var progress: some View {
        HStack(spacing: 6) {
            ForEach(OnboardingStep.allCases) { item in
                Capsule()
                    .fill(item.rawValue <= step.rawValue
                          ? AnyShapeStyle(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
                          : AnyShapeStyle(Color.primary.opacity(0.1)))
                    .frame(width: item == step ? 34 : 18, height: 6)
            }
        }
    }

    private var footer: some View {
        HStack {
            if step != .welcome {
                Button(L("Kembali", "Back")) { go(-1) }
                    .buttonStyle(SoftButtonStyle())
            }
            Spacer()
            switch step {
            case .welcome:
                Button(L("Mulai", "Get started")) { go(1) }
                    .buttonStyle(GradientButtonStyle(colors: colors))
            case .access:
                if !hasAccess {
                    Button(L("Nanti saja", "Maybe later")) { go(1) }
                        .buttonStyle(SoftButtonStyle())
                }
                Button(hasAccess ? L("Lanjut", "Continue") : L("Sudah, lanjut", "Done, continue")) { go(1) }
                    .buttonStyle(GradientButtonStyle(colors: colors))
            case .ready:
                Button(L("Mulai pakai KhaiCleanMac", "Start using KhaiCleanMac"), action: onFinish)
                    .buttonStyle(GradientButtonStyle(colors: colors))
            }
        }
    }

    private func go(_ offset: Int) {
        guard let next = OnboardingStep(rawValue: step.rawValue + offset) else { return }
        withAnimation(.snappy) { step = next }
    }

    // MARK: Welcome

    private var welcome: some View {
        VStack(spacing: 22) {
            AppLogo(size: 92)
            VStack(spacing: 8) {
                Text(L("Selamat datang di KhaiCleanMac", "Welcome to KhaiCleanMac"))
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                Text(L("Bersihkan sampah, temukan file besar, dan pantau Mac kamu, dengan cara yang aman.",
                       "Clean up junk, find big files and keep an eye on your Mac, safely."))
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            VStack(spacing: 10) {
                PromiseRow(symbol: "arrow.uturn.backward", colors: Palette.mint,
                           title: L("Semua masuk Trash dulu", "Everything goes to the Trash first"),
                           text: L("Kalau ada yang salah, tinggal kembalikan dari Trash. Hapus permanen hanya kalau kamu sendiri yang menyalakannya.",
                                   "If something was a mistake, put it back from the Trash. Permanent deletion only happens if you turn it on yourself."))
                PromiseRow(symbol: "hand.raised.fill", colors: Palette.sunny,
                           title: L("Tidak ada yang dihapus tanpa izinmu", "Nothing is removed without your OK"),
                           text: L("Setiap modul menunjukkan apa yang ditemukan dan meminta konfirmasi dulu.",
                                   "Every module shows what it found and asks you to confirm first."))
                PromiseRow(symbol: "lock.fill", colors: Palette.lavender,
                           title: L("App yang terbuka aman", "Open apps stay safe"),
                           text: L("Cache dan data milik app yang sedang berjalan dikunci.",
                                   "Caches and data of apps that are running are locked."))
            }
            .frame(maxWidth: 560)
            HStack(spacing: 10) {
                Text(L("Bahasa", "Language"))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                // A menu, as nine languages no longer fit side by side as chips.
                Picker(L("Bahasa", "Language"), selection: $settings.language) {
                    ForEach(AppLanguage.allCases) { language in
                        Text("\(language.flag)  \(language.nativeName)").tag(language)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .fixedSize()
            }
            if settings.language.isAITranslated {
                AITranslationNote()
                    .frame(maxWidth: 480)
            }
        }
    }

    // MARK: Full Disk Access

    private var access: some View {
        HStack(alignment: .top, spacing: 28) {
            VStack(alignment: .leading, spacing: 14) {
                GradientIcon(symbol: "lock.shield.fill", colors: Palette.peach, size: 56)
                Text(L("Izinkan Akses Disk Penuh", "Allow Full Disk Access"))
                    .font(.system(size: 24, weight: .heavy, design: .rounded))
                Text(L("macOS melindungi beberapa folder. Tanpa izin ini, KhaiCleanMac tetap jalan, tapi bagian di bawah tidak bisa diperiksa:",
                       "macOS protects some folders. Without this permission KhaiCleanMac still works, but it can't look at:"))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 7) {
                    unlock("trash", L("Isi Trash", "What's in the Trash"))
                    unlock("iphone", L("Backup iPhone dan iPad", "iPhone and iPad backups"))
                    unlock("safari", L("Cache Safari", "Safari's cache"))
                    unlock("shippingbox", L("Sisa app di folder Containers", "App leftovers in Containers"))
                }
                statusPill
                Text(L("KhaiCleanMac hanya membaca untuk menghitung ukuran, dan tidak mengirim data ke mana pun.",
                       "KhaiCleanMac only reads to measure sizes and never sends data anywhere."))
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: 290, alignment: .leading)

            VStack(alignment: .leading, spacing: 10) {
                Text(L("Caranya", "How to"))
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                TutorialStep(number: 1, symbol: "gearshape.fill",
                             text: L("Klik tombol di bawah untuk membuka Pengaturan Sistem › Privasi & Keamanan › Akses Disk Penuh.",
                                     "Click the button below to open System Settings › Privacy & Security › Full Disk Access.")) {
                    Button(L("Buka Pengaturan", "Open Settings")) { Permissions.openFullDiskAccessSettings() }
                        .buttonStyle(GradientButtonStyle(colors: Palette.peach))
                }
                TutorialStep(number: 2, symbol: "hand.draw.fill",
                             text: L("Seret ikon ini ke daftar di Pengaturan. Atau klik tombol + di bawah daftar dan pilih KhaiCleanMac di folder Applications.",
                                     "Drag this icon into the list in Settings. Or click + under the list and pick KhaiCleanMac in Applications.")) {
                    DraggableAppIcon()
                }
                TutorialStep(number: 3, symbol: "switch.2",
                             text: L("Pastikan sakelar di samping KhaiCleanMac menyala. macOS mungkin meminta password atau Touch ID.",
                                     "Make sure the switch next to KhaiCleanMac is on. macOS may ask for your password or Touch ID.")) { EmptyView() }
                TutorialStep(number: 4, symbol: "arrow.uturn.backward",
                             text: L("Kembali ke sini. Status di kiri berubah hijau sendiri. Kalau macOS menawarkan \"Keluar & Buka Lagi\", pilih itu, lalu panduan ini bisa dibuka lagi dari Pengaturan.",
                                     "Come back here. The status on the left turns green by itself. If macOS offers \"Quit & Reopen\", choose it; you can open this guide again from Settings.")) { EmptyView() }
            }
        }
    }

    private func unlock(_ symbol: String, _ text: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.system(size: 12, weight: .medium))
    }

    private var statusPill: some View {
        HStack(spacing: 8) {
            if hasAccess {
                Image(systemName: "checkmark.seal.fill")
                Text(L("Akses Disk Penuh sudah aktif", "Full Disk Access is on"))
            } else {
                ProgressView().controlSize(.small)
                Text(L("Menunggu izin…", "Waiting for permission…"))
            }
        }
        .font(.system(size: 12, weight: .semibold, design: .rounded))
        .foregroundStyle(hasAccess ? Color.white : Color.primary)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Capsule().fill(hasAccess
                                   ? AnyShapeStyle(LinearGradient(colors: Palette.mint, startPoint: .leading, endPoint: .trailing))
                                   : AnyShapeStyle(Color.white.opacity(0.7))))
    }

    // MARK: Ready

    private var ready: some View {
        VStack(spacing: 22) {
            GradientIcon(symbol: "checkmark", colors: Palette.mint, size: 84)
            VStack(spacing: 8) {
                Text(L("Siap dipakai!", "You're all set!"))
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                Text(L("Mulai dari Beranda. Semua fitur ada di sana, dan panduan ini bisa dibuka lagi dari Pengaturan › Tentang.",
                       "Start from Home. Every feature is there, and you can open this guide again from Settings › About."))
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 520)
            }
            HStack(spacing: 14) {
                TipCard(module: .smartScan, text: L("Satu klik untuk cache, log, dan sampah lain.", "One click for caches, logs and other junk."))
                TipCard(module: .memory, text: L("Lihat app yang paling boros RAM.", "See which apps use the most RAM."))
                TipCard(module: .startup, text: L("Rapikan yang jalan saat login.", "Tidy up what starts at login."))
            }
            .frame(maxWidth: 640)
        }
    }
}

// MARK: - Pieces

private struct PromiseRow: View {
    let symbol: String
    let colors: [Color]
    let title: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            GradientIcon(symbol: symbol, colors: colors, size: 34, corner: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                Text(text)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .softCard(padding: 12, radius: 16)
    }
}

private struct TutorialStep<Accessory: View>: View {
    let number: Int
    let symbol: String
    let text: String
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(LinearGradient.soft(Palette.peach)))
            VStack(alignment: .leading, spacing: 8) {
                Label {
                    Text(text)
                        .font(.system(size: 12))
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: symbol).foregroundStyle(LinearGradient.soft(Palette.peach))
                }
                accessory
            }
            Spacer(minLength: 0)
        }
        .softCard(padding: 12, radius: 14)
    }
}

/// The app's own icon, draggable straight into the Full Disk Access list in System Settings.
private struct DraggableAppIcon: View {
    var body: some View {
        HStack(spacing: 10) {
            // A bare `swift run` binary isn't an .app, so its "bundle" icon would be a plain folder.
            if Bundle.main.bundleURL.pathExtension == "app" {
                Image(nsImage: FileIcon.image(for: Bundle.main.bundleURL, size: 40))
                    .resizable()
                    .frame(width: 40, height: 40)
            } else {
                AppLogo(size: 40)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(AppInfo.name)
                    .font(.system(size: 12, weight: .semibold))
                Text(L("Seret aku ↗", "Drag me ↗"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button(L("Tampilkan di Finder", "Show in Finder")) {
                NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
            }
            .buttonStyle(.link)
            .font(.system(size: 11, weight: .semibold))
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])).foregroundStyle(Palette.peach[1].opacity(0.6)))
        .onDrag { NSItemProvider(contentsOf: Bundle.main.bundleURL) ?? NSItemProvider() }
        .help(L("Seret ke daftar Akses Disk Penuh", "Drag into the Full Disk Access list"))
    }
}

private struct TipCard: View {
    let module: Module
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GradientIcon(symbol: module.symbol, colors: module.colors, size: 36, corner: 11)
            Text(module.title)
                .font(.system(size: 13, weight: .bold, design: .rounded))
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .softCard(padding: 14, radius: 16)
    }
}
