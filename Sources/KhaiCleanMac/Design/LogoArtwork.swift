import AppKit

/// The KhaiCleanMac logo: a monitor mid-clean — a wiper leaves the left of the screen
/// shiny mint while the right is still dusty. Flat colours only, no decorative circles.
/// Shared by the app icon (scripts/make-icon) and the in-app logo, so both always match.
enum LogoArtwork {
    /// Design grid: the tile is 824×824 units (the macOS icon body inside a 1024 canvas).
    private static let unit: CGFloat = 824

    private static let tile = color(0x8B7CF6)
    private static let frame = color(0xFFFFFF)
    private static let cleanScreen = color(0x5EE0C1)
    private static let shine = color(0x9AF0DC)
    private static let dustyScreen = color(0xB7B2D0)
    private static let dust = color(0x9C96BE)
    private static let blade = color(0xFF6FA5)
    private static let handle = color(0xFFD15C)
    private static let grip = color(0xF2A93B)
    private static let sparkle = color(0xFFFFFF)

    /// Draws the full tile so that it fills `rect` (expects a square).
    static func draw(in rect: NSRect) {
        guard let context = NSGraphicsContext.current else { return }
        context.saveGraphicsState()
        defer { context.restoreGraphicsState() }

        let scale = NSAffineTransform()
        scale.translateX(by: rect.minX, yBy: rect.minY)
        scale.scale(by: rect.width / unit)
        scale.concat()

        tile.setFill()
        roundRect(0, 0, unit, unit, 186).fill()

        let screen = drawMonitor()
        drawScreen(screen)
        drawWiper()

        sparkle.setFill()
        star(center: NSPoint(x: 255, y: 545), radius: 70).fill()
        star(center: NSPoint(x: 360, y: 395), radius: 34).fill()
        handle.setFill()
        star(center: NSPoint(x: 150, y: 735), radius: 60).fill()
    }

    /// A vector image of the logo, crisp at any size.
    static func image(size: CGFloat) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            draw(in: rect)
            return true
        }
    }

    /// One-colour version of the logo for the menu bar, drawn on its own small grid so the
    /// lines stay thick enough at 18 pt. It is a template image, so macOS tints it for light
    /// mode, dark mode and the highlighted state.
    static func menuBarImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 20, height: 18), flipped: false) { _ in
            NSColor.black.setFill()

            // Monitor: bezel with the screen cut out, plus the stand.
            let bezel = roundRect(1, 4.5, 15, 11, 2.6)
            bezel.append(roundRect(2.6, 6.1, 11.8, 7.8, 1.1))
            bezel.windingRule = .evenOdd
            bezel.fill()
            roundRect(7.3, 2.6, 2.4, 2.2, 0.4).fill()
            roundRect(5, 1.2, 7, 1.5, 0.75).fill()

            // The still-dusty right side of the screen, lighter than the solid parts.
            if let context = NSGraphicsContext.current {
                context.saveGraphicsState()
                roundRect(2.6, 6.1, 11.8, 7.8, 1.1).addClip()
                NSColor.black.withAlphaComponent(0.38).setFill()
                let dusty = NSBezierPath()
                dusty.move(to: NSPoint(x: 11.9, y: 5))
                dusty.line(to: NSPoint(x: 16, y: 5))
                dusty.line(to: NSPoint(x: 16, y: 15))
                dusty.line(to: NSPoint(x: 10.3, y: 15))
                dusty.close()
                dusty.fill()
                context.restoreGraphicsState()
            }

            // Wiper: blade on the screen with the handle reaching out to the right.
            NSColor.black.setFill()
            rotated(at: NSPoint(x: 11.1, y: 10), degrees: -11) {
                roundRect(-0.95, -4.4, 1.9, 8.8, 0.95).fill()
                roundRect(0, -0.85, 7.6, 1.7, 0.85).fill()
            }

            // Sparkle on the freshly cleaned side.
            star(center: NSPoint(x: 6.2, y: 10), radius: 2.7, pinch: 0.3).fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "KhaiCleanMac"
        return image
    }

    /// White monitor body and stand; returns the screen area inside the bezel.
    private static func drawMonitor() -> NSBezierPath {
        frame.setFill()
        roundRect(355, 200, 90, 90, 8).fill()
        roundRect(270, 168, 260, 46, 23).fill()
        roundRect(110, 270, 580, 390, 50).fill()
        return roundRect(142, 302, 516, 326, 24)
    }

    /// Dusty screen with the already-wiped part (left of the blade) clean and shiny.
    private static func drawScreen(_ screen: NSBezierPath) {
        guard let context = NSGraphicsContext.current else { return }
        context.saveGraphicsState()
        defer { context.restoreGraphicsState() }
        screen.addClip()

        dustyScreen.setFill()
        screen.fill()
        dust.setFill()
        for (x, y) in [(600, 560), (630, 430), (580, 360), (650, 330), (610, 600)] as [(CGFloat, CGFloat)] {
            rotated(at: NSPoint(x: x, y: y), degrees: 30) { roundRect(-22, -7, 44, 14, 7).fill() }
        }

        let wiped = NSBezierPath()
        wiped.move(to: NSPoint(x: 0, y: 0))
        wiped.line(to: NSPoint(x: 548, y: 250))
        wiped.line(to: NSPoint(x: 462, y: 680))
        wiped.line(to: NSPoint(x: 0, y: 800))
        wiped.close()
        wiped.addClip()

        cleanScreen.setFill()
        screen.fill()
        shine.setFill()
        rotated(at: NSPoint(x: 280, y: 470), degrees: -35) { NSBezierPath(rect: NSRect(x: -40, y: -400, width: 80, height: 800)).fill() }
        rotated(at: NSPoint(x: 385, y: 470), degrees: -35) { NSBezierPath(rect: NSRect(x: -16, y: -400, width: 32, height: 800)).fill() }
    }

    /// Squeegee: pink rubber blade on the screen, yellow handle reaching out to the right.
    private static func drawWiper() {
        rotated(at: NSPoint(x: 505, y: 465), degrees: -11) {
            handle.setFill()
            roundRect(10, -32, 300, 64, 32).fill()
            grip.setFill()
            roundRect(200, -32, 110, 64, 32).fill()
            blade.setFill()
            roundRect(-34, -210, 68, 420, 30).fill()
        }
    }

    private static func rotated(at point: NSPoint, degrees: CGFloat, _ body: () -> Void) {
        guard let context = NSGraphicsContext.current else { return }
        context.saveGraphicsState()
        defer { context.restoreGraphicsState() }
        let transform = NSAffineTransform()
        transform.translateX(by: point.x, yBy: point.y)
        transform.rotate(byDegrees: degrees)
        transform.concat()
        body()
    }

    private static func roundRect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat, _ radius: CGFloat) -> NSBezierPath {
        NSBezierPath(roundedRect: NSRect(x: x, y: y, width: width, height: height), xRadius: radius, yRadius: radius)
    }

    /// Four-pointed sparkle with softly pinched sides; a larger `pinch` gives thicker arms.
    private static func star(center c: NSPoint, radius r: CGFloat, pinch pinchRatio: CGFloat = 0.12) -> NSBezierPath {
        let pinch = r * pinchRatio
        let path = NSBezierPath()
        path.move(to: NSPoint(x: c.x, y: c.y + r))
        path.curve(to: NSPoint(x: c.x + r, y: c.y), controlPoint1: NSPoint(x: c.x + pinch, y: c.y + pinch), controlPoint2: NSPoint(x: c.x + pinch, y: c.y + pinch))
        path.curve(to: NSPoint(x: c.x, y: c.y - r), controlPoint1: NSPoint(x: c.x + pinch, y: c.y - pinch), controlPoint2: NSPoint(x: c.x + pinch, y: c.y - pinch))
        path.curve(to: NSPoint(x: c.x - r, y: c.y), controlPoint1: NSPoint(x: c.x - pinch, y: c.y - pinch), controlPoint2: NSPoint(x: c.x - pinch, y: c.y - pinch))
        path.curve(to: NSPoint(x: c.x, y: c.y + r), controlPoint1: NSPoint(x: c.x - pinch, y: c.y + pinch), controlPoint2: NSPoint(x: c.x - pinch, y: c.y + pinch))
        path.close()
        return path
    }

    private static func color(_ hex: UInt32) -> NSColor {
        NSColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
