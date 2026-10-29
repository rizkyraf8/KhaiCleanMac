import SwiftUI

struct HistoryView: View {
    private var history: CleanHistory { .shared }
    @State private var expanded: Set<CleanRecord.ID> = []
    @State private var busy: Set<UUID> = []
    @State private var confirmClear = false
    @State private var toast: ToastMessage?
    private let module = Module.history

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ModuleHeader(module: module) {
                if !history.records.isEmpty {
                    Button(L("Hapus riwayat", "Clear history")) { confirmClear = true }
                        .buttonStyle(SoftButtonStyle())
                }
            }

            if history.records.isEmpty {
                EmptyStateView(
                    symbol: module.symbol, colors: module.colors,
                    title: L("Belum ada riwayat", "No history yet"),
                    message: L("Setiap kali kamu membersihkan sesuatu, catatannya muncul di sini: kapan, dari modul mana, dan apa saja. Yang masih ada di Trash bisa dikembalikan dengan satu klik.",
                               "Every cleanup shows up here: when, from which module and what. Anything still in the Trash can be put back with one click.")
                ) { EmptyView() }
            } else {
                if !Restorer.canReadTrash() { accessNote }
                ScrollView {
                    LazyVStack(spacing: 14) {
                        ForEach(history.records) { record in
                            recordCard(record)
                        }
                    }
                    .padding(4)
                }
                .scrollIndicators(.never)
            }
        }
        .toast($toast)
        .alert(L("Hapus seluruh riwayat?", "Clear the whole history?"), isPresented: $confirmClear) {
            Button(L("Hapus riwayat", "Clear history"), role: .destructive) { history.clear() }
            Button(L("Batal", "Cancel"), role: .cancel) {}
        } message: {
            Text(L("Hanya catatannya yang dihapus. Isi Trash tidak berubah, tapi item lama tidak bisa dikembalikan dari sini lagi.",
                   "Only the records go. The Trash stays as it is, but older items can't be put back from here any more."))
        }
    }

    private var accessNote: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.shield.fill").foregroundStyle(LinearGradient.soft(Palette.peach))
            Text(L("Tanpa Akses Disk Penuh, KhaiCleanMac tidak bisa membaca Trash. Kalau tombol Kembalikan gagal, buka Trash lalu pakai \"Put Back\" di Finder.",
                   "Without Full Disk Access KhaiCleanMac can't read the Trash. If Restore fails, open the Trash and use \"Put Back\" in Finder."))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button(L("Panduan", "Guide")) { AppRouter.shared.showOnboarding(at: .access) }
                .buttonStyle(SoftButtonStyle())
        }
        .softCard(padding: 14, radius: 16)
    }

    // MARK: Record

    private func recordCard(_ record: CleanRecord) -> some View {
        let isOpen = expanded.contains(record.id)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                GradientIcon(symbol: record.permanent ? "trash.slash.fill" : "trash.fill",
                             colors: record.permanent ? Palette.berry : module.colors, size: 38, corner: 11)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(record.source) · \(record.totalSize.formattedBytes)")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                    Text(subtitle(record))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if record.restorableCount > 0 {
                    Button {
                        Task { await restoreAll(record) }
                    } label: {
                        Label(L("Kembalikan semua", "Restore all"), systemImage: "arrow.uturn.backward")
                    }
                    .buttonStyle(SoftButtonStyle())
                    .disabled(busy.contains(record.id))
                }
                Button {
                    withAnimation(.snappy) {
                        if isOpen { expanded.remove(record.id) } else { expanded.insert(record.id) }
                    }
                } label: {
                    Image(systemName: "chevron.down")
                        .rotationEffect(.degrees(isOpen ? 180 : 0))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(isOpen ? L("Sembunyikan", "Hide") : L("Lihat item", "Show items"))
            }
            if isOpen {
                VStack(spacing: 2) {
                    ForEach(record.items) { item in
                        itemRow(item, in: record)
                    }
                }
                .transition(.opacity)
            }
        }
        .softCard(padding: 16)
    }

    private func subtitle(_ record: CleanRecord) -> String {
        let when = record.date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(AppSettings.shared.locale))
        let mode = record.permanent ? L("dihapus permanen", "deleted permanently") : L("ke Trash", "to the Trash")
        return L("\(when) · \(record.items.count) item \(mode)", "\(when) · \(record.items.count) \(record.items.count == 1 ? "item" : "items") \(mode)")
    }

    private func itemRow(_ item: RemovedItem, in record: CleanRecord) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(URL(filePath: item.originalPath).deletingLastPathComponent().abbreviatedPath)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            Spacer(minLength: 8)
            Text(item.size.formattedBytes)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            status(item, in: record)
                .frame(width: 130, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.03)))
    }

    @ViewBuilder
    private func status(_ item: RemovedItem, in record: CleanRecord) -> some View {
        if item.canRestore {
            Button {
                Task { await restore(item, in: record) }
            } label: {
                if busy.contains(item.id) { ProgressView().controlSize(.small) } else { Text(L("Kembalikan", "Restore")) }
            }
            .buttonStyle(SoftButtonStyle())
            .disabled(busy.contains(item.id))
        } else {
            Text(statusText(item))
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.primary.opacity(0.06)))
        }
    }

    private func statusText(_ item: RemovedItem) -> String {
        if item.trashedPath == nil { return L("Dihapus permanen", "Deleted permanently") }
        if let restored = item.restoredAt, restored != .distantPast { return L("Dikembalikan", "Restored") }
        return L("Sudah tidak di Trash", "No longer in Trash")
    }

    // MARK: Actions

    private func restore(_ item: RemovedItem, in record: CleanRecord) async {
        busy.insert(item.id)
        let result = await history.restore(item.id, in: record.id)
        busy.remove(item.id)
        toast = message(for: result, name: item.name)
    }

    private func restoreAll(_ record: CleanRecord) async {
        busy.insert(record.id)
        let outcome = await history.restoreAll(in: record.id)
        busy.remove(record.id)
        if outcome.results.contains(.noAccess) {
            toast = message(for: .noAccess, name: record.source)
        } else {
            toast = ToastMessage(text: L("\(outcome.restored) dari \(outcome.results.count) item dikembalikan",
                                         "Restored \(outcome.restored) of \(outcome.results.count) items"),
                                 symbol: "arrow.uturn.backward.circle.fill", colors: module.colors)
        }
    }

    private func message(for result: RestoreResult, name: String) -> ToastMessage {
        switch result {
        case .restored:
            ToastMessage(text: L("\(name) dikembalikan ke tempat asalnya", "\(name) is back where it was"),
                         symbol: "arrow.uturn.backward.circle.fill", colors: module.colors)
        case .notInTrash:
            ToastMessage(text: L("\(name) sudah tidak ada di Trash", "\(name) is no longer in the Trash"),
                         symbol: "questionmark.circle.fill", colors: Palette.slate)
        case .conflict:
            ToastMessage(text: L("Sudah ada file baru di lokasi asal \(name), jadi tidak ditimpa", "Something new already sits where \(name) was, so it wasn't overwritten"),
                         symbol: "exclamationmark.triangle.fill", colors: Palette.sunny)
        case .noAccess:
            ToastMessage(text: L("Butuh Akses Disk Penuh untuk membaca Trash. Bisa juga pakai Put Back di Finder.", "Full Disk Access is needed to read the Trash. You can also use Put Back in Finder."),
                         symbol: "lock.shield.fill", colors: Palette.peach)
        case .failed:
            ToastMessage(text: L("Gagal mengembalikan \(name)", "Couldn't restore \(name)"),
                         symbol: "exclamationmark.triangle.fill", colors: Palette.berry)
        }
    }
}
