import SwiftUI

struct StartupView: View {
    @Bindable var model: StartupModel
    @State private var pendingRemoval: StartupItem?
    private let module = Module.startup

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ModuleHeader(module: module) {
                HStack(spacing: 10) {
                    Button {
                        LoginItem.openSystemSettings()
                    } label: {
                        Label(L("Pengaturan Sistem", "System Settings"), systemImage: "gearshape")
                    }
                    .buttonStyle(SoftButtonStyle())
                    Button {
                        Task { await model.load() }
                    } label: {
                        Label(L("Muat Ulang", "Reload"), systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(SoftButtonStyle())
                }
            }

            HStack(spacing: 12) {
                StatTile(title: L("Agent pengguna aktif", "Active user agents"), value: "\(model.activeUserAgentCount)", colors: Palette.sunny)
                StatTile(title: L("Agent & daemon sistem", "System agents & daemons"), value: "\(model.systemItems.count)", colors: Palette.ocean)
                StatTile(title: L("Yatim (app sudah tidak ada)", "Orphaned (app is gone)"), value: "\(model.orphanCount)", colors: Palette.berry)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    loginItemsCard
                    section(
                        title: L("Agent milikmu", "Your agents"),
                        caption: L("Dari ~/Library/LaunchAgents. Mematikan agent bisa dibatalkan kapan saja. Menghapusnya membuang file plist-nya.",
                                   "From ~/Library/LaunchAgents. Turning one off can be undone anytime. Removing it throws away its plist."),
                        items: model.userAgents,
                        empty: L("Tidak ada agent di folder ini.", "No agents in this folder.")
                    )
                    section(
                        title: L("Agent & daemon sistem", "System agents & daemons"),
                        caption: L("Dari /Library. Dipasang dengan izin admin, jadi di sini hanya ditampilkan. Agent keamanan kantor (VPN, antivirus) sebaiknya dibiarkan.",
                                   "From /Library. Installed with admin rights, so they're shown here read-only. Leave work security agents (VPN, antivirus) alone."),
                        items: model.systemItems,
                        empty: L("Tidak ada.", "None.")
                    )
                }
                .padding(4)
            }
            .scrollIndicators(.never)
        }
        .toast($model.toast)
        .task { if !model.hasLoaded { await model.load() } }
        .alert(
            pendingRemoval?.kind == .loginItem
                ? L("Hapus \(pendingRemoval?.name ?? "") dari login?", "Remove \(pendingRemoval?.name ?? "") from login?")
                : Removal.question(pendingRemoval?.name ?? ""),
            isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } }),
            presenting: pendingRemoval
        ) { item in
            Button(item.kind == .loginItem ? L("Hapus dari login", "Remove from login") : Removal.actionTitle, role: .destructive) {
                Task { await model.remove(item) }
            }
            Button(L("Batal", "Cancel"), role: .cancel) {}
        } message: { item in
            Text(item.kind == .loginItem
                 ? L("Aplikasinya tidak dihapus, hanya tidak dibuka otomatis lagi saat kamu login.", "The app itself stays; it just won't open on its own when you log in.")
                 : L("Agent dihentikan dan file plist-nya dibuang. ", "The agent is stopped and its plist is removed. ") + Removal.undoNote)
        }
    }

    // MARK: Login items

    private var loginItemsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(L("Login Items", "Login Items"),
                          caption: L("App yang dibuka otomatis setiap kali kamu login. App yang memakai \"Izinkan di Latar Belakang\" diatur lewat Pengaturan Sistem.",
                                     "Apps that open every time you log in. Apps listed under \"Allow in the Background\" are managed in System Settings."))
            if let items = model.loginItems {
                if items.isEmpty {
                    emptyText(L("Tidak ada Login Items klasik.", "No classic login items."))
                } else {
                    ForEach(items) { row($0) }
                }
            } else {
                HStack(spacing: 12) {
                    Text(model.loginItemsDenied
                         ? L("Izin mengontrol System Events ditolak. Nyalakan di Pengaturan Sistem › Privasi & Keamanan › Otomatisasi.",
                             "Permission to control System Events was declined. Turn it on in System Settings › Privacy & Security › Automation.")
                         : L("Untuk membaca daftar ini, macOS akan meminta izin agar KhaiCleanMac bisa bertanya ke System Events.",
                             "To read this list, macOS will ask to let KhaiCleanMac talk to System Events."))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 12)
                    Button(L("Tampilkan", "Show")) { Task { await model.loadLoginItems() } }
                        .buttonStyle(GradientButtonStyle(colors: module.colors))
                }
            }
        }
        .softCard(padding: 16)
    }

    // MARK: Sections

    private func section(title: String, caption: String, items: [StartupItem], empty: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(title, caption: caption)
            if model.isLoading && items.isEmpty {
                ProgressView().frame(maxWidth: .infinity)
            } else if items.isEmpty {
                emptyText(empty)
            } else {
                ForEach(items) { row($0) }
            }
        }
        .softCard(padding: 16)
    }

    private func sectionHeader(_ title: String, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 14, weight: .bold, design: .rounded))
            Text(caption)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func emptyText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .padding(.vertical, 6)
    }

    private func row(_ item: StartupItem) -> some View {
        StartupRow(
            item: item,
            isBusy: model.busyIDs.contains(item.id),
            onToggle: { Task { await model.toggle(item) } },
            onRemove: { pendingRemoval = item }
        )
    }
}

private struct StartupRow: View {
    let item: StartupItem
    let isBusy: Bool
    let onToggle: () -> Void
    let onRemove: () -> Void
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let app = item.appURL {
                    Image(nsImage: FileIcon.image(for: app, size: 30)).resizable()
                } else {
                    GradientIcon(symbol: item.kind == .systemDaemon ? "gearshape.2.fill" : "bolt.fill",
                                 colors: item.isOrphan ? Palette.berry : Palette.slate, size: 30, corner: 9)
                }
            }
            .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.name)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    ForEach(badges, id: \.text) { badge in
                        Text(badge.text)
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(badge.color)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(badge.color.opacity(0.15)))
                    }
                }
                Text(item.kind == .loginItem ? (item.programPath ?? "") : item.label)
                    .font(.system(size: 11, design: item.kind == .loginItem ? .default : .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 12)

            if isBusy {
                ProgressView().controlSize(.small)
            }
            if let file = item.fileURL {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([file])
                } label: {
                    Image(systemName: "arrow.up.forward.square")
                }
                .buttonStyle(.borderless)
                .help(L("Tampilkan di Finder", "Show in Finder"))
                .opacity(isHovering ? 1 : 0.3)
            }
            if item.kind == .userAgent {
                Toggle("", isOn: Binding(get: { !item.isDisabled }, set: { _ in onToggle() }))
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.small)
                    .disabled(isBusy)
                    .help(item.isDisabled ? L("Nyalakan lagi", "Turn back on") : L("Matikan", "Turn off"))
            }
            if item.isEditable {
                Button(L("Hapus", "Remove"), action: onRemove)
                    .buttonStyle(SoftButtonStyle())
                    .disabled(isBusy)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(isHovering ? Color.primary.opacity(0.04) : .clear))
        .opacity(item.isDisabled ? 0.6 : 1)
        .onHover { isHovering = $0 }
    }

    private var badges: [(text: String, color: Color)] {
        var result: [(String, Color)] = []
        if item.isOrphan { result.append((L("Yatim", "Orphaned"), Palette.berry[1])) }
        if item.isDisabled { result.append((L("Mati", "Off"), Palette.slate[1])) }
        if item.kind == .systemDaemon { result.append(("Daemon", Palette.ocean[1])) }
        if item.keepsAlive && !item.isDisabled { result.append((L("Selalu jalan", "Always on"), Palette.sunny[1])) }
        return result
    }
}
