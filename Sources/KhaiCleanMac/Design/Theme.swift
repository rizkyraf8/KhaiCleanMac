import SwiftUI

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

/// Soft pastel gradients. Every module and category gets its own pair.
enum Palette {
    static let mint = [Color(hex: 0x5EE0C1), Color(hex: 0x38B6E8)]
    static let peach = [Color(hex: 0xFFB27A), Color(hex: 0xFF6FA5)]
    static let lavender = [Color(hex: 0xB39BFF), Color(hex: 0x6E9BFF)]
    static let leaf = [Color(hex: 0x86EFAC), Color(hex: 0x2DD4BF)]
    static let sunny = [Color(hex: 0xFDD86A), Color(hex: 0xFB923C)]
    static let ocean = [Color(hex: 0x93C5FD), Color(hex: 0x6366F1)]
    static let candy = [Color(hex: 0xF9A8D4), Color(hex: 0xC084FC)]
    static let berry = [Color(hex: 0xFDA4AF), Color(hex: 0xF43F5E)]
    static let sky = [Color(hex: 0x67D2F5), Color(hex: 0x0EA5E9)]
    static let grape = [Color(hex: 0xC4B5FD), Color(hex: 0x8B5CF6)]
    static let slate = [Color(hex: 0xCBD5E1), Color(hex: 0x94A3B8)]
    static let aqua = [Color(hex: 0x7DD3FC), Color(hex: 0x34D399)]
    static let blush = [Color(hex: 0xFBCFE8), Color(hex: 0xFB7185)]
    static let logo = [Color(hex: 0x5EE0C1), Color(hex: 0x6E9BFF), Color(hex: 0xC084FC)]
}

extension LinearGradient {
    static func soft(_ colors: [Color]) -> LinearGradient {
        LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

/// Window background: a calm base with blurred pastel blobs tinted by the active module.
struct SoftBackground: View {
    var colors: [Color]
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                (scheme == .dark ? Color(hex: 0x15161D) : Color(hex: 0xF5F6FB))
                Circle()
                    .fill(colors[0].opacity(scheme == .dark ? 0.22 : 0.38))
                    .frame(width: w * 0.55)
                    .blur(radius: 120)
                    .offset(x: w * 0.32, y: -h * 0.32)
                Circle()
                    .fill((colors.last ?? colors[0]).opacity(scheme == .dark ? 0.16 : 0.24))
                    .frame(width: w * 0.5)
                    .blur(radius: 130)
                    .offset(x: -w * 0.05, y: h * 0.42)
                Circle()
                    .fill(Color(hex: 0xC4B5FD).opacity(scheme == .dark ? 0.12 : 0.22))
                    .frame(width: w * 0.4)
                    .blur(radius: 140)
                    .offset(x: -w * 0.38, y: -h * 0.3)
            }
            .frame(width: w, height: h)
            .drawingGroup()
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.6), value: colors)
    }
}

struct SoftCard: ViewModifier {
    var padding: CGFloat
    var radius: CGFloat
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(scheme == .dark ? Color.white.opacity(0.06) : Color.white.opacity(0.78))
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.white.opacity(scheme == .dark ? 0.08 : 0.9), lineWidth: 1)
            )
            .shadow(color: .black.opacity(scheme == .dark ? 0.3 : 0.06), radius: 18, y: 8)
    }
}

extension View {
    func softCard(padding: CGFloat = 18, radius: CGFloat = 22) -> some View {
        modifier(SoftCard(padding: padding, radius: radius))
    }
}

extension Int64 {
    var formattedBytes: String {
        formatted(.byteCount(style: .file).locale(AppSettings.shared.locale))
    }
}

extension UInt64 {
    /// RAM sizes count in powers of 1024, as in Activity Monitor (an 18 GB Mac shows 18 GB).
    var formattedMemory: String {
        Int64(clamping: self).formatted(.byteCount(style: .memory).locale(AppSettings.shared.locale))
    }
}

extension URL {
    /// Path with the home folder shortened to `~`.
    var abbreviatedPath: String {
        let home = URL.homeDirectory.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}
