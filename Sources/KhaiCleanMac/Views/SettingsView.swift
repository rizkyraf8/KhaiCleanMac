import ServiceManagement
import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case general, appearance, reminders, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: L("Umum", "General")
        case .appearance: L("Tampilan", "Appearance")
        case .reminders: L("Pengingat", "Reminders")
        case .about: L("Tentang", "About")
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape.fill"
        case .appearance: "circle.lefthalf.filled"
        case .reminders: "bell.badge.fill"
        case .about: "info.circle.fill"
        }
    }

    var colors: [Color] {
        switch self {
        case .general: Palette.mint
        case .appearance: Palette.lavender
        case .reminders: Palette.peach
        case .about: Palette.sky
        }
    }
}

struct SettingsView: View {
    @State private var tab: SettingsTab

    init(tab: SettingsTab = .general) {
        _tab = State(initialValue: tab)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            header
            TabBar(selection: $tab)
            Group {
                switch tab {
                case .general: GeneralTab()
                case .appearance: AppearanceTab()
                case .reminders: RemindersTab()
                case .about: AboutTab()
                }
            }
            .transition(.opacity)
            Spacer(minLength: 0)
        }
        .padding(26)
        .frame(width: 560, height: 600, alignment: .top)
        .background(SoftBackground(colors: tab.colors))
        .animation(.snappy(duration: 0.2), value: tab)
    }

    private var header: some View {
        HStack(spacing: 14) {
            AppLogo(size: 50)
            VStack(alignment: .leading, spacing: 3) {
                Text(AppInfo.name)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                Text(L("Versi \(AppInfo.version) · Mac bersih, hati tenang", "Version \(AppInfo.version) · Clean Mac, calm mind"))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}

// MARK: - Tabs

private struct GeneralTab: View {
    @Bindable private var settings = AppSettings.shared
    @State private var loginStatus = LoginItem.status
    @State private var loginError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsSection(title: L("Bahasa", "Language"), symbol: "globe") {
                HStack(spacing: 12) {
                    ForEach(AppLanguage.allCases) { language in
                        OptionCard(isSelected: settings.language == language, colors: Palette.mint) {
                            settings.language = language
                        } content: {
                            HStack(spacing: 10) {
                                Text(language.flag)
                                    .font(.system(size: 24))
                                Text(language.nativeName)
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                Spacer(minLength: 24)
                            }
                        }
                    }
                }
            }

            SettingsSection(title: L("Saat Mac menyala", "Startup"), symbol: "power") {
                VStack(spacing: 0) {
                    ToggleRow(
                        symbol: "person.crop.circle.badge.checkmark", colors: Palette.mint,
                        title: L("Buka saat login", "Open at login"),
                        caption: loginCaption,
                        isOn: Binding(get: { loginStatus == .enabled }, set: setLogin)
                    )
                    if loginStatus == .requiresApproval {
                        Button(L("Buka Pengaturan Login Items", "Open Login Items Settings")) { LoginItem.openSystemSettings() }
                            .buttonStyle(.link)
                            .font(.system(size: 11, weight: .semibold))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, 48)
                            .padding(.bottom, 8)
                    }
                    Divider()
                    ToggleRow(
                        symbol: "menubar.rectangle", colors: Palette.lavender,
                        title: L("Tetap di menu bar saat jendela ditutup", "Keep running in the menu bar"),
                        caption: L("Ikon Dock disembunyikan sampai jendela dibuka lagi. Pengingat juga butuh ini agar tetap berjalan.",
                                   "The Dock icon hides until you reopen the window. Reminders need this to keep working."),
                        isOn: $settings.keepInMenuBar
                    )
                }
                .softCard(padding: 12, radius: 16)
            }

            SettingsSection(title: "Smart Scan", symbol: "sparkles") {
                HStack(spacing: 12) {
                    GradientIcon(symbol: "globe", colors: Palette.sky, size: 34, corner: 10)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("Batas umur cache web Chrome", "Chrome web cache age limit"))
                            .font(.system(size: 13, weight: .semibold))
                        Text(L("Cache yang lebih baru tetap disimpan agar situs tetap cepat dibuka.", "Newer cache is kept so sites still load fast."))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 12)
                    Picker("", selection: $settings.chromeCacheAge) {
                        ForEach(ChromeCacheAge.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
                .padding(.vertical, 8)
                .softCard(padding: 12, radius: 16)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            loginStatus = LoginItem.status
        }
    }

    private var loginCaption: String {
        if let loginError { return loginError }
        switch loginStatus {
        case .requiresApproval:
            return L("Menunggu persetujuan di Pengaturan Sistem → Login Items.", "Waiting for approval in System Settings → Login Items.")
        default:
            return L("Paling baik dipakai saat KhaiCleanMac ada di folder Applications.", "Works best when KhaiCleanMac is in your Applications folder.")
        }
    }

    private func setLogin(_ enabled: Bool) {
        do {
            try LoginItem.setEnabled(enabled)
            loginError = nil
        } catch {
            loginError = L("Tidak bisa diubah: \(error.localizedDescription)", "Couldn't change it: \(error.localizedDescription)")
        }
        loginStatus = LoginItem.status
    }
}

private struct AppearanceTab: View {
    private let settings = AppSettings.shared

    var body: some View {
        SettingsSection(title: L("Tema", "Theme"), symbol: "circle.lefthalf.filled") {
            HStack(spacing: 12) {
                ForEach(AppAppearance.allCases) { appearance in
                    OptionCard(isSelected: settings.appearance == appearance, colors: Palette.lavender) {
                        settings.appearance = appearance
                        NSApp.appearance = appearance.nsAppearance
                    } content: {
                        VStack(spacing: 10) {
                            AppearancePreview(appearance: appearance)
                                .frame(height: 64)
                            Text(appearance.title)
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                        }
                    }
                }
            }
        }
    }
}

private struct RemindersTab: View {
    @Bindable private var settings = AppSettings.shared
    @State private var isChecking = false
    @State private var lastResult: Int64?
    @State private var permissionDenied = false

    private var service: ReminderService { .shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsSection(title: L("Pengingat sampah", "Junk reminders"), symbol: "bell.badge") {
                VStack(alignment: .leading, spacing: 14) {
                    ToggleRow(
                        symbol: "bell.fill", colors: Palette.peach,
                        title: L("Ingatkan saat sampah menumpuk", "Remind me when junk piles up"),
                        caption: L("KhaiCleanMac hanya mengukur dan memberi notifikasi. Tidak ada yang dihapus otomatis.",
                                   "KhaiCleanMac only measures and notifies you. Nothing is ever removed automatically."),
                        isOn: Binding(get: { settings.remindersEnabled }, set: setReminders)
                    )
                    .disabled(!service.isAvailable)

                    Group {
                        LabeledPicker(title: L("Periksa", "Check")) {
                            Picker("", selection: $settings.reminderFrequency) {
                                ForEach(ReminderFrequency.allCases) { Text($0.title).tag($0) }
                            }
                        }
                        LabeledPicker(title: L("Ingatkan jika lebih dari", "Remind when over")) {
                            Picker("", selection: $settings.reminderThreshold) {
                                ForEach(ReminderThreshold.allCases) { Text($0.label).tag($0) }
                            }
                        }
                    }
                    .disabled(!settings.remindersEnabled)
                    .opacity(settings.remindersEnabled ? 1 : 0.5)
                }
                .softCard(padding: 14, radius: 16)
            }

            SettingsSection(title: L("Status", "Status"), symbol: "waveform.path.ecg") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(statusTitle)
                                .font(.system(size: 13, weight: .semibold))
                            Text(statusCaption)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 12)
                        Button {
                            Task {
                                isChecking = true
                                lastResult = await service.check(notify: settings.remindersEnabled)
                                isChecking = false
                            }
                        } label: {
                            Label(isChecking ? L("Memeriksa…", "Checking…") : L("Cek Sekarang", "Check Now"), systemImage: "magnifyingglass")
                        }
                        .buttonStyle(SoftButtonStyle())
                        .disabled(isChecking)
                    }
                    if permissionDenied {
                        Text(L("Notifikasi diblokir. Izinkan KhaiCleanMac di Pengaturan Sistem → Notifikasi.",
                               "Notifications are blocked. Allow KhaiCleanMac in System Settings → Notifications."))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Palette.berry[1])
                    }
                    if !settings.keepInMenuBar {
                        Text(L("Pengingat hanya berjalan selama KhaiCleanMac terbuka. Aktifkan \"Tetap di menu bar\" di tab Umum.",
                               "Reminders only run while KhaiCleanMac is open. Turn on \"Keep running in the menu bar\" in General."))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Palette.sunny[1])
                    }
                    if !service.isAvailable {
                        Text(L("Notifikasi hanya tersedia di aplikasi hasil build-app.sh.", "Notifications only work in the app built with build-app.sh."))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .softCard(padding: 14, radius: 16)
            }
        }
    }

    private var statusTitle: String {
        if let lastResult {
            return L("Sampah saat ini sekitar \(lastResult.formattedBytes)", "About \(lastResult.formattedBytes) of junk right now")
        }
        return settings.remindersEnabled ? L("Pengingat aktif", "Reminders are on") : L("Pengingat mati", "Reminders are off")
    }

    private var statusCaption: String {
        guard let last = settings.lastReminderCheck else {
            return L("Belum pernah diperiksa.", "Not checked yet.")
        }
        let when = last.formatted(.relative(presentation: .named).locale(AppSettings.shared.locale))
        return L("Terakhir diperiksa \(when). Batas: \(settings.reminderThreshold.label).",
                 "Last checked \(when). Limit: \(settings.reminderThreshold.label).")
    }

    private func setReminders(_ enabled: Bool) {
        settings.remindersEnabled = enabled
        guard enabled else { return }
        Task {
            let granted = await service.requestPermission()
            permissionDenied = !granted
            if !granted { settings.remindersEnabled = false }
        }
    }
}

private struct AboutTab: View {
    var body: some View {
        SettingsSection(title: L("Tentang", "About"), symbol: "info.circle") {
            VStack(spacing: 0) {
                InfoRow(title: L("Versi", "Version"), value: "\(AppInfo.version) (\(AppInfo.build))")
                Divider()
                InfoRow(title: L("Lisensi", "License"), value: "PolyForm Noncommercial")
                Divider()
                HStack {
                    Text("GitHub")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Link("rizkyraf8/KhaiCleanMac", destination: AppInfo.repository)
                        .font(.system(size: 12, weight: .semibold))
                }
                .font(.system(size: 12))
                .padding(.vertical, 9)
            }
            .softCard(padding: 14, radius: 16)
        }
    }
}

// MARK: - Pieces

private struct TabBar: View {
    @Binding var selection: SettingsTab
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 6) {
            ForEach(SettingsTab.allCases) { tab in
                let isSelected = selection == tab
                Button {
                    selection = tab
                } label: {
                    Label(tab.title, systemImage: tab.symbol)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(isSelected ? Color.white : Color.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            Capsule().fill(isSelected
                                ? AnyShapeStyle(LinearGradient(colors: tab.colors, startPoint: .leading, endPoint: .trailing))
                                : AnyShapeStyle(Color.clear))
                        )
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Capsule().fill(scheme == .dark ? Color.white.opacity(0.07) : Color.white.opacity(0.75)))
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.06)))
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbol)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
            content
        }
    }
}

private struct ToggleRow: View {
    let symbol: String
    let colors: [Color]
    let title: String
    let caption: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            GradientIcon(symbol: symbol, colors: colors, size: 34, corner: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(caption)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .labelsHidden()
        }
        .padding(.vertical, 8)
    }
}

private struct LabeledPicker<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 12, weight: .medium))
            Spacer()
            content
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 240)
        }
        .padding(.leading, 46)
    }
}

private struct OptionCard<Content: View>: View {
    let isSelected: Bool
    let colors: [Color]
    let action: () -> Void
    @ViewBuilder let content: Content
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: action) {
            content
                .padding(12)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(scheme == .dark ? Color.white.opacity(0.06) : Color.white.opacity(0.85))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(
                            isSelected ? AnyShapeStyle(LinearGradient.soft(colors)) : AnyShapeStyle(Color.primary.opacity(0.08)),
                            lineWidth: isSelected ? 2.5 : 1
                        )
                )
                .overlay(alignment: .topTrailing) {
                    if isSelected {
                        CheckCircle(isOn: true, colors: colors)
                            .padding(7)
                    }
                }
                .shadow(color: (colors.last ?? .clear).opacity(isSelected ? 0.18 : 0), radius: 10, y: 4)
                .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .animation(.snappy(duration: 0.2), value: isSelected)
    }
}

/// A tiny window sketch for each appearance; "system" is split diagonally between both.
private struct AppearancePreview: View {
    let appearance: AppAppearance

    var body: some View {
        switch appearance {
        case .light:
            MiniWindow(isDark: false)
        case .dark:
            MiniWindow(isDark: true)
        case .system:
            ZStack {
                MiniWindow(isDark: false)
                MiniWindow(isDark: true)
                    .mask(
                        GeometryReader { geo in
                            Path { path in
                                path.move(to: CGPoint(x: geo.size.width, y: 0))
                                path.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height))
                                path.addLine(to: CGPoint(x: 0, y: geo.size.height))
                                path.closeSubpath()
                            }
                        }
                    )
            }
        }
    }
}

private struct MiniWindow: View {
    let isDark: Bool

    var body: some View {
        let line = isDark ? Color.white.opacity(0.2) : Color.black.opacity(0.1)
        RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(isDark ? Color(hex: 0x1E1F27) : Color(hex: 0xF5F6FB))
            .overlay(alignment: .leading) {
                HStack(spacing: 7) {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(isDark ? Color(hex: 0x2B2C36) : .white)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 6) {
                        Capsule().fill(LinearGradient.soft(Palette.mint)).frame(width: 32, height: 7)
                        Capsule().fill(line).frame(width: 46, height: 4)
                        Capsule().fill(line).frame(width: 36, height: 4)
                    }
                    Spacer(minLength: 0)
                }
                .padding(7)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.1))
            )
    }
}

private struct InfoRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
                .textSelection(.enabled)
        }
        .font(.system(size: 12))
        .padding(.vertical, 9)
    }
}
