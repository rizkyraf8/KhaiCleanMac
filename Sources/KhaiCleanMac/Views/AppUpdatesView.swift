import SwiftUI

struct AppUpdatesView: View {
    @Bindable var model: AppUpdatesModel
    @State private var showUpToDate = false
    private let module = Module.appUpdates

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ModuleHeader(module: module) {
                if model.phase == .results {
                    Button {
                        model.check()
                    } label: {
                        Label(L("Periksa Lagi", "Check Again"), systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(SoftButtonStyle())
                }
            }

            switch model.phase {
            case .idle:
                EmptyStateView(
                    symbol: module.symbol,
                    colors: module.colors,
                    title: L("Cek versi baru semua app", "Check every app for a new version"),
                    message: L("Untuk app yang memakai Sparkle, KhaiCleanMac membaca feed pembaruan milik app itu sendiri, sama seperti yang dilakukan app tersebut. Tidak ada data tentang kamu atau app lain yang dikirim.",
                               "For apps that use Sparkle, KhaiCleanMac reads the app's own update feed, just like the app does itself. Nothing about you or your other apps is sent.")
                ) {
                    Button {
                        model.check()
                    } label: {
                        Label(L("Periksa Pembaruan", "Check for Updates"), systemImage: "arrow.down.circle")
                    }
                    .buttonStyle(GradientButtonStyle(colors: module.colors))
                }
            case .checking:
                checkingView
            case .results:
                resultsView
            }
        }
    }

    private var checkingView: some View {
        VStack(spacing: 24) {
            Spacer()
            ScanOrb(colors: module.colors, isActive: true, label: L("Memeriksa…", "Checking…"), symbol: "arrow.down.app") {}
            VStack(spacing: 10) {
                Text(model.feedCount == 0
                     ? L("Membaca daftar app…", "Reading your apps…")
                     : L("\(model.checkedCount) dari \(model.feedCount) app diperiksa", "\(model.checkedCount) of \(model.feedCount) apps checked"))
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
                    .animation(.snappy, value: model.checkedCount)
                if model.feedCount > 0 {
                    ProgressView(value: Double(model.checkedCount), total: Double(max(model.feedCount, 1)))
                        .tint(module.colors.last)
                        .frame(width: 280)
                }
                if !model.updates.isEmpty {
                    Text(L("\(model.updates.count) pembaruan ditemukan sejauh ini", "\(model.updates.count) updates found so far"))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            Button(L("Batal", "Cancel")) { model.cancel() }
                .buttonStyle(SoftButtonStyle())
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var resultsView: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                StatTile(title: L("Ada versi baru", "New version out"), value: "\(model.updates.count)", colors: module.colors)
                StatTile(title: L("Sudah terbaru", "Up to date"), value: "\(model.upToDate.count)", colors: Palette.leaf)
                StatTile(title: L("Dari App Store", "From the App Store"), value: "\(model.appStoreApps.count)", colors: Palette.sky)
                StatTile(title: L("Diperbarui dengan cara lain", "Updated another way"), value: "\(model.otherApps.count + model.unreachable.count)", colors: Palette.slate)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    updatesCard
                    if !model.appStoreApps.isEmpty { appStoreCard }
                    if !model.upToDate.isEmpty { upToDateCard }
                    otherCard
                }
                .padding(4)
            }
            .scrollIndicators(.never)
        }
    }

    // MARK: Cards

    private var updatesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            cardHeader(
                L("Versi baru tersedia", "New versions available"), symbol: "arrow.down.circle.fill", colors: module.colors,
                caption: L("Klik Buka untuk memperbarui: app akan memasang versinya sendiri dan memeriksa tanda tangannya. Kalau tidak muncul, pilih \"Check for Updates…\" di menu app.",
                           "Click Open to update: the app installs the new version itself and checks its signature. If nothing shows up, choose \"Check for Updates…\" in the app's menu.")
            )
            if model.updates.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(LinearGradient.soft(Palette.leaf))
                    Text(L("Semua app yang bisa diperiksa sudah versi terbaru.", "Every app that could be checked is up to date."))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            } else {
                ForEach(model.updates) { update in
                    UpdateRow(update: update, onOpen: { model.open(update.app) })
                }
            }
        }
        .softCard(padding: 16)
    }

    private var appStoreCard: some View {
        HStack(spacing: 14) {
            cardHeader(
                L("\(model.appStoreApps.count) app dari App Store", "\(model.appStoreApps.count) apps from the App Store"), symbol: "bag.fill", colors: Palette.sky,
                caption: model.appStoreApps.prefix(6).map(\.app.name).joined(separator: ", ")
                    + (model.appStoreApps.count > 6 ? L(", dan lainnya", ", and more") : "")
                    + L(". Pembaruannya diatur oleh App Store.", ". Their updates come through the App Store.")
            )
            Spacer(minLength: 12)
            Button(L("Buka App Store", "Open App Store")) { model.openAppStoreUpdates() }
                .buttonStyle(SoftButtonStyle())
        }
        .softCard(padding: 16)
    }

    private var upToDateCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.snappy) { showUpToDate.toggle() }
            } label: {
                HStack {
                    cardHeader(L("Sudah versi terbaru", "Up to date"), symbol: "checkmark.seal.fill", colors: Palette.leaf,
                               caption: L("\(model.upToDate.count) app", "\(model.upToDate.count) apps"))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(showUpToDate ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if showUpToDate {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 8) {
                    ForEach(model.upToDate) { app in
                        HStack(spacing: 8) {
                            Image(nsImage: FileIcon.image(for: app.app.url, size: 22)).resizable().frame(width: 22, height: 22)
                            Text(app.app.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                            Text(app.displayVersion).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }
            }
        }
        .softCard(padding: 16)
    }

    private var otherCard: some View {
        cardHeader(
            L("Tidak bisa diperiksa di sini", "Can't be checked here"), symbol: "questionmark.app.fill", colors: Palette.slate,
            caption: L("\(model.otherApps.count) app memakai updater sendiri, Homebrew, atau tidak punya pembaruan otomatis.",
                       "\(model.otherApps.count) apps use their own updater, Homebrew, or don't update automatically.")
                + (model.unreachable.isEmpty ? "" : L(" Feed \(model.unreachable.count) app tidak bisa dihubungi: \(model.unreachable.map(\.app.name).joined(separator: ", ")).",
                                                       " The feed of \(model.unreachable.count) apps couldn't be reached: \(model.unreachable.map(\.app.name).joined(separator: ", "))."))
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .softCard(padding: 16)
    }

    private func cardHeader(_ title: String, symbol: String, colors: [Color], caption: String) -> some View {
        HStack(spacing: 10) {
            GradientIcon(symbol: symbol, colors: colors, size: 30, corner: 9)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 14, weight: .bold, design: .rounded))
                Text(caption).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct UpdateRow: View {
    let update: AvailableUpdate
    let onOpen: () -> Void
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: FileIcon.image(for: update.app.app.url, size: 32)).resizable().frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 3) {
                Text(update.app.app.name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(update.app.displayVersion)
                        .foregroundStyle(.secondary)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.tertiary)
                    Text(update.release.displayVersion)
                        .fontWeight(.bold)
                        .foregroundStyle(LinearGradient.soft(Module.appUpdates.colors))
                    if let date = update.release.date {
                        Text("· " + L("dirilis \(date.formatted(.relative(presentation: .named)))", "released \(date.formatted(.relative(presentation: .named)))"))
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.system(size: 11, design: .rounded))
                .lineLimit(1)
            }
            Spacer(minLength: 12)
            if let notes = update.release.releaseNotes {
                Link(destination: notes) {
                    Label(L("Catatan Rilis", "Release Notes"), systemImage: "doc.text")
                }
                .font(.system(size: 12, weight: .semibold))
                .opacity(isHovering ? 1 : 0.6)
            }
            Button(L("Buka", "Open"), action: onOpen)
                .buttonStyle(SoftButtonStyle())
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(isHovering ? Color.primary.opacity(0.04) : .clear))
        .onHover { isHovering = $0 }
    }
}
