import AppKit

// App Store icons must be exactly 1024x1024 and fully opaque (no alpha
// channel). Rendering through NSImage's lockFocus() picks up the screen's
// backing scale (2x on Retina) and keeps alpha, so this builds an explicit
// 1x, non-premultiplied-alpha-free bitmap context instead.
let size = 1024

guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: size,
    pixelsHigh: size,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else { fatalError("could not create bitmap") }

guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fatalError("could not create graphics context")
}
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context

let rect = NSRect(x: 0, y: 0, width: size, height: size)

// Opaque background first — this is what makes the final PNG alpha-free.
let accent = NSColor(calibratedRed: 0.40, green: 0.49, blue: 0.92, alpha: 1.0)
let accentDark = NSColor(calibratedRed: 0.22, green: 0.28, blue: 0.62, alpha: 1.0)
NSGradient(starting: accent, ending: accentDark)?.draw(in: NSBezierPath(rect: rect), angle: -90)

if let symbol = NSImage(systemSymbolName: "cloud.sun.fill", accessibilityDescription: nil) {
    let config = NSImage.SymbolConfiguration(pointSize: CGFloat(size) * 0.46, weight: .medium)
        .applying(.init(paletteColors: [.white, .white.withAlphaComponent(0.85)]))
    let configured = symbol.withSymbolConfiguration(config) ?? symbol
    let symbolSize = configured.size
    let origin = NSPoint(
        x: (CGFloat(size) - symbolSize.width) / 2,
        y: (CGFloat(size) - symbolSize.height) / 2 - CGFloat(size) * 0.02)
    configured.draw(at: origin, from: .zero, operation: .sourceOver, fraction: 1.0)
}

NSGraphicsContext.restoreGraphicsState()

// Flatten to a strictly opaque (alpha-free) representation.
guard let cgImage = bitmap.cgImage,
      let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
      let flatContext = CGContext(
        data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
        space: colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
else { fatalError("could not flatten") }
flatContext.draw(cgImage, in: CGRect(x: 0, y: 0, width: size, height: size))
guard let flatImage = flatContext.makeImage() else { fatalError("could not make flat image") }

let flatBitmap = NSBitmapImageRep(cgImage: flatImage)
guard let png = flatBitmap.representation(using: .png, properties: [:]) else {
    fatalError("could not encode png")
}

let outPath = CommandLine.arguments[1]
try png.write(to: URL(fileURLWithPath: outPath))
print("wrote \(outPath): \(flatBitmap.pixelsWide)x\(flatBitmap.pixelsHigh), hasAlpha=\(flatBitmap.hasAlpha)")
