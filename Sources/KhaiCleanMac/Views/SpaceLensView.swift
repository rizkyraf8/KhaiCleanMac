import SwiftUI

struct SpaceLensView: View {
    @Bindable var model: SpaceLensModel
    @State private var pendingTrash: SpaceItem?
    private let module = Module.spaceLens

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ModuleHeader(module: module) {
                HStack(spacing: 10) {
                    if !VolumeList.shared.volumes.isEmpty {
                        Menu {
                            ForEach(VolumeList.shared.locations) { location in
                                Button {
                                    withAnimation(.smooth) { model.open(root: location.url) }
                                } label: {
                                    Label(location.isVolume ? location.name : L("Folder Home", "Home folder"), systemImage: location.symbol)
                                }
                            }
                        } label: {
                            Label("Disk", systemImage: "externaldrive")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                        }
                        .menuStyle(.button)
                        .buttonStyle(SoftButtonStyle())
                        .fixedSize()
                    }
                    Button {
                        model.chooseFolder()
                    } label: {
                        Label(L("Pilih Folder", "Choose Folder"), systemImage: "folder")
                    }
                    .buttonStyle(SoftButtonStyle())
                }
            }

            breadcrumb
            MeasureBar(model: model)

            HStack(alignment: .top, spacing: 18) {
                treemapCard
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                sideList
                    .frame(width: 300)
            }
        }
        .toast($model.toast)
        .task {
            if model.path.isEmpty { model.open(root: URL.homeDirectory) }
        }
        .alert(
            Removal.question(pendingTrash?.name ?? ""),
            isPresented: Binding(get: { pendingTrash != nil }, set: { if !$0 { pendingTrash = nil } }),
            presenting: pendingTrash
        ) { item in
            Button(Removal.actionTitle, role: .destructive) {
                Task { await model.moveToTrash(item) }
            }
            Button(L("Batal", "Cancel"), role: .cancel) {}
        } message: { item in
            Text("\((item.size ?? 0).formattedBytes). " + Removal.undoNote)
        }
    }

    private var breadcrumb: some View {
        HStack(spacing: 6) {
            ForEach(Array(model.path.enumerated()), id: \.offset) { level, url in
                if level > 0 {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.tertiary)
                }
                let isLast = level == model.path.count - 1
                Button {
                    withAnimation(.smooth) { model.goTo(level: level) }
                } label: {
                    Label(
                        url == URL.homeDirectory ? "Home" : url.lastPathComponent,
                        systemImage: level == 0 ? rootSymbol(url) : "folder"
                    )
                    .font(.system(size: 12, weight: isLast ? .bold : .medium, design: .rounded))
                    .foregroundStyle(isLast ? Color.primary : Color.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(isLast ? Color.white.opacity(0.85) : Color.clear))
                }
                .buttonStyle(.plain)
                .disabled(isLast)
            }
            Spacer()
        }
    }

    private func rootSymbol(_ url: URL) -> String {
        if url == URL.homeDirectory { return "house.fill" }
        return VolumeList.shared.volumes.first { $0.url.standardizedFileURL == url.standardizedFileURL }?.symbol ?? "folder.fill"
    }

    @ViewBuilder
    private var treemapCard: some View {
        let tiles = Array(model.measuredItems.prefix(40))
        Group {
            if tiles.isEmpty {
                VStack(spacing: 10) {
                    if model.isMeasuring {
                        ProgressView()
                        Text(L("Mengukur folder…", "Measuring folder…"))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    } else {
                        Text(L("Folder ini kosong.", "This folder is empty."))
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                TreemapView(
                    items: tiles,
                    selectedID: model.selectedID,
                    colors: { model.color(for: $0) },
                    onSelect: { model.selectedID = $0.id },
                    onOpen: { item in withAnimation(.smooth) { model.open(item) } }
                )
            }
        }
        .softCard(padding: 10)
    }

    private var sideList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("Isi folder", "Folder contents"))
                .font(.system(size: 14, weight: .bold, design: .rounded))
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(model.sortedItems) { item in
                        SpaceRow(
                            item: item,
                            colors: model.color(for: item),
                            share: model.knownTotal > 0 ? Double(item.size ?? 0) / Double(model.knownTotal) : 0,
                            isSelected: model.selectedID == item.id,
                            onSelect: { model.selectedID = item.id },
                            onOpen: { withAnimation(.smooth) { model.open(item) } }
                        )
                    }
                }
            }
            .scrollIndicators(.never)

            if let item = model.selectedItem {
                VStack(alignment: .leading, spacing: 10) {
                    Text(item.name)
                        .font(.system(size: 13, weight: .bold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    HStack(spacing: 8) {
                        Button {
                            NSWorkspace.shared.activateFileViewerSelecting([item.url])
                        } label: {
                            Label("Finder", systemImage: "arrow.up.forward.square")
                        }
                        .buttonStyle(SoftButtonStyle())
                        if SafetyGuard.isAllowed(item.url) {
                            Button {
                                pendingTrash = item
                            } label: {
                                Label(Removal.isPermanent ? L("Hapus", "Delete") : "Trash", systemImage: Removal.actionSymbol)
                            }
                            .buttonStyle(GradientButtonStyle(colors: Module.spaceLens.colors))
                        } else {
                            Label(L("Dilindungi", "Protected"), systemImage: "lock.shield.fill")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(.secondary)
                                .help(L("Folder penting ini tidak bisa dihapus dari KhaiCleanMac", "This important folder can't be removed from KhaiCleanMac"))
                        }
                    }
                }
                .padding(.top, 4)
                .transition(.opacity)
            } else {
                Text(L("Klik untuk memilih, klik dua kali untuk membuka folder.", "Click to select, double-click to open a folder."))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .softCard(padding: 14)
        .frame(maxHeight: .infinity)
    }
}

private struct SpaceRow: View {
    let item: SpaceItem
    let colors: [Color]
    let share: Double
    let isSelected: Bool
    let onSelect: () -> Void
    let onOpen: () -> Void
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(item.size == nil ? AnyShapeStyle(Color.primary.opacity(0.1)) : AnyShapeStyle(LinearGradient.soft(colors)))
                .frame(width: 12, height: 12)
            Image(nsImage: FileIcon.image(for: item.url, size: 20))
                .resizable()
                .frame(width: 20, height: 20)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                GeometryReader { geo in
                    Capsule().fill(Color.primary.opacity(0.06))
                        .overlay(alignment: .leading) {
                            Capsule().fill(LinearGradient.soft(colors)).frame(width: geo.size.width * share)
                        }
                }
                .frame(height: 3)
            }
            Spacer(minLength: 6)
            Text(item.size?.formattedBytes ?? "…")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            if item.canOpen {
                Button(action: onOpen) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                }
                .buttonStyle(.borderless)
                .help(L("Buka folder", "Open folder"))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? colors[0].opacity(0.22) : (isHovering ? Color.primary.opacity(0.04) : .clear))
        )
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: onOpen)
        .onTapGesture(perform: onSelect)
        .onHover { isHovering = $0 }
    }
}

/// Squarified treemap: each tile's area is proportional to its size.
private struct TreemapView: View {
    let items: [SpaceItem]
    let selectedID: URL?
    let colors: (SpaceItem) -> [Color]
    let onSelect: (SpaceItem) -> Void
    let onOpen: (SpaceItem) -> Void

    var body: some View {
        GeometryReader { geo in
            let rects = Treemap.layout(items.map { Double($0.size ?? 0) }, in: CGRect(origin: .zero, size: geo.size))
            ZStack(alignment: .topLeading) {
                ForEach(Array(zip(items, rects)), id: \.0.id) { item, rect in
                    TreemapTile(item: item, colors: colors(item), isSelected: selectedID == item.id)
                        .frame(width: max(rect.width - 4, 0), height: max(rect.height - 4, 0))
                        .offset(x: rect.minX + 2, y: rect.minY + 2)
                        .onTapGesture(count: 2) { onOpen(item) }
                        .onTapGesture { onSelect(item) }
                }
            }
            .animation(.smooth, value: items)
        }
    }
}

private struct TreemapTile: View {
    let item: SpaceItem
    let colors: [Color]
    let isSelected: Bool
    @State private var isHovering = false

    var body: some View {
        GeometryReader { geo in
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(LinearGradient.soft(colors))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.white, lineWidth: isSelected ? 3 : 0)
                )
                .overlay(alignment: .topLeading) {
                    if geo.size.width > 80 && geo.size.height > 44 {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 4) {
                                if item.canOpen {
                                    Image(systemName: "folder.fill").font(.system(size: 10))
                                }
                                Text(item.name)
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                                    .lineLimit(1)
                            }
                            Text((item.size ?? 0).formattedBytes)
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .opacity(0.9)
                        }
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
                        .padding(10)
                    }
                }
                .brightness(isHovering ? 0.04 : 0)
        }
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .help("\(item.name) · \((item.size ?? 0).formattedBytes)")
    }
}

enum Treemap {
    static func layout(_ values: [Double], in bounds: CGRect) -> [CGRect] {
        let total = values.reduce(0, +)
        guard total > 0, bounds.width > 0, bounds.height > 0 else { return values.map { _ in .zero } }
        let scale = bounds.width * bounds.height / total
        var remaining = values.map { $0 * scale }[...]
        var rect = bounds
        var row: [Double] = []
        var result: [CGRect] = []

        func worst(_ row: [Double], side: Double) -> Double {
            let sum = row.reduce(0, +)
            guard let largest = row.max(), let smallest = row.min(), sum > 0, smallest > 0 else { return .infinity }
            return max(side * side * largest / (sum * sum), (sum * sum) / (side * side * smallest))
        }

        func place(_ row: [Double]) {
            let sum = row.reduce(0, +)
            if rect.width >= rect.height {
                let width = sum / rect.height
                var y = rect.minY
                for value in row {
                    let height = value / width
                    result.append(CGRect(x: rect.minX, y: y, width: width, height: height))
                    y += height
                }
                rect = CGRect(x: rect.minX + width, y: rect.minY, width: rect.width - width, height: rect.height)
            } else {
                let height = sum / rect.width
                var x = rect.minX
                for value in row {
                    let width = value / height
                    result.append(CGRect(x: x, y: rect.minY, width: width, height: height))
                    x += width
                }
                rect = CGRect(x: rect.minX, y: rect.minY + height, width: rect.width, height: rect.height - height)
            }
        }

        while let value = remaining.first {
            let side = min(rect.width, rect.height)
            if row.isEmpty || worst(row + [value], side: side) <= worst(row, side: side) {
                row.append(value)
                remaining.removeFirst()
            } else {
                place(row)
                row = []
            }
        }
        if !row.isEmpty { place(row) }
        return result
    }
}

/// A full-width bar under the breadcrumb that follows a folder from "reading" through
/// "measuring item 12 of 40" to "done", so progress is visible the whole way.
private struct MeasureBar: View {
    let model: SpaceLensModel
    private let colors = Module.spaceLens.colors

    private var total: Int { model.items.count }
    private var fraction: Double { total > 0 ? Double(model.measuredCount) / Double(total) : 0 }
    private var folderName: String {
        guard let url = model.current else { return "" }
        return url == URL.homeDirectory ? "Home" : url.lastPathComponent
    }

    var body: some View {
        HStack(spacing: 14) {
            GradientIcon(symbol: model.isMeasuring ? "ruler.fill" : "checkmark", colors: model.isMeasuring ? colors : Palette.mint,
                         size: 36, corner: 11)
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .lineLimit(1)
                    if let name = model.measuringName, model.isMeasuring {
                        Text(L("sedang: \(name)", "now: \(name)"))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer(minLength: 12)
                    Text(counter)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
                if model.isMeasuring && !model.hasListed {
                    ProgressView()
                        .progressViewStyle(.linear)
                        .tint(colors.last)
                } else {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.primary.opacity(0.08))
                            Capsule()
                                .fill(LinearGradient(colors: model.isMeasuring ? colors : Palette.mint, startPoint: .leading, endPoint: .trailing))
                                .frame(width: max(8, geo.size.width * (model.isMeasuring ? fraction : 1)))
                        }
                    }
                    .frame(height: 8)
                    .animation(.smooth, value: fraction)
                }
            }
            Text(model.knownTotal.formattedBytes)
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .contentTransition(.numericText())
                .frame(minWidth: 90, alignment: .trailing)
        }
        .softCard(padding: 14, radius: 18)
    }

    private var title: String {
        if model.isMeasuring && !model.hasListed {
            return L("Membaca isi \(folderName)…", "Reading \(folderName)…")
        }
        return model.isMeasuring
            ? L("Mengukur \(folderName)", "Measuring \(folderName)")
            : L("\(folderName) selesai diukur", "\(folderName) fully measured")
    }

    private var counter: String {
        guard model.hasListed else { return "" }
        return model.isMeasuring
            ? L("\(model.measuredCount) dari \(total) item · \(Int(fraction * 100))%", "\(model.measuredCount) of \(total) items · \(Int(fraction * 100))%")
            : L("\(total) item", "\(total) items")
    }
}
