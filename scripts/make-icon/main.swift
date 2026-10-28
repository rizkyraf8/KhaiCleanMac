// Renders the 1024px app icon from LogoArtwork: `make-icon <output.png>`
// Compiled together with Sources/KhaiCleanMac/Design/LogoArtwork.swift by build-app.sh.
import AppKit

let canvas = 1024
guard CommandLine.arguments.count > 1,
      let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: canvas, pixelsHigh: canvas,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
      ) else {
    fatalError("usage: make-icon <output.png>")
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
// macOS icon grid: 824px body centred on the 1024 canvas.
LogoArtwork.draw(in: NSRect(x: 100, y: 100, width: 824, height: 824))
NSGraphicsContext.restoreGraphicsState()

let png = rep.representation(using: .png, properties: [:])!
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
