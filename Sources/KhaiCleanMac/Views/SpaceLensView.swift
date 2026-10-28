import SwiftUI

struct SpaceLensView: View {
    @Bindable var model: SpaceLensModel
    @State private var pendingTrash: SpaceItem?
    private let module = Module.spaceLens

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ModuleHeader(module: module) {
                Button {
                    model.chooseFolder()
                } label: {
                    Label(L("Pilih Folder", "Choose Folder"), systemImage: "folder")
                }
                .buttonStyle(SoftButtonStyle())
            }

            breadcrumb

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
            L("Pindahkan \(pendingTrash?.name ?? "") ke Trash?", "Move \(pendingTrash?.name ?? "") to the Trash?"),
            isPresented: Binding(get: { pendingTrash != nil }, set: { if !$0 { pendingTrash = nil } }),
            presenting: pendingTrash
        ) { item in
            Button(L("Pindahkan ke Trash", "Move to Trash"), role: .destructive) {
                Task { await model.moveToTrash(item) }
            }
            Button(L("Batal", "Cancel"), role: .cancel) {}
        } message: { item in
            Text(L("\((item.size ?? 0).formattedBytes) akan dipindahkan ke Trash dan masih bisa dikembalikan.", "\((item.size ?? 0).formattedBytes) will be moved to the Trash and can still be put back."))
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
                        systemImage: level == 0 ? (url == URL.homeDirectory ? "house.fill" : "folder.fill") : "folder"
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
            if model.isMeasuring {
                ProgressView().controlSize(.small)
                Text(L("Mengukur \(model.measuredCount)/\(model.items.count)…", "Measuring \(model.measuredCount)/\(model.items.count)…"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Text(model.knownTotal.formattedBytes)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .contentTransition(.numericText())
        }
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
                        Button {
                            pendingTrash = item
                        } label: {
                            Label("Trash", systemImage: "trash")
                        }
                        .buttonStyle(GradientButtonStyle(colors: Module.spaceLens.colors))
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
