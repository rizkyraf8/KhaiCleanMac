import SwiftUI

struct ContentView: View {
    @State private var selection: Module
    @State private var smartScan: SmartScanModel
    @State private var largeFiles = LargeFilesModel()
    @State private var duplicates: DuplicatesModel
    @State private var developer: DeveloperModel
    @State private var spaceLens = SpaceLensModel()
    @State private var memory = MemoryModel()
    @State private var startup = StartupModel()
    @State private var extensions = ExtensionsModel()
    @State private var appUpdates: AppUpdatesModel
    @State private var privacy = PrivacyModel()
    @Bindable private var router = AppRouter.shared
    @State private var uninstaller: UninstallerModel

    init(
        selection: Module = .home,
        smartScan: SmartScanModel = SmartScanModel(),
        duplicates: DuplicatesModel = DuplicatesModel(),
        developer: DeveloperModel = DeveloperModel(),
        uninstaller: UninstallerModel = UninstallerModel(),
        appUpdates: AppUpdatesModel = AppUpdatesModel()
    ) {
        _selection = State(initialValue: selection)
        _smartScan = State(initialValue: smartScan)
        _duplicates = State(initialValue: duplicates)
        _developer = State(initialValue: developer)
        _uninstaller = State(initialValue: uninstaller)
        _appUpdates = State(initialValue: appUpdates)
    }

    private func open(_ module: Module) {
        withAnimation(.snappy) { selection = module }
    }

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(selection: $selection)
                .frame(width: 248)

            Group {
                switch selection {
                case .home:
                    HomeView(smartScan: smartScan, onOpen: open) {
                        open(.smartScan)
                        Task { await smartScan.scan() }
                    }
                case .smartScan: SmartScanView(model: smartScan)
                case .largeFiles: LargeFilesView(model: largeFiles)
                case .duplicates: DuplicatesView(model: duplicates)
                case .developer: DeveloperView(model: developer)
                case .spaceLens: SpaceLensView(model: spaceLens)
                case .startup: StartupView(model: startup)
                case .memory: MemoryView(model: memory)
                case .history: HistoryView()
                case .extensions: ExtensionsView(model: extensions)
                case .uninstaller: UninstallerView(model: uninstaller)
                case .appUpdates: AppUpdatesView(model: appUpdates)
                case .privacy: PrivacyView(model: privacy)
                }
            }
            .padding(.horizontal, 30)
            .padding(.top, 34)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.opacity)
            .id(selection)
        }
        .background(SoftBackground(colors: selection.colors))
        .frame(minWidth: 1000, minHeight: 760)
        .sheet(item: $router.onboarding) { step in
            OnboardingView(step: step) {
                AppSettings.shared.hasCompletedOnboarding = true
                router.onboarding = nil
            }
        }
        .task {
            guard !AppInfo.isSnapshot else { return }
            if !AppSettings.shared.hasCompletedOnboarding {
                router.onboarding = .welcome
            } else if !router.didOfferAccessGuide && !Permissions.hasFullDiskAccess {
                // Full Disk Access is still off: open the guide at that step again on every launch.
                router.onboarding = .access
            }
            router.didOfferAccessGuide = true
        }
        // With "keep in menu bar" on, closing the window hides the Dock icon until it is reopened.
        .onAppear { NSApp.setActivationPolicy(.regular) }
        .onDisappear {
            if AppSettings.shared.keepInMenuBar { NSApp.setActivationPolicy(.accessory) }
        }
    }
}

struct SidebarView: View {
    @Binding var selection: Module
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 11) {
                AppLogo(size: 38)
                VStack(alignment: .leading, spacing: 1) {
                    Text(AppInfo.name)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                    Text(L("Mac bersih, hati tenang", "Clean Mac, calm mind"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 6)
            .padding(.top, 46)
            .padding(.bottom, 14)

            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Module.Section.allCases, id: \.self) { section in
                        if !section.title.isEmpty {
                            Text(section.title)
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 10)
                                .padding(.top, 8)
                                .padding(.bottom, 2)
                        }

                        ForEach(Module.allCases.filter { $0.section == section }) { module in
                            SidebarRow(module: module, isSelected: selection == module) {
                                withAnimation(.snappy) { selection = module }
                            }
                        }
                    }
                }
            }
            .scrollIndicators(.never)

            Spacer(minLength: 8)

            AccessCard()
            SidebarFooter()
        }
        .padding(14)
        .frame(maxHeight: .infinity)
        .background(scheme == .dark ? Color.white.opacity(0.03) : Color.white.opacity(0.35))
        .overlay(alignment: .trailing) {
            Rectangle().fill(Color.primary.opacity(0.06)).frame(width: 1)
        }
    }
}

private struct SidebarRow: View {
    let module: Module
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovering = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                GradientIcon(symbol: module.symbol, colors: module.colors, size: 34, corner: 10)
                VStack(alignment: .leading, spacing: 1) {
                    Text(module.title)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                    Text(module.tagline)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(background)
                    .shadow(color: .black.opacity(isSelected ? 0.07 : 0), radius: 10, y: 4)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }

    private var background: Color {
        if isSelected { return scheme == .dark ? Color.white.opacity(0.1) : Color.white.opacity(0.92) }
        return isHovering ? Color.primary.opacity(0.04) : .clear
    }
}

private struct SidebarFooter: View {
    @State private var isHovering = false

    var body: some View {
        HStack {
            SettingsLink {
                Label(L("Pengaturan", "Settings"), systemImage: "gearshape.fill")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .fixedSize()
                    .foregroundStyle(isHovering ? .primary : .secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.primary.opacity(isHovering ? 0.08 : 0.05)))
            }
            .buttonStyle(.plain)
            .onHover { isHovering = $0 }
            .help(L("Bahasa, tampilan, dan info aplikasi (⌘,)", "Language, appearance and app info (⌘,)"))
            Spacer()
            if UpdateChecker.shared.isUpdateAvailable, let latest = UpdateChecker.shared.latest {
                updatePill(latest.version.description)
            } else {
                Text("v\(AppInfo.version)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .help(L("Versi \(AppInfo.version) (build \(AppInfo.build))", "Version \(AppInfo.version) (build \(AppInfo.build))"))
            }
        }
        .padding(.top, 6)
    }

    /// The same as Home's Update button: installs in place when the release has a checksum, and falls
    /// back to the browser download without one or after an install failed.
    @ViewBuilder
    private func updatePill(_ version: String) -> some View {
        let checker = UpdateChecker.shared
        let installs: Bool = {
            if case .failed = checker.installStep { return false }
            return checker.canInstallInApp
        }()
        if checker.installStep.isBusy {
            HStack(spacing: 5) {
                ProgressView().controlSize(.mini)
                Text(InstallProgressNote.busyText(checker.installStep))
            }
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(.secondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color.primary.opacity(0.06)))
        } else {
            Button {
                if installs { Task { await checker.install() } } else { checker.openDownload() }
            } label: {
                Label(version, systemImage: installs ? "arrow.triangle.2.circlepath" : "arrow.down.circle.fill")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .fixedSize()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(LinearGradient(colors: Palette.mint, startPoint: .leading, endPoint: .trailing)))
            }
            .buttonStyle(.plain)
            .help(installs
                  ? L("Kamu memakai \(AppInfo.version). Klik untuk memperbarui ke \(version): diunduh, dicek, lalu dipasang dan dibuka ulang.",
                      "You have \(AppInfo.version). Click to update to \(version): downloaded, verified, installed and reopened.")
                  : L("Kamu memakai \(AppInfo.version). Klik untuk mengunduh \(version).", "You have \(AppInfo.version). Click to download \(version)."))
        }
    }
}


private struct AccessCard: View {
    @State private var granted = Permissions.hasFullDiskAccess
    @State private var showStaleHint = false

    var body: some View {
        Group {
            if granted {
                Label(L("Akses Disk Penuh aktif", "Full Disk Access on"), systemImage: "checkmark.shield.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color(hex: 0x10B981))
                    .padding(.horizontal, 6)
                    .padding(.top, 4)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Label(L("Akses Disk Penuh", "Full Disk Access"), systemImage: "lock.shield.fill")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(LinearGradient.soft(Palette.peach))
                    Text(L("Izinkan agar pemindaian dan uninstall lebih lengkap.", "Allow it for more thorough scans and uninstalls."))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 12) {
                        Button(L("Panduan", "Guide")) { AppRouter.shared.showOnboarding(at: .access) }
                        Button(L("Cek Lagi", "Check Again")) {
                            withAnimation(.snappy) {
                                granted = Permissions.hasFullDiskAccess
                                showStaleHint = !granted
                            }
                        }
                    }
                    .buttonStyle(.link)
                    .font(.system(size: 11, weight: .semibold))
                    // Only worth the space once the user believes they already allowed it.
                    if showStaleHint {
                        Text(L("Sudah diizinkan tapi masih muncul? Di Pengaturan, hapus KhaiCleanMac dengan tombol −, tambahkan lagi, lalu buka ulang aplikasi.",
                               "Already allowed but still showing? In Settings, remove KhaiCleanMac with the − button, add it again, then reopen the app."))
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .softCard(padding: 12, radius: 16)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            granted = Permissions.hasFullDiskAccess
        }
    }
}
