import SwiftUI

struct DeveloperView: View {
    @Bindable var model: DeveloperModel
    @State private var confirmTrash = false
    private let module = Module.developer

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
                    Label(L("Anggap tidak dipakai setelah", "Treat as unused after"), systemImage: "clock.arrow.circlepath")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    Picker(L("Tidak dipakai", "Unused for"), selection: $model.staleAge) {
                        ForEach(StaleAge.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 230)
                    Spacer()
                }
            }

            switch model.phase {
            case .idle:
                EmptyStateView(
                    symbol: module.symbol,
                    colors: module.colors,
                    title: L("Bersihkan sisa coding", "Clean up coding leftovers"),
                    message: L("Mencari dependensi proyek, cache package manager, dan arsip Xcode. Untuk cache, hanya library yang tidak dipakai lebih dari \(model.staleAge.rawValue) hari yang dibersihkan, jadi proyek aktif tetap cepat di-build.",
                               "Looks for project dependencies, package manager caches and Xcode archives. For caches, only libraries unused for \(model.staleAge.rawValue)+ days are cleaned, so active projects still build fast.")
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
        .alert(L("Pindahkan \(model.selected.count) item ke Trash?", "Move \(model.selected.count) \(model.selected.count == 1 ? "item" : "items") to the Trash?"),
               isPresented: $confirmTrash) {
            Button(L("Pindahkan ke Trash", "Move to Trash"), role: .destructive) {
                Task { await model.moveSelectedToTrash() }
            }
            Button(L("Batal", "Cancel"), role: .cancel) {}
        } message: {
            Text(L("Total \(model.selectedSize.formattedBytes). Library yang masih dipakai tidak disentuh. Tutup dulu editor atau dev server dari proyek terkait. Yang terhapus akan diunduh ulang otomatis kalau ternyata dibutuhkan.",
                   "Total \(model.selectedSize.formattedBytes). Libraries still in use are left alone. Close any editor or dev server using these projects first. Anything removed is downloaded again if it turns out to be needed."))
        }
    }

    private var scanningView: some View {
        VStack(spacing: 24) {
            Spacer()
            ScanOrb(colors: module.colors, isActive: true, label: L("Mencari…", "Searching…"), symbol: module.symbol) {}
            VStack(spacing: 6) {
                Text(L("\(model.visitedCount.formatted()) item diperiksa", "\(model.visitedCount.formatted()) items checked"))
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
                    .animation(.snappy, value: model.visitedCount)
                Text(L("Hanya folder dengan file proyeknya (package.json, Podfile, …) yang dihitung.",
                       "Only folders next to their project file (package.json, Podfile, …) count."))
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
        if model.categories.isEmpty && model.result.commands.isEmpty {
            EmptyStateView(
                symbol: "checkmark.seal.fill",
                colors: module.colors,
                title: L("Tidak ada sisa coding", "No coding leftovers"),
                message: L("Tidak ditemukan dependensi proyek, cache package manager, atau arsip Xcode.",
                           "No project dependencies, package manager caches or Xcode archives were found.")
            ) {
                Button(L("Pindai Ulang", "Scan Again")) { model.scan() }
                    .buttonStyle(GradientButtonStyle(colors: module.colors))
            }
        } else {
            VStack(spacing: 16) {
                ScrollView {
                    VStack(spacing: 16) {
                        ForEach(model.categories) { category in
                            DevSection(model: model, category: category)
                        }
                        if !model.result.commands.isEmpty {
                            CommandsCard(model: model)
                        }
                    }
                    .padding(4)
                }
                .scrollIndicators(.never)

                ActionBar(
                    caption: L("\(model.selected.count) item dipilih · bisa dibersihkan \(model.totalRemovable.formattedBytes)",
                               "\(model.selected.count) selected · \(model.totalRemovable.formattedBytes) can be cleaned"),
                    value: model.selectedSize.formattedBytes,
                    buttonTitle: L("Pindahkan ke Trash", "Move to Trash"),
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

private struct DevSection: View {
    @Bindable var model: DeveloperModel
    let category: DevCategory

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                GradientIcon(symbol: category.symbol, colors: category.colors, size: 42)
                VStack(alignment: .leading, spacing: 3) {
                    Text(category.title)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                    Text(category.subtitle(days: model.staleAge.rawValue))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                Text(model.size(of: category).formattedBytes)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                Button {
                    model.toggle(category)
                } label: {
                    CheckCircle(state: model.selectionState(of: category), colors: category.colors)
                }
                .buttonStyle(.plain)
                .help(L("Pilih semua", "Select all"))
            }
            VStack(spacing: 2) {
                ForEach(model.items(in: category)) { item in
                    DevItemRow(model: model, item: item, colors: category.colors)
                }
            }
        }
        .softCard()
    }
}

private struct DevItemRow: View {
    let model: DeveloperModel
    let item: DevItem
    let colors: [Color]
    @State private var isHovering = false

    private var isSelected: Bool { model.selected.contains(item.url) }
    private var lockedBy: String? { model.lockedBy[item.url] }
    private var removable: Int64 { model.removableSize(item) }

    var body: some View {
        HStack(spacing: 12) {
            leading
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(item.title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Text(item.tool)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.primary.opacity(0.06)))
                        .lineLimit(1)
                }
                caption
            }
            Spacer(minLength: 12)
            if !item.isSmart {
                Group {
                    if let lastUsed = item.lastUsed {
                        Text(lastUsed, format: .relative(presentation: .named))
                    } else {
                        Text("—")
                    }
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .trailing)
                .help(L("Terakhir dipakai", "Last used"))
            }
            Text(removable.formattedBytes)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(removable > 0 ? .primary : .secondary)
                .frame(width: 76, alignment: .trailing)
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
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
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? colors[0].opacity(0.14) : (isHovering ? Color.primary.opacity(0.04) : .clear))
        )
        .opacity(model.isSelectable(item) || isSelected ? 1 : 0.6)
        .contentShape(Rectangle())
        .onTapGesture { model.toggle(item) }
        .onHover { isHovering = $0 }
    }

    @ViewBuilder
    private var leading: some View {
        if lockedBy != nil {
            Image(systemName: "lock.circle.fill")
                .font(.system(size: 19))
                .foregroundStyle(Palette.sunny[1])
                .frame(width: 20, height: 20)
        } else if removable == 0 {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 17))
                .foregroundStyle(LinearGradient.soft(Palette.leaf))
                .frame(width: 20, height: 20)
                .help(L("Semua masih dipakai", "Everything is still in use"))
        } else {
            CheckCircle(isOn: isSelected, colors: colors)
        }
    }

    @ViewBuilder
    private var caption: some View {
        if let lockedBy {
            Text(L("\(lockedBy) sedang terbuka · tutup dulu untuk membersihkan", "\(lockedBy) is open · quit it to clean this"))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Palette.sunny[1])
        } else if let note = item.note {
            Text(note)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Palette.sunny[1])
                .fixedSize(horizontal: false, vertical: true)
        } else if item.isSmart {
            Text(smartCaption)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        } else {
            Text(item.url.abbreviatedPath)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.head)
        }
    }

    private var smartCaption: String {
        let stale = model.staleCount(item)
        let kept = model.keptSize(item).formattedBytes
        if stale == 0 {
            return L("Semua masih dipakai · \(kept) disimpan", "All still in use · \(kept) kept")
        }
        if model.keptSize(item) == 0 {
            return L("\(stale.formatted()) entri, semuanya sudah lama tidak dipakai", "\(stale.formatted()) entries, none used recently")
        }
        return L("\(stale.formatted()) entri tidak dipakai · \(kept) masih dipakai, tetap disimpan",
                 "\(stale.formatted()) unused entries · \(kept) still in use, kept")
    }
}

private struct CommandsCard: View {
    @Bindable var model: DeveloperModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                GradientIcon(symbol: "terminal.fill", colors: Palette.slate, size: 42)
                VStack(alignment: .leading, spacing: 3) {
                    Text(L("Pembersihan lewat Terminal", "Clean up in Terminal"))
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                    Text(L("Bagian ini hanya aman dibersihkan oleh alatnya sendiri, dan hasilnya tidak masuk Trash. Salin perintahnya, lalu jalankan di Terminal kalau kamu yakin.",
                           "Only the tool itself can clean these safely, and the result does not go to the Trash. Copy the command and run it in Terminal if you are sure."))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            VStack(spacing: 8) {
                ForEach(model.result.commands) { command in
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text(command.title)
                                    .font(.system(size: 13, weight: .semibold))
                                if let size = command.size {
                                    Text(size.formattedBytes)
                                        .font(.system(size: 11, weight: .bold, design: .rounded))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Text(command.detail)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(command.command)
                                .font(.system(size: 11, design: .monospaced))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(0.06)))
                                .textSelection(.enabled)
                        }
                        Spacer(minLength: 12)
                        Button {
                            model.copy(command)
                        } label: {
                            Label(L("Salin", "Copy"), systemImage: "doc.on.doc")
                        }
                        .buttonStyle(SoftButtonStyle())
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.03)))
                }
            }
        }
        .softCard()
    }
}
