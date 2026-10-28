import SwiftUI

struct UninstallerView: View {
    @Bindable var model: UninstallerModel
    @State private var pendingUninstall: InstalledApp?
    @State private var runningApp: InstalledApp?
    private let module = Module.uninstaller

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            ModuleHeader(module: module) {
                Button {
                    Task { await model.load() }
                } label: {
                    Label(L("Muat Ulang", "Reload"), systemImage: "arrow.clockwise")
                }
                .buttonStyle(SoftButtonStyle())
                .disabled(model.isLoading)
            }

            HStack(alignment: .top, spacing: 18) {
                appList
                    .frame(width: 330)
                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .toast($model.toast)
        .task {
            if !model.hasLoaded { await model.load() }
        }
        .alert(
            "Uninstall \(pendingUninstall?.name ?? "")?",
            isPresented: Binding(get: { pendingUninstall != nil }, set: { if !$0 { pendingUninstall = nil } }),
            presenting: pendingUninstall
        ) { app in
            Button("Uninstall", role: .destructive) {
                Task { await model.uninstall(app) }
            }
            Button(L("Batal", "Cancel"), role: .cancel) {}
        } message: { _ in
            Text(L("Aplikasi dan \(model.selectedLeftovers.count) file terkait akan dipindahkan ke Trash.", "The app and \(model.selectedLeftovers.count) related files will be moved to the Trash."))
        }
        .alert(
            L("\(runningApp?.name ?? "") sedang berjalan", "\(runningApp?.name ?? "") is running"),
            isPresented: Binding(get: { runningApp != nil }, set: { if !$0 { runningApp = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(L("Tutup aplikasinya dulu, lalu coba uninstall lagi.", "Quit the app first, then try again."))
        }
    }

    private var appList: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(L("Cari aplikasi", "Search apps"), text: $model.search)
                    .textFieldStyle(.plain)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.05)))

            if model.isLoading && model.apps.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(model.filteredApps) { app in
                            AppRow(app: app, size: model.sizes[app.url], isSelected: model.selectedID == app.id) {
                                model.select(app)
                            }
                        }
                    }
                }
                .scrollIndicators(.automatic)
            }

            Text(L("\(model.apps.count) aplikasi · app bawaan Apple tidak ditampilkan", "\(model.apps.count) apps · Apple's built-in apps are hidden"))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .softCard(padding: 12)
        .frame(maxHeight: .infinity)
    }

    @ViewBuilder
    private var detail: some View {
        if let app = model.selectedApp {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 16) {
                    AppIcon(url: app.url, size: 76)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(app.name)
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                        Text(app.bundleID)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                        if let version = app.version {
                            Text(L("Versi \(version)", "Version \(version)"))
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }

                let appSize = model.sizes[app.url]
                HStack(spacing: 12) {
                    StatTile(title: L("Aplikasi", "App"), value: appSize?.formattedBytes ?? L("Menghitung…", "Calculating…"), colors: Palette.lavender)
                    StatTile(title: L("File sisa", "Leftovers"), value: model.leftoverSelectedSize.formattedBytes, colors: Palette.peach)
                    StatTile(title: L("Total dibersihkan", "Total to clean"), value: ((appSize ?? 0) + model.leftoverSelectedSize).formattedBytes, colors: Palette.mint)
                }

                Text(L("File terkait", "Related files"))
                    .font(.system(size: 15, weight: .bold, design: .rounded))

                Group {
                    if model.isLoadingLeftovers {
                        ProgressView(L("Mencari file sisa…", "Looking for leftovers…"))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if model.leftovers.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 28))
                                .foregroundStyle(LinearGradient.soft(module.colors))
                            Text(L("Tidak ada file sisa ditemukan.", "No leftover files found."))
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 2) {
                                ForEach(model.leftovers) { item in
                                    ItemRow(item: item, isOn: model.selectedLeftovers.contains(item.url), colors: module.colors) {
                                        model.toggle(item)
                                    }
                                }
                            }
                        }
                    }
                }
                .frame(maxHeight: .infinity)

                HStack {
                    Label(L("Semua dipindahkan ke Trash, jadi masih bisa dikembalikan.", "Everything goes to the Trash, so it can be put back."), systemImage: "arrow.uturn.backward.circle")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        if model.isRunning(app) { runningApp = app } else { pendingUninstall = app }
                    } label: {
                        Label(model.isUninstalling ? L("Menghapus…", "Removing…") : "Uninstall", systemImage: "trash")
                    }
                    .buttonStyle(GradientButtonStyle(colors: module.colors))
                    .disabled(model.isUninstalling || model.isLoadingLeftovers)
                }
            }
            .softCard(padding: 22)
            .id(app.id)
        } else {
            EmptyStateView(
                symbol: module.symbol,
                colors: module.colors,
                title: L("Pilih aplikasi", "Choose an app"),
                message: L("Pilih aplikasi di sebelah kiri untuk melihat ukurannya dan file sisa yang ikut dibersihkan.", "Pick an app on the left to see its size and the leftover files that will be cleaned too.")
            ) { EmptyView() }
            .softCard()
        }
    }
}

private struct AppRow: View {
    let app: InstalledApp
    let size: Int64?
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                AppIcon(url: app.url, size: 32)
                VStack(alignment: .leading, spacing: 1) {
                    Text(app.name)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    if let version = app.version {
                        Text(version)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                Text(size?.formattedBytes ?? "…")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected
                        ? AnyShapeStyle(LinearGradient.soft(Module.uninstaller.colors).opacity(0.2))
                        : AnyShapeStyle(isHovering ? Color.primary.opacity(0.04) : Color.clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

private struct AppIcon: View {
    let url: URL
    let size: CGFloat

    var body: some View {
        Image(nsImage: FileIcon.image(for: url, size: size))
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .shadow(color: .black.opacity(0.1), radius: size * 0.08, y: size * 0.04)
    }
}
