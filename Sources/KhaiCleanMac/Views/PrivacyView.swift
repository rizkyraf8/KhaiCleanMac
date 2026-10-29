import SwiftUI

struct PrivacyView: View {
    @Bindable var model: PrivacyModel
    @State private var confirmClean = false
    private let module = Module.privacy

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ModuleHeader(module: module) {
                Button {
                    Task { await model.load() }
                } label: {
                    Label(L("Muat Ulang", "Reload"), systemImage: "arrow.clockwise")
                }
                .buttonStyle(SoftButtonStyle())
            }

            notice

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if model.isLoading && !model.hasLoaded {
                        ProgressView().frame(maxWidth: .infinity).padding(40)
                    }
                    if model.hasLoaded && model.browsers.isEmpty {
                        EmptyStateView(symbol: module.symbol, colors: module.colors,
                                       title: L("Tidak ada data browser", "No browser data found"),
                                       message: L("Chrome, Brave, Edge, Arc, Vivaldi, Firefox, dan Safari diperiksa. Safari butuh Akses Disk Penuh.",
                                                  "Chrome, Brave, Edge, Arc, Vivaldi, Firefox and Safari were checked. Safari needs Full Disk Access.")) { EmptyView() }
                            .frame(height: 320)
                    }
                    ForEach(model.browsers) { browserCard($0) }
                    if model.hasLoaded && !model.hasFullDiskAccess && !model.browsers.contains(where: { $0.browser.name == "Safari" }) {
                        Text(L("Safari tidak terlihat? Datanya hanya bisa dibaca dengan Akses Disk Penuh.",
                               "Don't see Safari? Its data can only be read with Full Disk Access."))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(4)
            }
            .scrollIndicators(.never)

            ActionBar(
                caption: L("\(model.selectedItems.count) jenis data dipilih", "\(model.selectedItems.count) kinds of data selected"),
                value: model.selectedSize.formattedBytes,
                buttonTitle: L("Hapus Data Terpilih", "Clear Selected"),
                buttonSymbol: "hand.raised.fill",
                colors: module.colors,
                isDisabled: model.selectedItems.isEmpty || model.isCleaning
            ) {
                confirmClean = true
            }
        }
        .toast($model.toast)
        .task { if !model.hasLoaded { await model.load() } }
        .onReceive(NotificationCenter.default.publisher(for: NSWorkspace.didTerminateApplicationNotification)) { _ in model.refreshRunning() }
        .onReceive(NotificationCenter.default.publisher(for: NSWorkspace.didLaunchApplicationNotification)) { _ in model.refreshRunning() }
        .alert(L("Hapus data browser yang dipilih?", "Clear the selected browser data?"), isPresented: $confirmClean) {
            Button(L("Hapus", "Clear"), role: .destructive) { Task { await model.clean() } }
            Button(L("Batal", "Cancel"), role: .cancel) {}
        } message: {
            Text(confirmationMessage)
        }
    }

    private var confirmationMessage: String {
        let lines = model.selectedItems.map { "• \($0.browserName): \($0.kind.title)" }.joined(separator: "\n")
        var notes: [String] = []
        if model.selectedItems.contains(where: { $0.kind == .cookies }) {
            notes.append(L("Kamu akan keluar dari semua situs di browser itu.", "You'll be signed out of every site in that browser."))
        }
        if model.selectedItems.contains(where: { if case .removeFiles = $0.action { true } else { false } }) {
            notes.append(Removal.isPermanent
                ? L("Mode hapus permanen aktif: file langsung dihapus.", "Delete permanently is on: files are removed right away.")
                : L("File masuk Trash dan bisa dikembalikan lewat Riwayat. Kosongkan Trash supaya benar-benar hilang.",
                    "Files go to the Trash and can be put back from History. Empty the Trash to get rid of them for good."))
        }
        if model.selectionIncludesPermanent {
            notes.append(L("Isian formulir Chromium dihapus dari dalam database dan tidak bisa dikembalikan.",
                           "Chromium form data is deleted inside its database and can't be put back."))
        }
        return lines + "\n\n" + notes.joined(separator: " ")
    }

    private var notice: some View {
        HStack(spacing: 12) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(LinearGradient.soft(module.colors))
            Text(L("Tidak ada yang dipilih otomatis. Browser harus ditutup dulu. Kalau sinkronisasi browser aktif, data dari perangkat lain bisa muncul lagi. Password, bookmark, alamat, dan kartu tidak pernah disentuh.",
                   "Nothing is picked for you. The browser has to be closed first. With browser sync on, data from your other devices may come back. Passwords, bookmarks, addresses and cards are never touched."))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(module.colors[0].opacity(0.18)))
    }

    private func browserCard(_ entry: BrowserPrivacy) -> some View {
        let isRunning = model.runningBrowsers.contains(entry.browser.name)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Group {
                    if let app = entry.browser.bundleIDs.lazy.compactMap(StartupScanner.appURL(forBundleID:)).first {
                        Image(nsImage: FileIcon.image(for: app, size: 30)).resizable()
                    } else {
                        GradientIcon(symbol: "globe", colors: Palette.slate, size: 30, corner: 9)
                    }
                }
                .frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.browser.name).font(.system(size: 14, weight: .bold, design: .rounded))
                    let profiles = entry.items.first?.profileCount ?? 1
                    if profiles > 1 {
                        Text(L("\(profiles) profil", "\(profiles) profiles")).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if isRunning {
                    Label(L("Sedang terbuka, tutup dulu", "Open, quit it first"), systemImage: "lock.fill")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(Palette.sunny[1])
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Palette.sunny[1].opacity(0.15)))
                }
            }
            ForEach(entry.items) { item in
                PrivacyRow(item: item, isSelected: model.selected.contains(item.id), isLocked: model.isLocked(item)) {
                    model.toggle(item)
                }
            }
        }
        .softCard(padding: 16)
    }
}

private struct PrivacyRow: View {
    let item: PrivacyItem
    let isSelected: Bool
    let isLocked: Bool
    let onToggle: () -> Void
    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Group {
                if item.isSupported {
                    CheckCircle(isOn: isSelected, colors: Module.privacy.colors)
                        .opacity(isLocked ? 0.35 : 1)
                } else {
                    Image(systemName: "minus.circle")
                        .font(.system(size: 17))
                        .foregroundStyle(.tertiary)
                        .frame(width: 20, height: 20)
                }
            }
            .padding(.top, 6)
            GradientIcon(symbol: item.kind.symbol, colors: item.isSupported ? Module.privacy.colors : Palette.slate, size: 30, corner: 9)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(item.kind.title).font(.system(size: 13, weight: .semibold))
                    if let count = item.entryCount {
                        Text(L("\(count.formatted()) entri", "\(count.formatted()) entries"))
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
                Text(note)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            if item.size > 0 {
                Text(item.size.formattedBytes)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .padding(.top, 6)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? Module.privacy.colors[0].opacity(0.16) : (isHovering && !isLocked ? Color.primary.opacity(0.04) : .clear))
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onToggle)
        .onHover { isHovering = $0 }
    }

    private var note: String {
        if case .unsupported(let note) = item.action { return note }
        return item.kind.consequence
    }
}
