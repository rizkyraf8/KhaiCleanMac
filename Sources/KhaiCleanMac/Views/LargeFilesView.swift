import SwiftUI

struct LargeFilesView: View {
    @Bindable var model: LargeFilesModel
    @State private var confirmTrash = false
    private let module = Module.largeFiles

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            ModuleHeader(module: module) {
                HStack(spacing: 10) {
                    Text("Minimal")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Picker("Minimal", selection: $model.threshold) {
                        ForEach(SizeThreshold.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 250)
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
                    title: "Cari file yang makan tempat",
                    message: "Kami akan memeriksa folder pribadimu (Desktop, Documents, Downloads, dan lainnya) untuk file di atas \(model.threshold.label). macOS mungkin meminta izin akses folder."
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
        .alert("Pindahkan \(model.selected.count) file ke Trash?", isPresented: $confirmTrash) {
            Button("Pindahkan ke Trash", role: .destructive) {
                Task { await model.moveSelectedToTrash() }
            }
            Button("Batal", role: .cancel) {}
        } message: {
            Text("Total \(model.selectedSize.formattedBytes). File masih bisa dikembalikan dari Trash.")
        }
    }

    private var scanningView: some View {
        VStack(spacing: 24) {
            Spacer()
            ScanOrb(colors: module.colors, isActive: true, label: "Mencari…", symbol: "magnifyingglass") {}
            VStack(spacing: 6) {
                Text("\(model.visitedCount.formatted()) file diperiksa")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
                    .animation(.snappy, value: model.visitedCount)
                Text("Folder Library dan isi paket aplikasi dilewati.")
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
        if model.files.isEmpty {
            EmptyStateView(
                symbol: "checkmark.seal.fill",
                colors: module.colors,
                title: "Tidak ada file di atas \(model.threshold.label)",
                message: "Coba turunkan batas ukuran untuk melihat lebih banyak file."
            ) {
                Button("Pindai Ulang") { model.scan() }
                    .buttonStyle(GradientButtonStyle(colors: module.colors))
            }
        } else {
            VStack(spacing: 16) {
                HStack(spacing: 8) {
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            Chip(title: "Semua", count: model.files.count, colors: module.colors, isSelected: model.filter == nil) {
                                model.filter = nil
                            }
                            ForEach(model.presentKinds) { kind in
                                Chip(title: kind.title, count: model.count(of: kind), colors: kind.colors, isSelected: model.filter == kind) {
                                    model.filter = kind
                                }
                            }
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 2)
                    }
                    .scrollIndicators(.never)

                    Picker("Urutkan", selection: $model.sort) {
                        ForEach(LargeFilesModel.Sort.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.menu)
                    .fixedSize()
                }

                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(model.visibleFiles) { file in
                            LargeFileRow(file: file, isSelected: model.selected.contains(file.url)) {
                                model.toggle(file)
                            }
                        }
                    }
                    .padding(6)
                }
                .softCard(padding: 4)

                ActionBar(
                    caption: "\(model.selected.count) dari \(model.files.count) file dipilih · total \(model.totalSize.formattedBytes)",
                    value: model.selectedSize.formattedBytes,
                    buttonTitle: "Pindahkan ke Trash",
                    buttonSymbol: "trash",
                    colors: module.colors,
                    isDisabled: model.selected.isEmpty
                ) {
                    confirmTrash = true
                }
            }
        }
    }
}

private struct LargeFileRow: View {
    let file: LargeFile
    let isSelected: Bool
    let onToggle: () -> Void
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 14) {
            CheckCircle(isOn: isSelected, colors: Module.largeFiles.colors)
            GradientIcon(symbol: file.kind.symbol, colors: file.kind.colors, size: 36, corner: 11)
            VStack(alignment: .leading, spacing: 2) {
                Text(file.name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(file.url.deletingLastPathComponent().abbreviatedPath)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            Spacer(minLength: 12)
            Group {
                if let date = file.lastUsed {
                    Text(date, format: .relative(presentation: .named))
                } else {
                    Text("—")
                }
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .frame(width: 120, alignment: .trailing)
            Text(file.size.formattedBytes)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .frame(width: 80, alignment: .trailing)
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([file.url])
            } label: {
                Image(systemName: "arrow.up.forward.square")
            }
            .buttonStyle(.borderless)
            .help("Tampilkan di Finder")
            .opacity(isHovering ? 1 : 0.25)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isSelected ? Module.largeFiles.colors[0].opacity(0.14) : (isHovering ? Color.primary.opacity(0.04) : .clear))
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onToggle)
        .onHover { isHovering = $0 }
    }
}
