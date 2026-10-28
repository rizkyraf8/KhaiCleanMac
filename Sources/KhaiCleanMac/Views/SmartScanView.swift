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
                        Label("Pindai Ulang", systemImage: "arrow.clockwise")
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
        .alert("Bersihkan \(model.selectedSize.formattedBytes)?", isPresented: $confirmClean) {
            Button("Pindahkan ke Trash", role: .destructive) {
                Task { await model.clean() }
            }
            Button("Batal", role: .cancel) {}
        } message: {
            Text("Item dipindahkan ke Trash dan masih bisa dikembalikan sebelum Trash dikosongkan.\n\nCache dibuat ulang otomatis, jadi aplikasi terkait mungkin terasa sedikit lebih lambat saat pertama dibuka. Cache milik aplikasi yang sedang terbuka tidak ikut dibersihkan.")
        }
    }

    // MARK: Phases

    private var idleView: some View {
        VStack(spacing: 28) {
            Spacer()
            ScanOrb(colors: module.colors, isActive: false, label: "Pindai") {
                Task { await model.scan() }
            }
            VStack(spacing: 8) {
                Text("Siap merapikan Mac kamu?")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Text("KhaiCleanMac akan mencari file sampah di bawah ini. Tidak ada yang dihapus sebelum kamu menyetujuinya.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 440)
            }
            HStack(spacing: 10) {
                ForEach(JunkKind.allCases) { kind in
                    KindChip(kind: kind, status: .pending)
                }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var scanningView: some View {
        VStack(spacing: 28) {
            Spacer()
            ScanOrb(colors: module.colors, isActive: true, label: "Memindai…") {}
            Text(model.currentKind.map { "Memeriksa \($0.title.lowercased())…" } ?? "Menyiapkan…")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .contentTransition(.opacity)
            HStack(spacing: 10) {
                ForEach(JunkKind.allCases) { kind in
                    KindChip(kind: kind, status: status(of: kind))
                }
            }
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
                title: "Mac kamu sudah bersih!",
                message: "Tidak ada file sampah yang ditemukan. Coba pindai lagi beberapa hari ke depan."
            ) {
                Button("Selesai") { model.reset() }
                    .buttonStyle(GradientButtonStyle(colors: module.colors))
            }
        } else {
            VStack(spacing: 18) {
                summaryCard
                if !model.inUseApps.isEmpty || model.hasSystemOwners {
                    inUseNotice
                }
                ScrollView {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 16) {
                        ForEach(model.categories) { category in
                            CategoryCard(
                                category: category,
                                state: model.selectionState(of: category),
                                selectedSize: model.selectedSize(in: category),
                                inUseCount: model.inUseCount(in: category),
                                onToggle: { model.toggle(category) },
                                onDetails: { detailKind = category.kind }
                            )
                        }
                    }
                    .padding(4)
                }
                .scrollIndicators(.never)

                ActionBar(
                    caption: "Dipilih untuk dibersihkan",
                    value: model.selectedSize.formattedBytes,
                    buttonTitle: "Bersihkan",
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
                Text("Sampah ditemukan")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                Text(model.totalSize.formattedBytes)
                    .font(.system(size: 40, weight: .heavy, design: .rounded))
                    .foregroundStyle(LinearGradient.soft(module.colors))
                Text("\(model.itemCount) item di \(model.categories.count { !$0.items.isEmpty }) kategori")
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
                Text("Cache aplikasi yang sedang terbuka tidak dipilih")
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
        let system = "Cache proses sistem yang sedang aktif juga dikunci agar aman."
        guard !model.inUseApps.isEmpty else { return system }
        var text = "\(model.inUseApps.joined(separator: ", ")) sedang terbuka. Tutup aplikasinya, lalu pindai ulang kalau ingin ikut membersihkan cache-nya."
        if model.hasSystemOwners { text += " " + system }
        return text
    }

    private var cleaningView: some View {
        VStack(spacing: 20) {
            Spacer()
            ScanOrb(colors: module.colors, isActive: true, label: "Membersihkan…", symbol: "wind") {}
            Text("Memindahkan item ke Trash…")
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
            title: "Beres! \(report.movedSize.formattedBytes) dibersihkan",
            message: doneMessage(report)
        ) {
            HStack(spacing: 12) {
                Button("Buka Trash") { Permissions.openTrash() }
                    .buttonStyle(SoftButtonStyle())
                Button("Selesai") { model.reset() }
                    .buttonStyle(GradientButtonStyle(colors: module.colors))
            }
        }
    }

    private func doneMessage(_ report: CleanReport) -> String {
        var text = "\(report.movedCount) item dipindahkan ke Trash. Kosongkan Trash untuk benar-benar membebaskan ruang disk."
        if !report.failed.isEmpty {
            text += "\n\(report.failed.count) item dilewati karena sedang dipakai atau dilindungi sistem."
        }
        if !model.skippedApps.isEmpty {
            text += "\nCache \(model.skippedApps.joined(separator: ", ")) dilewati karena aplikasinya dibuka setelah pemindaian."
        }
        return text
    }

    private func status(of kind: JunkKind) -> KindChip.Status {
        if let category = model.category(kind) { return .done(category.totalSize) }
        return model.currentKind == kind ? .active : .pending
    }
}

// MARK: - Pieces

private struct KindChip: View {
    enum Status { case pending, active, done(Int64) }
    let kind: JunkKind
    let status: Status
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 8) {
            GradientIcon(symbol: kind.symbol, colors: kind.colors, size: 26, corner: 8)
            Text(kind.title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
            switch status {
            case .pending:
                EmptyView()
            case .active:
                ProgressView().controlSize(.small)
            case .done(let size):
                Text(size.formattedBytes)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(LinearGradient.soft(kind.colors))
            }
        }
        .padding(.leading, 6)
        .padding(.trailing, 12)
        .padding(.vertical, 6)
        .background(Capsule().fill(scheme == .dark ? Color.white.opacity(0.07) : Color.white.opacity(0.8)))
        .shadow(color: .black.opacity(0.04), radius: 6, y: 3)
    }
}

private struct CategoryCard: View {
    let category: JunkCategory
    let state: SelectionState
    let selectedSize: Int64
    let inUseCount: Int
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
            }
            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Text(category.totalSize.formattedBytes)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Text("\(category.items.count) item")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                if inUseCount > 0 {
                    Label("\(inUseCount) dipakai", systemImage: "lock.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Palette.sunny[1])
                        .help("Milik aplikasi yang sedang terbuka, jadi tidak ikut dibersihkan")
                }
                Spacer()
                if !category.items.isEmpty {
                    Button("Lihat detail", action: onDetails)
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
                    Text("\(model.selectedSize(in: category).formattedBytes) dipilih dari \(category.totalSize.formattedBytes)")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    model.toggle(category)
                } label: {
                    HStack(spacing: 6) {
                        CheckCircle(state: model.selectionState(of: category), colors: category.kind.colors)
                        Text("Pilih semua")
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
                Button("Selesai") { dismiss() }
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
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                .resizable()
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let lockedBy {
                    Text("\(lockedBy) sedang terbuka · tutup dulu untuk membersihkan")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Palette.sunny[1])
                        .lineLimit(1)
                } else {
                    Text(item.url.deletingLastPathComponent().abbreviatedPath)
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
            .help("Tampilkan di Finder")
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
