import SwiftUI

struct DuplicatesView: View {
    @Bindable var model: DuplicatesModel
    @State private var confirmTrash = false
    private let module = Module.duplicates

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            ModuleHeader(module: module) {
                HStack(spacing: 10) {
                    Text("Minimal")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Picker("Minimal", selection: $model.minSize) {
                        ForEach(DuplicatesModel.MinSize.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 210)
                    .disabled(model.phase == .scanning)
                    if model.phase == .results {
                        Button {
                            model.scan()
                        } label: {
                            Label("Pindai Ulang", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(SoftButtonStyle())
                        .fixedSize()
                    }
                }
            }

            switch model.phase {
            case .idle:
                EmptyStateView(
                    symbol: module.symbol,
                    colors: module.colors,
                    title: "Cari file kembar",
                    message: "File dibandingkan berdasarkan isinya, bukan namanya, jadi hanya salinan yang benar-benar identik yang ditampilkan. File iCloud yang belum diunduh dilewati."
                ) {
                    Button {
                        model.scan()
                    } label: {
                        Label("Mulai Pindai", systemImage: "magnifyingglass")
                    }
                    .buttonStyle(GradientButtonStyle(colors: module.colors))
                }
            case .scanning:
                scanningView
            case .results:
                resultsView
            }
        }
        .toast($model.toast)
        .alert("Pindahkan \(model.selected.count) salinan ke Trash?", isPresented: $confirmTrash) {
            Button("Pindahkan ke Trash", role: .destructive) {
                Task { await model.moveSelectedToTrash() }
            }
            Button("Batal", role: .cancel) {}
        } message: {
            Text("Hemat \(model.selectedSize.formattedBytes). Satu salinan di setiap grup tetap disimpan.")
        }
    }

    private var scanningView: some View {
        VStack(spacing: 24) {
            Spacer()
            ScanOrb(colors: module.colors, isActive: true, label: "Mencari…", symbol: "doc.on.doc") {}
            VStack(spacing: 10) {
                switch model.progress {
                case .comparing(let fraction):
                    Text("Membandingkan isi file… \(Int(fraction * 100))%")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                    ProgressView(value: fraction)
                        .tint(module.colors.last)
                        .frame(width: 280)
                case .collecting(let count):
                    Text("\(count.formatted()) file diperiksa")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .contentTransition(.numericText())
                case nil:
                    Text("Menyiapkan…")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                }
                Text("File dengan ukuran sama dibandingkan isinya satu per satu.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Button("Batal") { model.cancel() }
                .buttonStyle(SoftButtonStyle())
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var resultsView: some View {
        if model.groups.isEmpty {
            EmptyStateView(
                symbol: "checkmark.seal.fill",
                colors: module.colors,
                title: "Tidak ada file kembar",
                message: "Tidak ditemukan salinan identik di atas \(model.minSize.label). Coba turunkan batas ukurannya."
            ) {
                Button("Pindai Ulang") { model.scan() }
                    .buttonStyle(GradientButtonStyle(colors: module.colors))
            }
        } else {
            VStack(spacing: 16) {
                ScrollView {
                    LazyVStack(spacing: 14) {
                        ForEach(model.groups) { group in
                            DuplicateGroupCard(model: model, group: group)
                        }
                    }
                    .padding(4)
                }
                .scrollIndicators(.never)

                ActionBar(
                    caption: "\(model.groups.count) grup · total bisa dihemat \(model.totalWasted.formattedBytes)",
                    value: model.selectedSize.formattedBytes,
                    buttonTitle: "Pindahkan ke Trash",
                    buttonSymbol: "trash",
                    colors: module.colors,
                    isDisabled: model.selected.isEmpty,
                    action: { confirmTrash = true }
                ) {
                    Button {
                        model.autoSelect()
                    } label: {
                        Label("Pilih Otomatis", systemImage: "wand.and.stars")
                    }
                    .buttonStyle(SoftButtonStyle())
                    .help("Simpan salinan tertua di setiap grup, pilih sisanya")
                }
            }
        }
    }
}

private struct DuplicateGroupCard: View {
    @Bindable var model: DuplicatesModel
    let group: DuplicateGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: group.files[0].url.path))
                    .resizable()
                    .frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.files[0].name)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text("\(group.files.count) salinan · \(group.size.formattedBytes) per file")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("Hemat \(group.wasted.formattedBytes)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(LinearGradient(colors: Module.duplicates.colors, startPoint: .leading, endPoint: .trailing)))
            }

            VStack(spacing: 2) {
                ForEach(group.files) { file in
                    DuplicateRow(file: file, isSelected: model.selected.contains(file.url)) {
                        model.toggle(file, in: group)
                    }
                }
            }
        }
        .softCard(padding: 16)
    }
}

private struct DuplicateRow: View {
    let file: DuplicateFile
    let isSelected: Bool
    let onToggle: () -> Void
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 12) {
            CheckCircle(isOn: isSelected, colors: Module.duplicates.colors)
            Text(file.url.deletingLastPathComponent().abbreviatedPath)
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.head)
            Spacer(minLength: 12)
            if !isSelected {
                Text("Disimpan")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(hex: 0x0F9F7A))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color(hex: 0x5EE0C1, opacity: 0.2)))
            }
            if let modified = file.modified {
                Text(modified, format: .dateTime.day().month(.abbreviated).year())
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(width: 96, alignment: .trailing)
            }
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([file.url])
            } label: {
                Image(systemName: "arrow.up.forward.square")
            }
            .buttonStyle(.borderless)
            .help("Tampilkan di Finder")
            .opacity(isHovering ? 1 : 0.25)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? Module.duplicates.colors[0].opacity(0.18) : (isHovering ? Color.primary.opacity(0.04) : .clear))
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onToggle)
        .onHover { isHovering = $0 }
    }
}
