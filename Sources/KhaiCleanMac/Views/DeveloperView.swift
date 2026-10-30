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
                    message: L("Mencari dependensi proyek, cache package manager, simulator, dan arsip Xcode. Untuk cache, hanya library yang tidak dipakai lebih dari \(model.staleAge.rawValue) hari yang dibersihkan, jadi proyek aktif tetap cepat di-build.",
                               "Looks for project dependencies, package manager caches, simulators and Xcode archives. For caches, only libraries unused for \(model.staleAge.rawValue)+ days are cleaned, so active projects still build fast.")
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
        .alert(Removal.question(L("\(model.selected.count) item", "\(model.selected.count) \(model.selected.count == 1 ? "item" : "items")")),
               isPresented: $confirmTrash) {
            Button(Removal.actionTitle, role: .destructive) {
                Task { await model.moveSelectedToTrash() }
            }
            Button(L("Batal", "Cancel"), role: .cancel) {}
        } message: {
            Text(L("Total \(model.selectedSize.formattedBytes). Library yang masih dipakai tidak disentuh. Tutup dulu editor atau dev server dari proyek terkait. Yang terhapus akan diunduh ulang otomatis kalau ternyata dibutuhkan.",
                   "Total \(model.selectedSize.formattedBytes). Libraries still in use are left alone. Close any editor or dev server using these projects first. Anything removed is downloaded again if it turns out to be needed.")
                 + (model.selectionHasSimulators
                    ? L("\n\nRuntime dan simulator yang dipilih dihapus permanen lewat Xcode, tidak lewat Trash. Aplikasi dan data di dalam simulator itu ikut terhapus. Runtime bisa diunduh lagi di Xcode › Settings › Components.",
                        "\n\nThe selected runtimes and simulators are deleted for good through Xcode, not moved to the Trash, along with the apps and data inside them. Runtimes can be downloaded again in Xcode › Settings › Components.")
                    : ""))
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
        if model.categories.isEmpty && model.result.commands.isEmpty && model.docker == .notInstalled {
            EmptyStateView(
                symbol: "checkmark.seal.fill",
                colors: module.colors,
                title: L("Tidak ada sisa coding", "No coding leftovers"),
                message: L("Tidak ditemukan dependensi proyek, cache package manager, simulator, atau arsip Xcode.",
                           "No project dependencies, package manager caches, simulators or Xcode archives were found.")
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
                        if model.docker != .notInstalled {
                            DockerCard(model: model)
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
                    buttonTitle: Removal.actionTitle,
                    buttonSymbol: "trash",
                    colors: module.colors,
                    isDisabled: model.selected.isEmpty || model.isCleaning
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

/// Cleans Docker through its own CLI, by age. Its data sits in a disk image only the engine reads,
/// so this is the one place in Developer where removal is permanent by nature.
struct DockerCard: View {
    @Bindable var model: DeveloperModel
    @State private var confirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                GradientIcon(symbol: "shippingbox.fill", colors: Palette.sky, size: 42)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text("Docker")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                        if case .ready(let engine) = model.docker {
                            Text(L("Lokal · \(engine.context)", "Local · \(engine.context)"))
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundStyle(Palette.mint[1])
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Palette.mint[1].opacity(0.15)))
                        }
                    }
                    Text(L("Image yang tidak dipakai container mana pun dan build cache yang dibuat lebih dari batas umur, dihapus oleh Docker sendiri. Docker tidak mencatat kapan terakhir dipakai, jadi umur dihitung dari tanggal dibuat. Volume dan container yang berjalan tidak pernah disentuh.",
                           "Images no container uses and build cache created longer ago than the age limit, removed by Docker itself. Docker doesn't record when something was last used, so age counts from creation. Volumes and running containers are never touched."))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                if model.isCleaningDocker { ProgressView().controlSize(.small) }
            }

            switch model.docker {
            case .notInstalled:
                EmptyView()
            case .notRunning:
                notice("pause.circle.fill", Palette.sunny,
                       L("Docker tidak berjalan. Buka Docker Desktop, OrbStack, atau Colima, lalu periksa lagi.",
                         "Docker isn't running. Open Docker Desktop, OrbStack or Colima, then check again."))
            case .timedOut:
                notice("hourglass", Palette.sunny,
                       L("Docker tidak merespons. Coba mulai ulang Docker, lalu periksa lagi.",
                         "Docker isn't responding. Try restarting Docker, then check again."))
            case .notLocal(let context, let host):
                notice("network.badge.shield.half.filled", Palette.berry, context.isEmpty
                       ? L("Tidak bisa memastikan Docker berjalan di Mac ini, jadi tidak ada yang dibersihkan.",
                           "Couldn't confirm that Docker runs on this Mac, so nothing is cleaned.")
                       : L("Context Docker yang aktif (\(context)) mengarah ke \(host), bukan Mac ini. KhaiCleanMac hanya membersihkan Docker lokal. Pindah ke context lokal (misalnya docker context use desktop-linux), lalu periksa lagi.",
                           "The active Docker context (\(context)) points to \(host), not this Mac. KhaiCleanMac only cleans a local Docker. Switch to a local context (for example docker context use desktop-linux), then check again."))
            case .ready(let engine):
                ready(engine)
            }
        }
        .softCard()
        .alert(L("Bersihkan Docker?", "Clean Docker?"), isPresented: $confirm) {
            Button(L("Bersihkan", "Clean"), role: .destructive) { Task { await model.cleanDocker() } }
            Button(L("Batal", "Cancel"), role: .cancel) {}
        } message: {
            Text(confirmation)
        }
    }

    @ViewBuilder
    private func ready(_ engine: DockerEngine) -> some View {
        let usage = engine.usage
        let oldContainers = engine.containers(olderThan: model.dockerAge)
        HStack(spacing: 10) {
            StatTile(title: L("Image tak terpakai", "Unused images"), value: usage.images.reclaimable.formattedBytes, colors: Palette.sky)
            StatTile(title: L("Build cache", "Build cache"), value: usage.buildCache.reclaimable.formattedBytes, colors: Palette.mint)
            StatTile(title: L("Container berhenti", "Stopped containers"), value: "\(engine.stoppedContainers.count)", colors: Palette.lavender)
        }
        HStack(spacing: 12) {
            Text(L("Dibuat lebih dari", "Created over"))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize()
            Picker(L("Dibuat lebih dari", "Created over"), selection: $model.dockerAge) {
                ForEach(DockerAge.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 220)
            .disabled(model.isCleaningDocker)
            Spacer(minLength: 8)
            Button {
                confirm = true
            } label: {
                Label(L("Bersihkan Docker", "Clean Docker"), systemImage: "shippingbox")
            }
            .buttonStyle(GradientButtonStyle(colors: Palette.sky))
            .disabled(model.isCleaningDocker || (usage.images.reclaimable + usage.buildCache.reclaimable == 0 && model.dockerContainersToRemove.isEmpty))
        }
        if !oldContainers.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Toggle(isOn: $model.includeStoppedContainers) {
                    Text(L("Ikut hapus \(oldContainers.count) container yang sudah berhenti", "Also remove \(oldContainers.count) stopped containers"))
                        .font(.system(size: 12, weight: .semibold))
                }
                .toggleStyle(.checkbox)
                .disabled(model.isCleaningDocker)
                Text(L("File di dalam container (semua yang tidak disimpan di volume, misalnya database tanpa -v) ikut hilang. Umurnya dihitung dari tanggal container dibuat, bukan terakhir dijalankan.",
                       "Files inside a container (anything not kept in a volume, such as a database run without -v) go with it. Age counts from when the container was created, not when it last ran."))
                    .font(.system(size: 11))
                    .foregroundStyle(model.includeStoppedContainers ? Palette.berry[1] : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(Self.names(oldContainers))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.03)))
        }
        Text(L("Docker melaporkan hingga \(usage.reclaimable.formattedBytes) yang bisa dibersihkan tanpa batas umur; dengan batas umur hasilnya bisa lebih kecil. Docker Desktop mengembalikan ruang ke macOS secara bertahap, jadi ruang kosong bisa baru bertambah beberapa saat kemudian.",
               "Docker reports up to \(usage.reclaimable.formattedBytes) reclaimable without an age limit; with it, less may go. Docker Desktop hands space back to macOS gradually, so free space may grow a little later."))
            .font(.system(size: 11))
            .foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func notice(_ symbol: String, _ colors: [Color], _ text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).foregroundStyle(colors[1])
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button(L("Periksa Lagi", "Check Again")) { Task { await model.refreshDocker() } }
                .buttonStyle(SoftButtonStyle())
        }
    }

    private static func names(_ containers: [DockerContainer]) -> String {
        let shown = containers.prefix(6).map(\.name).joined(separator: ", ")
        return containers.count > 6 ? shown + L(", dan \(containers.count - 6) lagi", ", and \(containers.count - 6) more") : shown
    }

    private var confirmation: String {
        var text = L("Image yang tidak dipakai dan build cache yang dibuat lebih dari \(model.dockerAge.label) lalu dihapus permanen oleh Docker, tidak lewat Trash. Image bisa diunduh ulang saat dibutuhkan. Volume tidak disentuh.",
                     "Unused images and build cache created over \(model.dockerAge.label) ago are deleted for good by Docker, not moved to the Trash. Images can be pulled again when needed. Volumes aren't touched.")
        text += L(" Image yang dibuat di Mac ini (build lokal, docker commit atau load) tidak ada di registry, jadi tidak ikut dihapus.",
                  " Images made on this Mac (local builds, docker commit or load) aren't in a registry, so they're kept.")
        let containers = model.dockerContainersToRemove
        if !containers.isEmpty {
            text += L("\n\nJuga \(containers.count) container yang sudah berhenti, beserta file di dalamnya: \(Self.names(containers)).",
                      "\n\nAlso \(containers.count) stopped containers, with the files inside them: \(Self.names(containers)).")
        }
        return text
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
