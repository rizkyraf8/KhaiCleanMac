import SwiftUI

struct SettingsView: View {
    private let settings = AppSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            header

            section(L("Bahasa", "Language"), symbol: "globe") {
                HStack(spacing: 12) {
                    ForEach(AppLanguage.allCases) { language in
                        OptionCard(isSelected: settings.language == language, colors: Palette.mint) {
                            withAnimation(.snappy) { settings.language = language }
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

            section(L("Tampilan", "Appearance"), symbol: "circle.lefthalf.filled") {
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

            section(L("Tentang", "About"), symbol: "info.circle") {
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
        .padding(26)
        .frame(width: 540)
        .background(SoftBackground(colors: Palette.lavender))
    }

    private var header: some View {
        HStack(spacing: 14) {
            AppLogo(size: 54)
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

    private func section<Content: View>(_ title: String, symbol: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbol)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
            content()
        }
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
