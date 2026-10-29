// Renders the DMG window background: `background <output.png>`
// 660×400 points at 2x, with an arrow from the app icon to the Applications shortcut and install notes.
// Icon positions must match the layout in make-dmg.sh (app at x 170, Applications at x 490, y 190).
import AppKit

let width: CGFloat = 660, height: CGFloat = 400, scale: CGFloat = 2
guard CommandLine.arguments.count > 1,
      let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(width * scale), pixelsHigh: Int(height * scale),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
      ) else {
    fatalError("usage: background <output.png>")
}
// Point size smaller than pixel size marks the PNG as 144 dpi, so Finder shows it sharp on Retina.
rep.size = NSSize(width: width, height: height)

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// Soft pastel wash, the same family as the app's background.
NSGradient(colors: [color(0xEFFBF7), color(0xF3F1FF), color(0xFFF1F6)])!
    .draw(in: NSRect(x: 0, y: 0, width: width, height: height), angle: -30)
color(0x5EE0C1, 0.16).setFill()
NSBezierPath(roundedRect: NSRect(x: -60, y: 250, width: 300, height: 220), xRadius: 110, yRadius: 110).fill()
color(0xB39BFF, 0.14).setFill()
NSBezierPath(roundedRect: NSRect(x: 440, y: -80, width: 300, height: 220), xRadius: 110, yRadius: 110).fill()

// Arrow between the two icons (Finder y 190 from the top is y 210 from the bottom here).
let arrowY: CGFloat = 210
let shaft = NSBezierPath()
shaft.move(to: NSPoint(x: 262, y: arrowY))
shaft.line(to: NSPoint(x: 384, y: arrowY))
shaft.lineWidth = 10
shaft.lineCapStyle = .round
let head = NSBezierPath()
head.move(to: NSPoint(x: 370, y: arrowY + 22))
head.line(to: NSPoint(x: 396, y: arrowY))
head.line(to: NSPoint(x: 370, y: arrowY - 22))
head.lineWidth = 10
head.lineCapStyle = .round
head.lineJoinStyle = .round
// Paint the gradient only where the arrow is: clip to its stroked outline.
let outline = NSBezierPath(cgPath: shaft.cgPath.copy(strokingWithWidth: 10, lineCap: .round, lineJoin: .round, miterLimit: 10))
outline.append(NSBezierPath(cgPath: head.cgPath.copy(strokingWithWidth: 10, lineCap: .round, lineJoin: .round, miterLimit: 10)))
NSGraphicsContext.current?.saveGraphicsState()
outline.addClip()
NSGradient(colors: [color(0x5EE0C1), color(0x6E9BFF), color(0xB39BFF)])!.draw(in: NSRect(x: 250, y: arrowY - 30, width: 160, height: 60), angle: 0)
NSGraphicsContext.current?.restoreGraphicsState()

func text(_ string: String, size: CGFloat, weight: NSFont.Weight, color textColor: NSColor, y: CGFloat) {
    let font = NSFont.systemFont(ofSize: size, weight: weight)
    let rounded = font.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: size) } ?? font
    let attributed = NSAttributedString(string: string, attributes: [.font: rounded, .foregroundColor: textColor])
    attributed.draw(at: NSPoint(x: (width - attributed.size().width) / 2, y: y))
}

text("KhaiCleanMac  ·  macOS 15+  ·  Apple silicon", size: 12, weight: .semibold, color: color(0x8B7CF6), y: 360)
text("Seret KhaiCleanMac ke folder Applications", size: 17, weight: .bold, color: color(0x2B2F45), y: 84)
text("Drag KhaiCleanMac into the Applications folder to install", size: 12, weight: .medium, color: color(0x6B7080), y: 62)
// The app isn't notarized yet, so the first launch needs Open Anyway (same note as the README).
text("Diblokir saat pertama dibuka? System Settings › Privacy & Security › Open Anyway",
     size: 11, weight: .regular, color: color(0x8A8FA0), y: 22)

NSGraphicsContext.restoreGraphicsState()
try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
