import SwiftUI

struct DuplicatesView: View {
    @Bindable var model: DuplicatesModel
    @State private var confirmTrash = false
    private let module = Module.duplicates

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            ModuleHeader(module: module) {
                HStack(spacing: 10) {
                    Text(L("Minimal", "Minimum"))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Picker(L("Minimal", "Minimum"), selection: $model.minSize) {
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
                            Label(L("Pindai Ulang", "Scan Again"), systemImage: "arrow.clockwise")
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
                    title: L("Cari file kembar", "Find identical files"),
                    message: L("File dibandingkan berdasarkan isinya, bukan namanya, jadi hanya salinan yang benar-benar identik yang ditampilkan. File iCloud yang belum diunduh dilewati.",
                               "Files are compared by content, not by name, so only true copies are shown. iCloud files that aren't downloaded are skipped.")
                ) {
                    Button {
                        model.scan()
                    } label: {
                        Label(L("Mulai Pindai", "Start Scan"), systemImage: "magnifyingglass")
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
        .alert(L("Pindahkan \(model.selected.count) salinan ke Trash?", "Move \(model.selected.count) \(model.selected.count == 1 ? "copy" : "copies") to the Trash?"), isPresented: $confirmTrash) {
            Button(L("Pindahkan ke Trash", "Move to Trash"), role: .destructive) {
                Task { await model.moveSelectedToTrash() }
            }
            Button(L("Batal", "Cancel"), role: .cancel) {}
        } message: {
            Text(L("Hemat \(model.selectedSize.formattedBytes). Satu salinan di setiap grup tetap disimpan.", "Saves \(model.selectedSize.formattedBytes). One copy in every group is always kept."))
        }
    }

    private var scanningView: some View {
        VStack(spacing: 24) {
            Spacer()
            ScanOrb(colors: module.colors, isActive: true, label: L("Mencari…", "Searching…"), symbol: "doc.on.doc") {}
            VStack(spacing: 10) {
                switch model.progress {
                case .comparing(let fraction):
                    Text(L("Membandingkan isi file… \(Int(fraction * 100))%", "Comparing file contents… \(Int(fraction * 100))%"))
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                    ProgressView(value: fraction)
                        .tint(module.colors.last)
                        .frame(width: 280)
                case .collecting(let count):
                    Text(L("\(count.formatted()) file diperiksa", "\(count.formatted()) files checked"))
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .contentTransition(.numericText())
                case nil:
                    Text(L("Menyiapkan…", "Getting ready…"))
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                }
                Text(L("File dengan ukuran sama dibandingkan isinya satu per satu.", "Files of the same size are compared one by one."))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Button(L("Batal", "Cancel")) { model.cancel() }
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
                title: L("Tidak ada file kembar", "No identical files"),
                message: L("Tidak ditemukan salinan identik di atas \(model.minSize.label). Coba turunkan batas ukurannya.", "No identical copies over \(model.minSize.label). Try a lower size limit.")
            ) {
                Button(L("Pindai Ulang", "Scan Again")) { model.scan() }
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
                    caption: L("\(model.groups.count) grup · total bisa dihemat \(model.totalWasted.formattedBytes)", "\(model.groups.count) groups · \(model.totalWasted.formattedBytes) can be saved"),
                    value: model.selectedSize.formattedBytes,
                    buttonTitle: L("Pindahkan ke Trash", "Move to Trash"),
                    buttonSymbol: "trash",
                    colors: module.colors,
                    isDisabled: model.selected.isEmpty,
                    action: { confirmTrash = true }
                ) {
                    Button {
                        model.autoSelect()
                    } label: {
                        Label(L("Pilih Otomatis", "Auto Select"), systemImage: "wand.and.stars")
                    }
                    .buttonStyle(SoftButtonStyle())
                    .help(L("Simpan salinan tertua di setiap grup, pilih sisanya", "Keep the oldest copy in every group and select the rest"))
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
                Image(nsImage: FileIcon.image(for: group.files[0].url, size: 34))
                    .resizable()
                    .frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.files[0].name)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(L("\(group.files.count) salinan · \(group.size.formattedBytes) per file", "\(group.files.count) copies · \(group.size.formattedBytes) each"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(L("Hemat \(group.wasted.formattedBytes)", "Saves \(group.wasted.formattedBytes)"))
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
                Text(L("Disimpan", "Kept"))
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
            .help(L("Tampilkan di Finder", "Show in Finder"))
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
