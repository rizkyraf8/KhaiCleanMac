import SwiftUI

struct SystemDataView: View {
    @Bindable var model: SystemDataModel
    let onOpen: (Module) -> Void
    @State private var confirmSnapshots = false
    private let module = Module.systemData

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            ModuleHeader(module: module) {
                if model.phase != .idle {
                    Button {
                        model.measure()
                    } label: {
                        Label(L("Ukur Ulang", "Measure Again"), systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(SoftButtonStyle())
                    .disabled(model.phase == .measuring)
                }
            }

            if model.phase == .idle {
                EmptyStateView(
                    symbol: module.symbol, colors: module.colors,
                    title: L("Apa isi System Data?", "What's in System Data?"),
                    message: L("System Settings menyebut semua ini \"System Data\" tanpa rincian. KhaiCleanMac mengukur folder-folder di baliknya dan menunjukkan mana yang bisa dibersihkan. Hanya membaca ukuran, tidak ada yang dihapus.",
                               "System Settings calls all of this \"System Data\" without a breakdown. KhaiCleanMac measures the folders behind it and shows which parts can be cleaned. It only reads sizes; nothing is removed.")
                ) {
                    Button {
                        model.measure()
                    } label: {
                        Label(L("Ukur Sekarang", "Measure Now"), systemImage: "ruler")
                    }
                    .buttonStyle(GradientButtonStyle(colors: module.colors))
                }
            } else {
                ScrollView {
                    VStack(spacing: 16) {
                        HStack(spacing: 10) {
                            StatTile(title: L("Terukur", "Measured"), value: model.measuredTotal.formattedBytes, colors: module.colors)
                            StatTile(title: L("Bisa dikosongkan macOS", "macOS can free"), value: model.purgeable?.formattedBytes ?? "—", colors: Palette.mint)
                            StatTile(title: L("Snapshot lokal", "Local snapshots"), value: "\(model.snapshots.count)", colors: Palette.lavender)
                        }
                        snapshotCard
                        VStack(spacing: 2) {
                            ForEach(model.buckets) { bucket in
                                BucketRow(bucket: bucket, largest: model.buckets.compactMap(\.size).max() ?? 1,
                                          onOpen: onOpen, onReveal: { model.showInFinder(bucket) })
                            }
                        }
                        .softCard(padding: 12)
                        Text(L("Folder yang butuh Full Disk Access (Mail, Messages, sebagian container) bisa terukur lebih kecil tanpanya. Cache dan log sistem hanya terukur sebagian karena milik macOS.",
                               "Folders that need Full Disk Access (Mail, Messages, some containers) may measure smaller without it. System caches and logs are only partly readable, since they belong to macOS."))
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(4)
                }
                .scrollIndicators(.never)
            }
        }
        .toast($model.toast)
        .alert(L("Hapus \(model.snapshots.count) snapshot lokal?", "Delete \(model.snapshots.count) local snapshots?"), isPresented: $confirmSnapshots) {
            Button(L("Hapus Snapshot", "Delete Snapshots"), role: .destructive) { Task { await model.deleteSnapshots() } }
            Button(L("Batal", "Cancel"), role: .cancel) {}
        } message: {
            Text(L("Snapshot dihapus permanen oleh Time Machine, dan macOS akan meminta password administrator. Backup di disk Time Machine tidak tersentuh, tapi file yang kamu hapus sejak backup terakhir tidak bisa lagi dikembalikan dari snapshot. Time Machine membuat snapshot baru saat backup berikutnya.",
                   "Time Machine deletes the snapshots for good, and macOS asks for an administrator password. Backups on your Time Machine disk aren't touched, but files you deleted since the last backup can no longer be restored from a snapshot. Time Machine makes new snapshots with the next backup."))
        }
    }

    private var snapshotCard: some View {
        HStack(alignment: .top, spacing: 14) {
            GradientIcon(symbol: "clock.arrow.2.circlepath", colors: Palette.lavender, size: 42)
            VStack(alignment: .leading, spacing: 4) {
                Text(L("Snapshot lokal Time Machine", "Local Time Machine snapshots"))
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                Text(model.snapshots.isEmpty
                     ? L("Tidak ada snapshot lokal di disk startup.", "There are no local snapshots on the startup disk.")
                     : L("Time Machine menyimpan file yang berubah atau terhapus di disk ini sampai backup berikutnya. macOS menghapusnya sendiri saat butuh ruang, tapi sampai saat itu ruangnya terhitung terpakai.",
                         "Time Machine keeps files that changed or were deleted on this disk until the next backup. macOS removes them on its own when it needs space, but until then the space counts as used."))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !model.snapshots.isEmpty {
                    Text(model.snapshots.prefix(4).compactMap { $0.date?.formatted(date: .abbreviated, time: .shortened) }.joined(separator: " · ")
                         + (model.snapshots.count > 4 ? L(" · dan \(model.snapshots.count - 4) lagi", " · and \(model.snapshots.count - 4) more") : ""))
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            if model.isDeletingSnapshots {
                ProgressView().controlSize(.small)
            } else if !model.snapshots.isEmpty {
                Button {
                    confirmSnapshots = true
                } label: {
                    Label(L("Hapus", "Delete"), systemImage: "trash")
                }
                .buttonStyle(GradientButtonStyle(colors: Palette.lavender))
            }
        }
        .softCard()
    }
}

private struct BucketRow: View {
    let bucket: StorageBucket
    let largest: Int64
    let onOpen: (Module) -> Void
    let onReveal: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            GradientIcon(symbol: bucket.symbol, colors: bucket.colors, size: 34, corner: 10)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(bucket.title)
                        .font(.system(size: 13, weight: .semibold))
                    Spacer(minLength: 8)
                    if let size = bucket.size {
                        Text(size.formattedBytes)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                    } else {
                        ProgressView().controlSize(.mini)
                    }
                }
                GeometryReader { proxy in
                    Capsule().fill(Color.primary.opacity(0.06))
                        .overlay(alignment: .leading) {
                            Capsule().fill(LinearGradient(colors: bucket.colors, startPoint: .leading, endPoint: .trailing))
                                .frame(width: proxy.size.width * CGFloat(Double(bucket.size ?? 0) / Double(max(largest, 1))))
                        }
                }
                .frame(height: 5)
                Text(bucket.detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            action
                .frame(width: 120, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
    }

    @ViewBuilder
    private var action: some View {
        switch bucket.action {
        case .module(let module):
            Button {
                onOpen(module)
            } label: {
                Label(module.title, systemImage: "arrow.right.circle")
                    .lineLimit(1)
            }
            .buttonStyle(SoftButtonStyle())
        case .showInFinder:
            Button(L("Tampilkan", "Show"), action: onReveal)
                .buttonStyle(SoftButtonStyle())
        case .none:
            EmptyView()
        }
    }
}

struct ICloudView: View {
    @Bindable var model: ICloudModel
    @State private var confirm = false
    private let module = Module.iCloud

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            ModuleHeader(module: module) {
                if model.phase == .results {
                    Button {
                        model.scan()
                    } label: {
                        Label(L("Pindai Ulang", "Scan Again"), systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(SoftButtonStyle())
                }
            }

            if model.phase != .scanning {
                HStack(spacing: 10) {
                    Label(L("Ukuran minimal", "Minimum size"), systemImage: "ruler")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    Picker(L("Ukuran minimal", "Minimum size"), selection: $model.threshold) {
                        ForEach(CloudSizeThreshold.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 240)
                    Spacer()
                }
            }

            switch model.phase {
            case .idle:
                EmptyStateView(
                    symbol: module.symbol, colors: module.colors,
                    title: model.hasICloudDrive ? L("Kosongkan ruang tanpa menghapus", "Free space without deleting") : L("iCloud Drive tidak aktif", "iCloud Drive isn't on"),
                    message: model.hasICloudDrive
                        ? L("Mencari file iCloud Drive besar yang sudah diunduh ke Mac ini dan sudah tersimpan di iCloud. Melepas salinannya mengosongkan ruang; file tetap terlihat di Finder dan diunduh lagi saat dibuka.",
                            "Looks for big iCloud Drive files that are downloaded to this Mac and already stored in iCloud. Removing their copy frees the space; the files stay visible in Finder and download again when opened.")
                        : L("Nyalakan iCloud Drive di System Settings › Apple Account › iCloud untuk memakai fitur ini.",
                            "Turn on iCloud Drive in System Settings › Apple Account › iCloud to use this.")
                ) {
                    if model.hasICloudDrive {
                        Button {
                            model.scan()
                        } label: {
                            Label(L("Mulai Pindai", "Start Scan"), systemImage: "magnifyingglass")
                        }
                        .buttonStyle(GradientButtonStyle(colors: module.colors))
                    }
                }
            case .scanning:
                VStack(spacing: 24) {
                    Spacer()
                    ScanOrb(colors: module.colors, isActive: true, label: L("Mencari…", "Searching…"), symbol: module.symbol) {}
                    Text(L("\(model.visitedCount.formatted()) item diperiksa", "\(model.visitedCount.formatted()) items checked"))
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .contentTransition(.numericText())
                    Button(L("Batal", "Cancel")) { model.cancel() }
                        .buttonStyle(SoftButtonStyle())
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            case .results:
                results
            }
        }
        .toast($model.toast)
        .alert(L("Lepas \(model.selected.count) salinan lokal?", "Remove \(model.selected.count) local copies?"), isPresented: $confirm) {
            Button(L("Lepas Salinan", "Remove Copies")) { Task { await model.evictSelected() } }
            Button(L("Batal", "Cancel"), role: .cancel) {}
        } message: {
            Text(L("\(model.selectedSize.formattedBytes) dikosongkan di Mac ini. File tidak dihapus: tetap ada di iCloud dan di perangkat lain, dan diunduh lagi saat kamu membukanya (butuh internet).",
                   "\(model.selectedSize.formattedBytes) is freed on this Mac. Nothing is deleted: the files stay in iCloud and on your other devices, and download again when you open them (an internet connection is needed)."))
        }
    }

    @ViewBuilder
    private var results: some View {
        if model.files.isEmpty {
            EmptyStateView(
                symbol: "checkmark.seal.fill", colors: module.colors,
                title: L("Tidak ada salinan besar", "No big local copies"),
                message: L("Tidak ada file iCloud Drive di atas \(model.threshold.label) yang tersimpan di Mac ini.",
                           "No iCloud Drive files over \(model.threshold.label) are stored on this Mac.")
            ) {
                Button(L("Pindai Ulang", "Scan Again")) { model.scan() }
                    .buttonStyle(GradientButtonStyle(colors: module.colors))
            }
        } else {
            VStack(spacing: 16) {
                ScrollView {
                    VStack(spacing: 2) {
                        HStack {
                            Text(L("\(model.files.count) file · \(model.totalSize.formattedBytes) di Mac ini", "\(model.files.count) files · \(model.totalSize.formattedBytes) on this Mac"))
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button(model.selected.count == model.files.count ? L("Batal pilih semua", "Deselect all") : L("Pilih semua", "Select all")) {
                                model.toggleAll()
                            }
                            .buttonStyle(.borderless)
                        }
                        .padding(.horizontal, 10)
                        .padding(.bottom, 6)
                        ForEach(model.files) { file in
                            FileRow(url: file.url, size: file.size, lastUsed: file.lastUsed, colors: module.colors,
                                    isSelected: model.selected.contains(file.url)) { model.toggle(file) }
                        }
                    }
                    .softCard(padding: 12)
                    .padding(4)
                }
                .scrollIndicators(.never)

                ActionBar(
                    caption: L("\(model.selected.count) dipilih · file tetap di iCloud", "\(model.selected.count) selected · files stay in iCloud"),
                    value: model.selectedSize.formattedBytes,
                    buttonTitle: L("Lepas Salinan Lokal", "Remove Local Copies"),
                    buttonSymbol: "icloud.and.arrow.up",
                    colors: module.colors,
                    isDisabled: model.selected.isEmpty || model.isEvicting
                ) {
                    confirm = true
                }
            }
        }
    }
}

/// A file with a checkbox, its folder, last use and size, shared by screens that list single files.
struct FileRow: View {
    let url: URL
    let size: Int64
    var lastUsed: Date?
    var detail: String?
    let colors: [Color]
    let isSelected: Bool
    let toggle: () -> Void
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 12) {
            CheckCircle(isOn: isSelected, colors: colors)
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(url.lastPathComponent)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(detail ?? url.deletingLastPathComponent().abbreviatedPath)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            Spacer(minLength: 12)
            if let lastUsed {
                Text(lastUsed, format: .relative(presentation: .named))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(width: 110, alignment: .trailing)
            }
            Text(size.formattedBytes)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .frame(width: 76, alignment: .trailing)
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } label: {
                Image(systemName: "arrow.up.forward.square")
            }
            .buttonStyle(.borderless)
            .help(L("Tampilkan di Finder", "Show in Finder"))
            .opacity(isHovering ? 1 : 0.25)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? colors[0].opacity(0.14) : (isHovering ? Color.primary.opacity(0.04) : .clear))
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: toggle)
        .onHover { isHovering = $0 }
    }
}
