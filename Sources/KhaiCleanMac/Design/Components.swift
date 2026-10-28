import SwiftUI

struct GradientIcon: View {
    var symbol: String
    var colors: [Color]
    var size: CGFloat = 44
    var corner: CGFloat? = nil

    var body: some View {
        RoundedRectangle(cornerRadius: corner ?? size * 0.3, style: .continuous)
            .fill(LinearGradient.soft(colors))
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: size * 0.45, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
            )
            .frame(width: size, height: size)
            .shadow(color: (colors.last ?? .clear).opacity(0.3), radius: size * 0.18, y: size * 0.08)
    }
}

struct AppLogo: View {
    var size: CGFloat = 36

    var body: some View {
        Image(nsImage: LogoArtwork.image(size: size))
            .resizable()
            .frame(width: size, height: size)
            .shadow(color: Color(hex: 0x8B7CF6).opacity(0.35), radius: size * 0.18, y: size * 0.08)
    }
}

enum SelectionState {
    case none, partial, all
}

struct CheckCircle: View {
    var state: SelectionState
    var colors: [Color]

    init(isOn: Bool, colors: [Color]) {
        self.state = isOn ? .all : .none
        self.colors = colors
    }

    init(state: SelectionState, colors: [Color]) {
        self.state = state
        self.colors = colors
    }

    var body: some View {
        ZStack {
            if state == .none {
                Circle().strokeBorder(Color.secondary.opacity(0.4), lineWidth: 1.5)
            } else {
                Circle().fill(LinearGradient.soft(colors))
                Image(systemName: state == .all ? "checkmark" : "minus")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 20, height: 20)
        .contentShape(Circle())
        .animation(.snappy(duration: 0.18), value: state)
    }
}

struct GradientButtonStyle: ButtonStyle {
    var colors: [Color]
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            // Buttons keep their label on one line instead of squeezing into a narrow column.
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(.white)
            .padding(.horizontal, 22)
            .padding(.vertical, 11)
            .background(Capsule().fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)))
            .shadow(color: (colors.last ?? .blue).opacity(isEnabled ? 0.35 : 0), radius: 10, y: 5)
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.snappy(duration: 0.2), value: configuration.isPressed)
    }
}

struct SoftButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(.primary)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Capsule().fill(scheme == .dark ? Color.white.opacity(0.1) : Color.white.opacity(0.85)))
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.06)))
            .shadow(color: .black.opacity(0.05), radius: 6, y: 3)
            .opacity(isEnabled ? 1 : 0.5)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.snappy(duration: 0.2), value: configuration.isPressed)
    }
}

struct ModuleHeader<Trailing: View>: View {
    let module: Module
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 14) {
            GradientIcon(symbol: module.symbol, colors: module.colors, size: 50)
            VStack(alignment: .leading, spacing: 2) {
                Text(module.title)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                Text(module.subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            trailing
        }
    }
}

extension ModuleHeader where Trailing == EmptyView {
    init(module: Module) {
        self.init(module: module) { EmptyView() }
    }
}

/// The big round "scan" button with a gentle breathing glow.
struct ScanOrb: View {
    var colors: [Color]
    var isActive: Bool
    var label: String
    var symbol: String = "sparkles"
    var action: () -> Void

    @State private var breathe = false
    @State private var spin = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(LinearGradient.soft(colors).opacity(0.16))
                    .frame(width: 270, height: 270)
                    .scaleEffect(breathe ? 1.06 : 0.94)
                Circle()
                    .fill(LinearGradient.soft(colors).opacity(0.28))
                    .frame(width: 220, height: 220)
                    .scaleEffect(breathe ? 1.02 : 0.97)
                Circle()
                    .fill(LinearGradient.soft(colors))
                    .frame(width: 172, height: 172)
                    .shadow(color: (colors.last ?? .blue).opacity(0.45), radius: 26, y: 14)
                Circle()
                    .trim(from: 0, to: 0.3)
                    .stroke(Color.white.opacity(0.95), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .frame(width: 150, height: 150)
                    .rotationEffect(.degrees(spin ? 360 : 0))
                    .opacity(isActive ? 1 : 0)
                VStack(spacing: 6) {
                    Image(systemName: symbol)
                        .font(.system(size: 34, weight: .semibold))
                        .symbolEffect(.pulse, isActive: isActive)
                    Text(label)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                }
                .foregroundStyle(.white)
            }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(isActive)
        .onAppear {
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) { breathe = true }
            withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) { spin = true }
        }
    }
}

/// Sticky footer with the current selection and the main action.
struct ActionBar<Accessory: View>: View {
    var caption: String
    var value: String
    var buttonTitle: String
    var buttonSymbol: String
    var colors: [Color]
    var isDisabled: Bool
    var action: () -> Void
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(caption)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
            }
            Spacer()
            accessory
            Button(action: action) {
                Label(buttonTitle, systemImage: buttonSymbol)
            }
            .buttonStyle(GradientButtonStyle(colors: colors))
            .disabled(isDisabled)
        }
        .softCard(padding: 16, radius: 20)
    }
}

extension ActionBar where Accessory == EmptyView {
    init(caption: String, value: String, buttonTitle: String, buttonSymbol: String, colors: [Color], isDisabled: Bool, action: @escaping () -> Void) {
        self.init(caption: caption, value: value, buttonTitle: buttonTitle, buttonSymbol: buttonSymbol, colors: colors, isDisabled: isDisabled, action: action) { EmptyView() }
    }
}

struct EmptyStateView<Actions: View>: View {
    var symbol: String
    var colors: [Color]
    var title: String
    var message: String
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(LinearGradient.soft(colors).opacity(0.18))
                    .frame(width: 130, height: 130)
                GradientIcon(symbol: symbol, colors: colors, size: 76)
            }
            VStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                Text(message)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }
            actions
                .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct Chip: View {
    var title: String
    var count: Int?
    var colors: [Color]
    var isSelected: Bool
    var action: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title)
                if let count {
                    Text("\(count)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(isSelected ? Color.white.opacity(0.3) : Color.primary.opacity(0.07)))
                }
            }
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule().fill(isSelected
                    ? AnyShapeStyle(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
                    : AnyShapeStyle(scheme == .dark ? Color.white.opacity(0.08) : Color.white.opacity(0.8)))
            )
            .shadow(color: (colors.last ?? .clear).opacity(isSelected ? 0.3 : 0), radius: 6, y: 3)
        }
        .buttonStyle(.plain)
        .animation(.snappy(duration: 0.2), value: isSelected)
    }
}

struct StatTile: View {
    var title: String
    var value: String
    var colors: [Color]
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Capsule()
                .fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
                .frame(width: 26, height: 5)
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(LinearGradient.soft(colors).opacity(scheme == .dark ? 0.14 : 0.12))
        )
    }
}

struct ToastMessage: Identifiable, Equatable {
    let id = UUID()
    var text: String
    var symbol = "checkmark.circle.fill"
    var colors: [Color]
}

private struct ToastModifier: ViewModifier {
    @Binding var message: ToastMessage?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let toast = message {
                    HStack(spacing: 10) {
                        Image(systemName: toast.symbol)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(LinearGradient.soft(toast.colors))
                        Text(toast.text)
                            .font(.system(size: 13, weight: .medium))
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(Capsule().fill(.regularMaterial))
                    .shadow(color: .black.opacity(0.12), radius: 16, y: 6)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .task(id: toast.id) {
                        try? await Task.sleep(for: .seconds(4))
                        withAnimation(.snappy) { message = nil }
                    }
                }
            }
            .animation(.snappy, value: message)
    }
}

extension View {
    func toast(_ message: Binding<ToastMessage?>) -> some View {
        modifier(ToastModifier(message: message))
    }
}

/// Finder icons, drawn once at the size they are shown. `NSWorkspace.icon(forFile:)` returns an image
/// holding every resolution up to 1024 px, and asking for it again on every redraw adds up fast.
@MainActor
enum FileIcon {
    private static let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 500
        return cache
    }()

    static func image(for url: URL, size: CGFloat) -> NSImage {
        let key = "\(Int(size))|\(url.path)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        let pixels = Int((size * (NSScreen.main?.backingScaleFactor ?? 2)).rounded())
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return icon }
        rep.size = NSSize(width: size, height: size)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        icon.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        cache.setObject(image, forKey: key)
        return image
    }
}
