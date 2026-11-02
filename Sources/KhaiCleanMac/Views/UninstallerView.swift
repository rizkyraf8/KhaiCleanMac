import SwiftUI

enum UninstallerTab: String, CaseIterable, Identifiable {
    case apps, leftovers, languages

    var id: String { rawValue }

    var title: String {
        switch self {
        case .apps: L("Aplikasi", "Apps")
        case .leftovers: L("Sisa app terhapus", "Leftovers of removed apps")
        case .languages: L("Bahasa", "Languages")
        }
    }
}

struct UninstallerView: View {
    @Bindable var model: UninstallerModel
    @State private var tab: UninstallerTab = .apps
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

            Picker(L("Tampilan", "View"), selection: $tab) {
                ForEach(UninstallerTab.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 520)

            switch tab {
            case .apps:
                HStack(alignment: .top, spacing: 18) {
                    appList
                        .frame(width: 330)
                    detail
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            case .leftovers:
                OrphanLeftoversView(model: model.orphans)
            case .languages:
                LanguageReportView(model: model.languages, apps: model.apps)
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
            Text(Removal.isPermanent
                ? L("Aplikasi dan \(model.selectedLeftovers.count) file terkait akan dihapus permanen.", "The app and \(model.selectedLeftovers.count) related files will be deleted permanently.")
                : L("Aplikasi dan \(model.selectedLeftovers.count) file terkait akan dipindahkan ke Trash.", "The app and \(model.selectedLeftovers.count) related files will be moved to the Trash."))
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
                    Label(Removal.undoNote, systemImage: Removal.isPermanent ? "exclamationmark.triangle" : "arrow.uturn.backward.circle")
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

/// Files in ~/Library named after apps that aren't on this Mac anymore.
private struct OrphanLeftoversView: View {
    @Bindable var model: OrphanLeftoversModel
    @State private var confirm = false
    private let colors = Module.uninstaller.colors

    var body: some View {
        Group {
            switch model.phase {
            case .idle:
                EmptyStateView(
                    symbol: "questionmark.folder.fill", colors: colors,
                    title: L("Cari sisa app yang sudah dihapus", "Find leftovers of removed apps"),
                    message: L("App yang dibuang langsung ke Trash meninggalkan cache, preferensi, dan container. KhaiCleanMac mencari yang namanya cocok dengan ID app yang tidak ada lagi di Mac ini dan tidak diubah dua minggu terakhir. Tidak ada yang dipilih otomatis.",
                               "Apps dragged straight to the Trash leave caches, preferences and containers behind. KhaiCleanMac looks for entries named after an app ID no longer on this Mac and unchanged for two weeks. Nothing is preselected.")
                ) {
                    Button {
                        model.scan()
                    } label: {
                        Label(L("Mulai Pindai", "Start Scan"), systemImage: "magnifyingglass")
                    }
                    .buttonStyle(GradientButtonStyle(colors: colors))
                }
            case .scanning:
                ProgressView(L("Mencocokkan dengan app yang terpasang…", "Matching against installed apps…"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .results:
                if model.leftovers.isEmpty {
                    EmptyStateView(symbol: "checkmark.seal.fill", colors: colors,
                                   title: L("Tidak ada sisa", "No leftovers"),
                                   message: L("Semua yang ada di Library milik app yang masih terpasang.", "Everything in your Library belongs to an app that's still installed.")) {
                        Button(L("Pindai Ulang", "Scan Again")) { model.scan() }
                            .buttonStyle(GradientButtonStyle(colors: colors))
                    }
                } else {
                    VStack(spacing: 16) {
                        ScrollView {
                            VStack(spacing: 2) {
                                HStack(alignment: .top) {
                                    Text(L("Tool command-line dan helper latar belakang juga bisa memakai ID seperti ini. Periksa ID-nya sebelum menghapus.",
                                           "Command-line tools and background helpers can use IDs like these too. Check the ID before removing."))
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Spacer()
                                    Button(L("Pindai Ulang", "Scan Again")) { model.scan() }
                                        .buttonStyle(SoftButtonStyle())
                                }
                                .padding(.horizontal, 10)
                                .padding(.bottom, 8)
                                ForEach(model.leftovers) { leftover in
                                    FileRow(url: leftover.url, size: leftover.size, lastUsed: leftover.modified,
                                            detail: [leftover.location, leftover.note].compactMap { $0 }.joined(separator: " · "),
                                            colors: colors, isSelected: model.selected.contains(leftover.url)) {
                                        model.toggle(leftover)
                                    }
                                }
                            }
                            .softCard(padding: 12)
                            .padding(4)
                        }
                        .scrollIndicators(.never)
                        ActionBar(
                            caption: L("\(model.selected.count) dipilih · total \(model.totalSize.formattedBytes)", "\(model.selected.count) selected · \(model.totalSize.formattedBytes) in all"),
                            value: model.selectedSize.formattedBytes,
                            buttonTitle: Removal.actionTitle, buttonSymbol: Removal.actionSymbol, colors: colors,
                            isDisabled: model.selected.isEmpty || model.isCleaning,
                            action: { confirm = true }
                        ) {
                            if !model.selected.isEmpty {
                                AIReviewButton {
                                    let chosen = model.leftovers.filter { model.selected.contains($0.url) }
                                    return AIAnalyst.inputs(chosen.map(\.item), lastUsed: Dictionary(chosen.compactMap { item in item.modified.map { (item.url, $0) } }) { a, _ in a },
                                                            context: "~/Library entries named after an app ID that no installed app has")
                                }
                            }
                        }
                    }
                }
            }
        }
        .toast($model.toast)
        .alert(Removal.question(L("\(model.selected.count) item", "\(model.selected.count) items")), isPresented: $confirm) {
            Button(Removal.actionTitle, role: .destructive) { Task { await model.moveSelectedToTrash() } }
            Button(L("Batal", "Cancel"), role: .cancel) {}
        } message: {
            Text(L("Total \(model.selectedSize.formattedBytes). Kalau ternyata app-nya masih ada di tempat lain (misalnya disk eksternal), ia akan mulai dengan pengaturan baru. ", "Total \(model.selectedSize.formattedBytes). If the app turns out to be somewhere else (an external disk, say), it starts with fresh settings. ") + Removal.undoNote)
        }
    }
}

/// Read-only: which apps carry translations none of the Mac's languages use.
private struct LanguageReportView: View {
    let model: LanguageReportModel
    let apps: [InstalledApp]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                GradientIcon(symbol: "character.bubble.fill", colors: Palette.grape, size: 42)
                VStack(alignment: .leading, spacing: 3) {
                    Text(L("Bahasa yang tidak dipakai", "Unused languages"))
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                    Text(L("Terjemahan di dalam app untuk bahasa selain yang dipakai Mac ini. Hanya laporan: menghapus file di dalam app merusak tanda tangan kodenya, sehingga macOS bisa menolak membukanya dan update-nya bisa gagal.",
                           "Translations inside apps for languages this Mac doesn't use. Report only: removing files inside an app breaks its code signature, so macOS may refuse to open it and its updates may fail."))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                if model.isMeasuring { ProgressView().controlSize(.small) }
                Text(model.totalSize.formattedBytes)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
            }
            .softCard()

            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(model.apps) { entry in
                        HStack(spacing: 10) {
                            AppIcon(url: entry.app.url, size: 28)
                            Text(entry.app.name)
                                .font(.system(size: 13, weight: .semibold))
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            Text(L("\(entry.unusedCount) dari \(entry.totalCount) bahasa tidak dipakai", "\(entry.unusedCount) of \(entry.totalCount) languages unused"))
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                            Text(entry.unusedSize.formattedBytes)
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .frame(width: 76, alignment: .trailing)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                    }
                }
                .softCard(padding: 12)
                .padding(4)
            }
            .scrollIndicators(.never)
        }
        .task(id: apps.map(\.url)) {
            model.measureIfChanged(apps)
        }
    }
}
