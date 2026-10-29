import SwiftUI

struct ExtensionsView: View {
    @Bindable var model: ExtensionsModel
    @State private var pendingRemoval: LegacyPlugin?
    private let module = Module.extensions

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

            HStack(spacing: 12) {
                StatTile(title: L("Ekstensi aplikasi aktif", "Active app extensions"), value: "\(model.enabledCount) / \(model.extensions.count)", colors: module.colors)
                StatTile(title: L("Plug-in milikmu", "Your plug-ins"), value: "\(model.userPlugins.count)", colors: Palette.peach)
                StatTile(title: L("Plug-in sistem", "System plug-ins"), value: "\(model.systemPlugins.count)", colors: Palette.slate)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if model.isLoading && !model.hasLoaded {
                        ProgressView().frame(maxWidth: .infinity).padding(40)
                    }
                    if model.hasLoaded && model.extensions.isEmpty && model.plugins.isEmpty {
                        EmptyStateView(symbol: module.symbol, colors: module.colors,
                                       title: L("Tidak ada ekstensi pihak ketiga", "No third-party extensions"),
                                       message: L("Ekstensi bawaan Apple tidak ditampilkan.", "Apple's own extensions aren't shown.")) { EmptyView() }
                    }
                    ForEach(model.groups, id: \.kind) { group in
                        card(title: group.kind.title, symbol: group.kind.symbol,
                             caption: L("Mematikan ekstensi bisa dibatalkan kapan saja, aplikasinya tidak ikut terhapus.",
                                        "Turning an extension off can be undone anytime; its app stays.")) {
                            ForEach(group.items) { ext in extensionRow(ext) }
                        }
                    }
                    if !model.userPlugins.isEmpty {
                        card(title: L("Plug-in & Quick Action milikmu", "Your plug-ins & Quick Actions"), symbol: "puzzlepiece.fill",
                             caption: L("Dari ~/Library. Menghapusnya memindahkan bundelnya ke Trash, dan tercatat di Riwayat.",
                                        "From ~/Library. Removing one moves its bundle to the Trash and logs it in History.")) {
                            ForEach(model.userPlugins) { pluginRow($0) }
                        }
                    }
                    if !model.systemPlugins.isEmpty {
                        card(title: L("Plug-in sistem", "System plug-ins"), symbol: "lock.fill",
                             caption: L("Dari /Library. Dipasang dengan izin admin, jadi di sini hanya ditampilkan. Plug-in browser dan panel Java sudah lama tidak dipakai macOS modern.",
                                        "From /Library. Installed with admin rights, so shown read-only. Browser plug-ins and Java panes are long unused on modern macOS.")) {
                            ForEach(model.systemPlugins) { pluginRow($0) }
                        }
                    }
                }
                .padding(4)
            }
            .scrollIndicators(.never)
        }
        .toast($model.toast)
        .task { if !model.hasLoaded { await model.load() } }
        .alert(Removal.question(pendingRemoval?.name ?? ""),
               isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } }),
               presenting: pendingRemoval) { plugin in
            Button(Removal.actionTitle, role: .destructive) { Task { await model.remove(plugin) } }
            Button(L("Batal", "Cancel"), role: .cancel) {}
        } message: { _ in
            Text(Removal.undoNote)
        }
    }

    private func card<Content: View>(title: String, symbol: String, caption: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                GradientIcon(symbol: symbol, colors: module.colors, size: 30, corner: 9)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 14, weight: .bold, design: .rounded))
                    Text(caption).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            content()
        }
        .softCard(padding: 16)
    }

    private func extensionRow(_ ext: AppExtension) -> some View {
        HStack(spacing: 12) {
            Group {
                if let app = ext.appURL {
                    Image(nsImage: FileIcon.image(for: app, size: 28)).resizable()
                } else {
                    GradientIcon(symbol: ext.kind.symbol, colors: Palette.slate, size: 28, corner: 8)
                }
            }
            .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(ext.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Text([ext.appURL?.deletingPathExtension().lastPathComponent, ext.version].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            if model.busy.contains(ext.id) { ProgressView().controlSize(.small) }
            revealButton(URL(filePath: ext.path))
            Toggle("", isOn: Binding(get: { ext.isEnabled }, set: { _ in Task { await model.toggle(ext) } }))
                .toggleStyle(.switch).labelsHidden().controlSize(.small)
                .disabled(model.busy.contains(ext.id))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .opacity(ext.isEnabled ? 1 : 0.6)
    }

    private func pluginRow(_ plugin: LegacyPlugin) -> some View {
        HStack(spacing: 12) {
            Image(nsImage: FileIcon.image(for: plugin.url, size: 28)).resizable().frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(plugin.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Text([plugin.kind.title, plugin.bundleID].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 8)
            Text(plugin.size.formattedBytes).font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundStyle(.secondary)
            revealButton(plugin.url)
            if !plugin.isSystem {
                Button(L("Hapus", "Remove")) { pendingRemoval = plugin }
                    .buttonStyle(SoftButtonStyle())
                    .disabled(model.busy.contains(plugin.url.path))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private func revealButton(_ url: URL) -> some View {
        Button {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } label: {
            Image(systemName: "arrow.up.forward.square")
        }
        .buttonStyle(.borderless)
        .help(L("Tampilkan di Finder", "Show in Finder"))
    }
}
