import SwiftUI

struct SmartScanView: View {
    @Bindable var model: SmartScanModel
    @State private var detailKind: JunkKind?
    @State private var confirmClean = false
    private let module = Module.smartScan

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            ModuleHeader(module: module) {
                if model.phase == .results {
                    Button {
                        Task { await model.scan() }
                    } label: {
                        Label(L("Pindai Ulang", "Scan Again"), systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(SoftButtonStyle())
                }
            }

            switch model.phase {
            case .idle: idleView
            case .scanning: scanningView
            case .results: resultsView
            case .cleaning: cleaningView
            case .done: doneView
            }
        }
        .sheet(item: $detailKind) { kind in
            if let category = model.category(kind) {
                CategoryDetailSheet(model: model, category: category)
            }
        }
        .alert(L("Bersihkan \(model.selectedSize.formattedBytes)?", "Clean \(model.selectedSize.formattedBytes)?"), isPresented: $confirmClean) {
            Button(Removal.actionTitle, role: .destructive) {
                Task { await model.clean() }
            }
            Button(L("Batal", "Cancel"), role: .cancel) {}
        } message: {
            Text(confirmMessage)
        }
    }

    private var confirmMessage: String {
        var text = Removal.isPermanent
            ? L("Mode hapus permanen aktif: item langsung dihapus dan tidak bisa dikembalikan.", "Delete permanently is on: items are removed right away and can't be put back.")
            : L("Item dipindahkan ke Trash dan masih bisa dikembalikan sebelum Trash dikosongkan.", "Items go to the Trash and can be put back until you empty it.")
        if model.selectedTrashCount > 0 {
            text += L("\n\n\(model.selectedTrashCount) item dari Trash dihapus permanen.", "\n\n\(model.selectedTrashCount) items from the Trash are deleted permanently.")
        }
        text += L("\n\nCache dibuat ulang otomatis, jadi aplikasi terkait mungkin terasa sedikit lebih lambat saat pertama dibuka. Cache milik aplikasi yang sedang terbuka tidak ikut dibersihkan.",
                  "\n\nCaches are rebuilt automatically, so related apps may feel a little slower the first time they open. Caches of apps that are currently open are left alone.")
        return text
    }

    // MARK: Phases

    private var idleView: some View {
        VStack(spacing: 28) {
            Spacer()
            ScanOrb(colors: module.colors, isActive: false, label: L("Pindai", "Scan")) {
                Task { await model.scan() }
            }
            VStack(spacing: 8) {
                Text(L("Siap merapikan Mac kamu?", "Ready to tidy up your Mac?"))
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Text(L("KhaiCleanMac akan mencari file sampah di bawah ini. Tidak ada yang dihapus sebelum kamu menyetujuinya.", "KhaiCleanMac looks for the junk below. Nothing is removed until you approve it."))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 440)
            }
            KindGrid { _ in .idle }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var scanningView: some View {
        VStack(spacing: 24) {
            Spacer()
            ScanOrb(colors: module.colors, isActive: true, label: L("Memindai…", "Scanning…")) {}
            ScanProgressBar(
                title: model.currentKind.map { L("Memeriksa \($0.title.lowercased())…", "Checking \($0.title.lowercased())…") } ?? L("Menyiapkan…", "Getting ready…"),
                done: model.categories.count,
                total: JunkKind.allCases.count,
                found: model.totalSize,
                colors: module.colors
            )
            KindGrid { status(of: $0) }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var resultsView: some View {
        if model.totalSize == 0 {
            EmptyStateView(
                symbol: "checkmark.seal.fill",
                colors: module.colors,
                title: L("Mac kamu sudah bersih!", "Your Mac is already clean!"),
                message: L("Tidak ada file sampah yang ditemukan. Coba pindai lagi beberapa hari ke depan.", "No junk found. Try scanning again in a few days.")
            ) {
                Button(L("Selesai", "Done")) { model.reset() }
                    .buttonStyle(GradientButtonStyle(colors: module.colors))
            }
        } else {
            VStack(spacing: 18) {
                // Everything but the action bar scrolls, so the notices can't squeeze the categories
                // into a sliver on a small screen.
                ScrollView {
                    VStack(spacing: 18) {
                        summaryCard
                        if !model.inUseApps.isEmpty || model.hasSystemOwners {
                            inUseNotice
                        }
                        if let update = model.chromeUpdate {
                            ChromeUpdateNotice(update: update, isChromeRunning: model.isChromeRunning)
                        }
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 16) {
                            ForEach(model.categories) { category in
                                CategoryCard(
                                    category: category,
                                    state: model.selectionState(of: category),
                                    selectedSize: model.selectedSize(in: category),
                                    inUseCount: model.inUseCount(in: category),
                                    needsAccess: category.kind.needsFullDiskAccess && !model.hasFullDiskAccess && category.items.isEmpty,
                                    onToggle: { model.toggle(category) },
                                    onDetails: { detailKind = category.kind }
                                )
                            }
                        }
                    }
                    .padding(4)
                }
                .scrollIndicators(.never)

                ActionBar(
                    caption: L("Dipilih untuk dibersihkan", "Selected for cleanup"),
                    value: model.selectedSize.formattedBytes,
                    buttonTitle: L("Bersihkan", "Clean"),
                    buttonSymbol: "sparkles",
                    colors: module.colors,
                    isDisabled: model.selected.isEmpty
                ) {
                    confirmClean = true
                }
            }
        }
    }

    private var summaryCard: some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L("Sampah ditemukan", "Junk found"))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                Text(model.totalSize.formattedBytes)
                    .font(.system(size: 40, weight: .heavy, design: .rounded))
                    .foregroundStyle(LinearGradient.soft(module.colors))
                Text(L("\(model.itemCount) item di \(model.categories.count { !$0.items.isEmpty }) kategori",
                       "\(model.itemCount) items in \(model.categories.count { !$0.items.isEmpty }) categories"))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            SegmentRing(categories: model.categories)
                .frame(width: 96, height: 96)
        }
        .softCard(padding: 22)
    }

    private var inUseNotice: some View {
        HStack(spacing: 14) {
            GradientIcon(symbol: "app.badge.fill", colors: Palette.sunny, size: 36, corner: 11)
            VStack(alignment: .leading, spacing: 2) {
                Text(L("Cache aplikasi yang sedang terbuka tidak dipilih", "Caches of open apps are not selected"))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                Text(inUseMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .softCard(padding: 14, radius: 18)
    }

    private var inUseMessage: String {
        let system = L("Cache proses sistem yang sedang aktif juga dikunci agar aman.", "Caches of active system processes are locked too, to stay safe.")
        guard !model.inUseApps.isEmpty else { return system }
        let apps = model.inUseApps.joined(separator: ", ")
        var text = L("\(apps) sedang terbuka. Tutup aplikasinya, lalu pindai ulang kalau ingin ikut membersihkan cache-nya.",
                     "\(apps) \(model.inUseApps.count == 1 ? "is" : "are") open. Quit them and scan again if you want to clean their caches too.")
        if model.hasSystemOwners { text += " " + system }
        return text
    }

    private var cleaningView: some View {
        VStack(spacing: 20) {
            Spacer()
            ScanOrb(colors: module.colors, isActive: true, label: L("Membersihkan…", "Cleaning…"), symbol: "wind") {}
            Text(Removal.progressText)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var doneView: some View {
        let report = model.report ?? CleanReport()
        return EmptyStateView(
            symbol: "checkmark.circle.fill",
            colors: module.colors,
            title: L("Beres! \(report.movedSize.formattedBytes) dibersihkan", "All done! \(report.movedSize.formattedBytes) cleaned"),
            message: doneMessage(report)
        ) {
            HStack(spacing: 12) {
                if !report.permanent {
                    Button(L("Buka Trash", "Open Trash")) { Permissions.openTrash() }
                        .buttonStyle(SoftButtonStyle())
                }
                Button(L("Selesai", "Done")) { model.reset() }
                    .buttonStyle(GradientButtonStyle(colors: module.colors))
            }
        }
    }

    private func doneMessage(_ report: CleanReport) -> String {
        var text = report.permanent
            ? L("\(report.movedCount) item dihapus permanen.", "\(report.movedCount) \(report.movedCount == 1 ? "item" : "items") deleted permanently.")
            : L("\(report.movedCount) item dipindahkan ke Trash. Kosongkan Trash untuk benar-benar membebaskan ruang disk.",
                "\(report.movedCount) \(report.movedCount == 1 ? "item" : "items") moved to the Trash. Empty the Trash to actually free up disk space.")
        if !report.failed.isEmpty {
            text += L("\n\(report.failed.count) item dilewati karena sedang dipakai atau dilindungi sistem.",
                      "\n\(report.failed.count) skipped because they are in use or protected by the system.")
        }
        if !model.skippedApps.isEmpty {
            let apps = model.skippedApps.joined(separator: ", ")
            text += L("\nCache \(apps) dilewati karena aplikasinya dibuka setelah pemindaian.",
                      "\nSkipped the caches of \(apps) because those apps were opened after the scan.")
        }
        return text
    }

    private func status(of kind: JunkKind) -> KindTile.Status {
        if let category = model.category(kind) { return .done(category.totalSize) }
        return model.currentKind == kind ? .active : .pending
    }
}

// MARK: - Pieces

/// Overall scan progress: which category is being checked, how many are done, and what's found so far.
private struct ScanProgressBar: View {
    let title: String
    let done: Int
    let total: Int
    let found: Int64
    let colors: [Color]

    private var fraction: Double { total > 0 ? Double(done) / Double(total) : 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .contentTransition(.opacity)
                Spacer(minLength: 16)
                Text(L("\(done) dari \(total) kategori", "\(done) of \(total) categories"))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08))
                    Capsule()
                        .fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(12, geo.size.width * fraction))
                }
            }
            .frame(height: 10)
            .animation(.smooth, value: fraction)
            Text(found > 0
                 ? L("\(found.formattedBytes) ditemukan sejauh ini", "\(found.formattedBytes) found so far")
                 : L("Belum ada yang ditemukan", "Nothing found yet"))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
        }
        .softCard(padding: 18, radius: 18)
        .frame(maxWidth: 620)
    }
}

/// Every Smart Scan category as a tile, four per row so long names never wrap letter by letter.
private struct KindGrid: View {
    let status: (JunkKind) -> KindTile.Status

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
            ForEach(JunkKind.allCases) { kind in
                KindTile(kind: kind, status: status(kind))
            }
        }
        .frame(maxWidth: 860)
    }
}

private struct KindTile: View {
    enum Status { case idle, pending, active, done(Int64) }
    let kind: JunkKind
    let status: Status
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 10) {
            GradientIcon(symbol: kind.symbol, colors: kind.colors, size: 32, corner: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(kind.title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Text(caption)
                    .font(.system(size: 11, weight: isDone ? .bold : .regular, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            switch status {
            case .active:
                ProgressView().controlSize(.small)
            case .done:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(LinearGradient.soft(kind.colors))
            case .idle, .pending:
                EmptyView()
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(scheme == .dark ? Color.white.opacity(0.07) : Color.white.opacity(0.82))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(LinearGradient.soft(kind.colors), lineWidth: isActive ? 2 : 0)
        )
        .shadow(color: .black.opacity(0.04), radius: 6, y: 3)
        .opacity(isPending ? 0.55 : 1)
        .animation(.snappy, value: caption)
    }

    private var caption: String {
        switch status {
        case .idle: L("Akan diperiksa", "Will be checked")
        case .pending: L("Menunggu", "Waiting")
        case .active: L("Memeriksa…", "Checking…")
        case .done(let size): size > 0 ? size.formattedBytes : L("Bersih", "Clean")
        }
    }

    private var isActive: Bool { if case .active = status { true } else { false } }
    private var isPending: Bool { if case .pending = status { true } else { false } }
    private var isDone: Bool { if case .done = status { true } else { false } }
}

private struct CategoryCard: View {
    let category: JunkCategory
    let state: SelectionState
    let selectedSize: Int64
    let inUseCount: Int
    var needsAccess = false
    let onToggle: () -> Void
    let onDetails: () -> Void

    private var kind: JunkKind { category.kind }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                GradientIcon(symbol: kind.symbol, colors: kind.colors, size: 46)
                Spacer()
                Button(action: onToggle) {
                    CheckCircle(state: state, colors: kind.colors)
                }
                .buttonStyle(.plain)
                .disabled(category.items.isEmpty)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(kind.title)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                Text(kind.subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2, reservesSpace: true)
                if needsAccess {
                    Label(L("Butuh Akses Disk Penuh untuk dibaca", "Needs Full Disk Access to read"), systemImage: "lock.shield")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Palette.peach[1])
                }
            }
            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Text(category.totalSize.formattedBytes)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Text(L("\(category.items.count) item", "\(category.items.count) items"))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                if inUseCount > 0 {
                    Label(L("\(inUseCount) dipakai", "\(inUseCount) in use"), systemImage: "lock.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Palette.sunny[1])
                        .help(L("Milik aplikasi yang sedang terbuka, jadi tidak ikut dibersihkan", "Belongs to an open app, so it won't be cleaned"))
                }
                Spacer()
                if !category.items.isEmpty {
                    Button(L("Lihat detail", "Details"), action: onDetails)
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(LinearGradient.soft(kind.colors))
                }
            }
        }
        .softCard()
        .opacity(category.items.isEmpty ? 0.6 : 1)
    }
}

/// Donut showing how much each category contributes.
private struct SegmentRing: View {
    let categories: [JunkCategory]

    var body: some View {
        let total = max(Double(categories.reduce(0) { $0 + $1.totalSize }), 1)
        let segments = categories.reduce(into: [(JunkKind, Double, Double)]()) { acc, category in
            let start = acc.last?.2 ?? 0
            acc.append((category.kind, start, start + Double(category.totalSize) / total))
        }
        ZStack {
            Circle().stroke(Color.primary.opacity(0.07), lineWidth: 14)
            ForEach(segments, id: \.0) { kind, start, end in
                Circle()
                    .trim(from: start, to: max(start, end - 0.004))
                    .stroke(LinearGradient.soft(kind.colors), style: StrokeStyle(lineWidth: 14, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
            }
            Image(systemName: "sparkles")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(LinearGradient.soft(Palette.logo))
        }
    }
}

private struct CategoryDetailSheet: View {
    @Bindable var model: SmartScanModel
    let category: JunkCategory
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                GradientIcon(symbol: category.kind.symbol, colors: category.kind.colors, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(category.kind.title)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                    Text(L("\(model.selectedSize(in: category).formattedBytes) dipilih dari \(category.totalSize.formattedBytes)",
                           "\(model.selectedSize(in: category).formattedBytes) selected of \(category.totalSize.formattedBytes)"))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    model.toggle(category)
                } label: {
                    HStack(spacing: 6) {
                        CheckCircle(state: model.selectionState(of: category), colors: category.kind.colors)
                        Text(L("Pilih semua", "Select all"))
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
            }

            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(category.items) { item in
                        ItemRow(
                            item: item,
                            isOn: model.selected.contains(item.url),
                            colors: category.kind.colors,
                            lockedBy: model.owner(of: item)
                        ) {
                            model.toggle(item)
                        }
                    }
                }
            }
            .softCard(padding: 8, radius: 16)

            HStack {
                Spacer()
                Button(L("Selesai", "Done")) { dismiss() }
                    .buttonStyle(GradientButtonStyle(colors: category.kind.colors))
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 620, height: 560)
        .background(SoftBackground(colors: category.kind.colors))
    }
}

/// Selectable row for a single file or folder, shared by Smart Scan and Uninstaller.
struct ItemRow: View {
    let item: CleanItem
    let isOn: Bool
    let colors: [Color]
    /// Name of the open app that owns this item; the row is locked while it runs.
    var lockedBy: String? = nil
    let onToggle: () -> Void
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 12) {
            if lockedBy != nil {
                Image(systemName: "lock.circle.fill")
                    .font(.system(size: 19))
                    .foregroundStyle(Palette.sunny[1])
                    .frame(width: 20, height: 20)
            } else {
                CheckCircle(isOn: isOn, colors: colors)
            }
            Image(nsImage: FileIcon.image(for: item.url, size: 24))
                .resizable()
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let lockedBy {
                    Text(L("\(lockedBy) sedang terbuka · tutup dulu untuk membersihkan", "\(lockedBy) is open · quit it to clean this"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Palette.sunny[1])
                        .lineLimit(1)
                } else {
                    Text(item.detail ?? item.url.deletingLastPathComponent().abbreviatedPath)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }
            Spacer(minLength: 12)
            Text(item.size.formattedBytes)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            } label: {
                Image(systemName: "arrow.up.forward.square")
            }
            .buttonStyle(.borderless)
            .help(L("Tampilkan di Finder", "Show in Finder"))
            .opacity(isHovering ? 1 : 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(isHovering ? Color.primary.opacity(0.04) : .clear))
        .contentShape(Rectangle())
        .onTapGesture(perform: onToggle)
        .onHover { isHovering = $0 }
    }
}

/// Explains old Chrome versions instead of deleting them: while Chrome waits for a relaunch,
/// the "old" version is the one that is running.
private struct ChromeUpdateNotice: View {
    let update: ChromeUpdateInfo
    let isChromeRunning: Bool

    var body: some View {
        HStack(spacing: 14) {
            GradientIcon(symbol: "arrow.clockwise", colors: JunkKind.browsers.colors, size: 36, corner: 11)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .softCard(padding: 14, radius: 18)
    }

    private var title: String {
        guard update.hasOldVersions else {
            return L("Google Updater menyimpan versi lama", "Google Updater keeps old versions")
        }
        return isChromeRunning
            ? L("Chrome menunggu relaunch · \(update.oldVersionsSize.formattedBytes) bisa kembali", "Chrome is waiting to relaunch · \(update.oldVersionsSize.formattedBytes) to reclaim")
            : L("Versi Chrome lama · \(update.oldVersionsSize.formattedBytes)", "Old Chrome version · \(update.oldVersionsSize.formattedBytes)")
    }

    private var message: String {
        var parts: [String] = []
        if update.hasOldVersions {
            let versions = update.oldVersions.joined(separator: ", ")
            parts.append(isChromeRunning
                ? L("Versi \(versions) masih dipakai Chrome yang sedang terbuka, jadi tidak dihapus. Pilih menu Chrome › Relaunch, nanti Chrome menghapus versi lama itu sendiri. Setelah itu pindai ulang, karena Code Cache dari versi lama ikut jadi usang.",
                    "Version \(versions) is still used by the Chrome you have open, so it isn't removed. Choose Chrome › Relaunch and Chrome deletes the old version itself. Then scan again, as the old version's code cache becomes obsolete too.")
                : L("Versi \(versions) tidak dihapus dari dalam Chrome.app. Buka Chrome sekali, nanti Chrome menghapusnya sendiri.",
                    "Version \(versions) isn't removed from inside Chrome.app. Open Chrome once and it deletes it itself."))
        }
        if update.updaterLeftovers > 0 {
            parts.append(L("\(update.updaterLeftovers) versi lama Google Updater ada di folder sistem dan butuh izin admin, jadi dilewati.",
                           "\(update.updaterLeftovers) old Google Updater versions sit in the system Library and need admin rights, so they are skipped."))
        }
        return parts.joined(separator: " ")
    }
}
