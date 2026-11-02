import SwiftUI

struct SimilarPhotosView: View {
    @Bindable var model: SimilarPhotosModel
    @State private var confirm = false
    private let module = Module.similarPhotos

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

            switch model.phase {
            case .idle:
                EmptyStateView(
                    symbol: module.symbol, colors: module.colors,
                    title: L("Cari foto yang mirip", "Find look-alike photos"),
                    message: L("Memeriksa Pictures, Desktop, Downloads, dan Documents. Foto di Photos Library tidak disentuh; untuk itu pakai fitur Duplikat di app Photos. Tidak ada foto yang dipilih otomatis.",
                               "Checks Pictures, Desktop, Downloads and Documents. Photos in your Photos Library aren't touched; use Duplicates in the Photos app for those. No photo is preselected.")
                ) {
                    Button {
                        model.scan()
                    } label: {
                        Label(L("Mulai Pindai", "Start Scan"), systemImage: "magnifyingglass")
                    }
                    .buttonStyle(GradientButtonStyle(colors: module.colors))
                }
            case .scanning:
                VStack(spacing: 24) {
                    Spacer()
                    ScanOrb(colors: module.colors, isActive: true, label: L("Mencari…", "Searching…"), symbol: module.symbol) {}
                    Text(progressText)
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
        .alert(Removal.question(L("\(model.selected.count) foto", "\(model.selected.count) photos")), isPresented: $confirm) {
            Button(Removal.actionTitle, role: .destructive) { Task { await model.moveSelectedToTrash() } }
            Button(L("Batal", "Cancel"), role: .cancel) {}
        } message: {
            Text(L("Total \(model.selectedSize.formattedBytes). Foto yang mirip belum tentu sama persis, jadi periksa dulu pilihanmu. ", "Total \(model.selectedSize.formattedBytes). Similar photos aren't always identical, so check your picks first. ") + Removal.undoNote)
        }
    }

    private var progressText: String {
        switch model.progress {
        case .collecting(let count): L("\(count.formatted()) item diperiksa", "\(count.formatted()) items checked")
        case .hashing(let fraction): L("Membandingkan foto… \(Int(fraction * 100))%", "Comparing photos… \(Int(fraction * 100))%")
        case nil: L("Menyiapkan…", "Getting ready…")
        }
    }

    @ViewBuilder
    private var results: some View {
        if model.groups.isEmpty {
            EmptyStateView(
                symbol: "checkmark.seal.fill", colors: module.colors,
                title: L("Tidak ada foto mirip", "No similar photos"),
                message: L("Tidak ditemukan foto yang terlihat hampir sama.", "No photos that look nearly the same were found.")
            ) {
                Button(L("Pindai Ulang", "Scan Again")) { model.scan() }
                    .buttonStyle(GradientButtonStyle(colors: module.colors))
            }
        } else {
            VStack(spacing: 16) {
                HStack {
                    Text(L("\(model.groups.count) grup · hingga \(model.totalReclaimable.formattedBytes) bisa dikosongkan", "\(model.groups.count) groups · up to \(model.totalReclaimable.formattedBytes) can be freed"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(L("Pilih semua kecuali yang terbaik", "Select all but the best")) { model.selectAllButBest() }
                        .buttonStyle(SoftButtonStyle())
                        .help(L("Yang terbaik: resolusi paling tinggi, lalu file paling besar", "The best: the highest resolution, then the biggest file"))
                    Button(L("Batal pilih", "Deselect")) { model.selected = [] }
                        .buttonStyle(SoftButtonStyle())
                        .disabled(model.selected.isEmpty)
                }
                ScrollView {
                    LazyVStack(spacing: 14) {
                        ForEach(model.groups) { group in
                            SimilarGroupCard(model: model, group: group)
                        }
                    }
                    .padding(4)
                }
                .scrollIndicators(.never)

                ActionBar(
                    caption: L("\(model.selected.count) foto dipilih", "\(model.selected.count) photos selected"),
                    value: model.selectedSize.formattedBytes,
                    buttonTitle: Removal.actionTitle,
                    buttonSymbol: Removal.actionSymbol,
                    colors: module.colors,
                    isDisabled: model.selected.isEmpty || model.isCleaning
                ) {
                    confirm = true
                }
            }
        }
    }
}

private struct SimilarGroupCard: View {
    let model: SimilarPhotosModel
    let group: SimilarGroup

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 12) {
                ForEach(Array(group.photos.enumerated()), id: \.element.id) { index, photo in
                    PhotoTile(photo: photo, isBest: index == 0, isSelected: model.selected.contains(photo.url)) {
                        model.toggle(photo, in: group)
                    }
                }
            }
            .padding(2)
        }
        .scrollIndicators(.never)
        .softCard(padding: 12)
    }
}

private struct PhotoTile: View {
    let photo: SimilarPhoto
    let isBest: Bool
    let isSelected: Bool
    let toggle: () -> Void
    @State private var image: NSImage?
    @State private var isHovering = false
    private let colors = Module.similarPhotos.colors

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topLeading) {
                Group {
                    if let image {
                        Image(nsImage: image).resizable().scaledToFill()
                    } else {
                        Color.primary.opacity(0.06)
                    }
                }
                .frame(width: 150, height: 112)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(isSelected ? colors[1] : .clear, lineWidth: 3)
                )
                CheckCircle(isOn: isSelected, colors: colors)
                    .padding(6)
                if isBest {
                    Text(L("Terbaik", "Best"))
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(LinearGradient.soft(Palette.leaf)))
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .topTrailing)
                }
            }
            .frame(width: 150, height: 112)
            Text(photo.name)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.middle)
            Text("\(photo.pixelWidth) × \(photo.pixelHeight) · \(photo.size.formattedBytes)")
                .font(.system(size: 10, design: .rounded))
                .foregroundStyle(.secondary)
            Text(photo.url.deletingLastPathComponent().abbreviatedPath)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.head)
        }
        .frame(width: 150)
        .contentShape(Rectangle())
        .onTapGesture(perform: toggle)
        .onHover { isHovering = $0 }
        .contextMenu {
            Button(L("Tampilkan di Finder", "Show in Finder")) { NSWorkspace.shared.activateFileViewerSelecting([photo.url]) }
            Button(L("Buka", "Open")) { NSWorkspace.shared.open(photo.url) }
        }
        .task(id: photo.url) {
            let url = photo.url
            image = await Task.detached(priority: .utility) { SimilarPhotoScanner.thumbnail(url) }.value
        }
    }
}

struct SecurityScanView: View {
    @Bindable var model: SecurityScanModel
    @State private var confirm = false
    private let module = Module.security

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

            switch model.phase {
            case .idle:
                EmptyStateView(
                    symbol: module.symbol, colors: module.colors,
                    title: L("Cari file sensitif yang tercecer", "Find sensitive files lying around"),
                    message: L("Memeriksa Desktop, Documents, dan Downloads, serta izin kunci di ~/.ssh. Hanya awal file yang namanya mirip file rahasia yang dibaca, dan tidak ada yang dikirim ke mana pun. Tidak ada yang dipilih otomatis.",
                               "Checks Desktop, Documents and Downloads, and the permissions of keys in ~/.ssh. Only the start of files named like secrets is read, and nothing is sent anywhere. Nothing is preselected.")
                ) {
                    Button {
                        model.scan()
                    } label: {
                        Label(L("Mulai Pindai", "Start Scan"), systemImage: "magnifyingglass")
                    }
                    .buttonStyle(GradientButtonStyle(colors: module.colors))
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
        .alert(Removal.question(L("\(model.selected.count) file", "\(model.selected.count) files")), isPresented: $confirm) {
            Button(Removal.actionTitle, role: .destructive) { Task { await model.moveSelectedToTrash() } }
            Button(L("Batal", "Cancel"), role: .cancel) {}
        } message: {
            Text(Removal.isPermanent
                 ? L("File langsung dihapus permanen. Kalau kunci atau kata sandi di dalamnya pernah dibagikan, ganti juga di layanannya.",
                     "The files are deleted for good right away. If a key or password in them was ever shared, change it at its service too.")
                 : L("File masuk Trash dan masih bisa dibaca dari sana: kosongkan Trash setelah ini. Kalau kunci atau kata sandi di dalamnya pernah dibagikan, ganti juga di layanannya.",
                     "The files go to the Trash and can still be read there: empty the Trash afterwards. If a key or password in them was ever shared, change it at its service too."))
        }
    }

    @ViewBuilder
    private var results: some View {
        if model.findings.isEmpty {
            EmptyStateView(
                symbol: "checkmark.shield.fill", colors: Palette.leaf,
                title: L("Tidak ada yang mencurigakan", "Nothing stood out"),
                message: L("Tidak ditemukan kunci, ekspor kata sandi, atau kredensial yang tercecer di Desktop, Documents, atau Downloads.",
                           "No stray keys, exported passwords or credentials were found in Desktop, Documents or Downloads.")
            ) {
                Button(L("Pindai Ulang", "Scan Again")) { model.scan() }
                    .buttonStyle(GradientButtonStyle(colors: module.colors))
            }
        } else {
            VStack(spacing: 16) {
                ScrollView {
                    VStack(spacing: 16) {
                        ForEach(model.kinds, id: \.self) { kind in
                            SecuritySection(model: model, kind: kind)
                        }
                    }
                    .padding(4)
                }
                .scrollIndicators(.never)

                ActionBar(
                    caption: L("\(model.selected.count) file dipilih", "\(model.selected.count) files selected"),
                    value: model.selectedSize.formattedBytes,
                    buttonTitle: Removal.actionTitle,
                    buttonSymbol: Removal.actionSymbol,
                    colors: module.colors,
                    isDisabled: model.selected.isEmpty || model.isCleaning
                ) {
                    confirm = true
                }
            }
        }
    }
}

private struct SecuritySection: View {
    let model: SecurityScanModel
    let kind: SecurityFinding.Kind

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                GradientIcon(symbol: kind.symbol, colors: kind.colors, size: 42)
                VStack(alignment: .leading, spacing: 3) {
                    Text(kind.title)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                    Text(kind.subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                Text("\(model.findings(of: kind).count)")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
            }
            VStack(spacing: 2) {
                ForEach(model.findings(of: kind)) { finding in
                    if kind == .loosePermissions {
                        HStack(spacing: 12) {
                            Image(systemName: "lock.open.fill").foregroundStyle(Palette.candy[1])
                            VStack(alignment: .leading, spacing: 1) {
                                Text(finding.name).font(.system(size: 13, weight: .semibold))
                                Text(finding.detail ?? "").font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(L("Perbaiki Izin", "Fix Permissions")) { model.fixPermissions(finding) }
                                .buttonStyle(SoftButtonStyle())
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                    } else {
                        FileRow(url: finding.url, size: finding.size, lastUsed: finding.modified,
                                detail: finding.detail.map { "\($0) · \(finding.url.deletingLastPathComponent().abbreviatedPath)" },
                                colors: kind.colors, isSelected: model.selected.contains(finding.url)) {
                            model.toggle(finding)
                        }
                    }
                }
            }
        }
        .softCard()
    }
}
