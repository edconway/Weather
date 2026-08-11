import AppKit

let size: CGFloat = 1024

func makeContext() -> (NSBitmapImageRep, NSGraphicsContext) {
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!
    return (bitmap, context)
}

func flatten(_ bitmap: NSBitmapImageRep) -> NSBitmapImageRep {
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    let flatContext = CGContext(
        data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
        space: colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    flatContext.draw(bitmap.cgImage!, in: CGRect(x: 0, y: 0, width: size, height: size))
    return NSBitmapImageRep(cgImage: flatContext.makeImage()!)
}

func background(dark: Bool = false) {
    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    let top = dark
        ? NSColor(calibratedRed: 0.14, green: 0.16, blue: 0.30, alpha: 1)
        : NSColor(calibratedRed: 0.40, green: 0.49, blue: 0.92, alpha: 1)
    let bottom = dark
        ? NSColor(calibratedRed: 0.07, green: 0.08, blue: 0.18, alpha: 1)
        : NSColor(calibratedRed: 0.22, green: 0.28, blue: 0.62, alpha: 1)
    NSGradient(starting: top, ending: bottom)?.draw(in: NSBezierPath(rect: rect), angle: -90)
}

func strokePath(_ points: [CGPoint], width: CGFloat, color: NSColor, dash: [CGFloat]? = nil) {
    let path = NSBezierPath()
    path.lineJoinStyle = .round
    path.lineCapStyle = .round
    path.lineWidth = width
    if let dash {
        path.setLineDash(dash, count: dash.count, phase: 0)
    }
    path.move(to: points[0])
    for point in points.dropFirst() { path.line(to: point) }
    color.setStroke()
    path.stroke()
}

/// Catmull-Rom-ish smoothing so the trend line doesn't look like a stock ticker.
func smooth(_ raw: [CGPoint], samplesPerSegment: Int = 24) -> [CGPoint] {
    guard raw.count > 2 else { return raw }
    var out: [CGPoint] = []
    for i in 0..<(raw.count - 1) {
        let p0 = raw[max(i - 1, 0)]
        let p1 = raw[i]
        let p2 = raw[i + 1]
        let p3 = raw[min(i + 2, raw.count - 1)]
        for s in 0..<samplesPerSegment {
            let t = CGFloat(s) / CGFloat(samplesPerSegment)
            let t2 = t * t, t3 = t2 * t
            let x = 0.5 * ((2 * p1.x) + (-p0.x + p2.x) * t
                + (2 * p0.x - 5 * p1.x + 4 * p2.x - p3.x) * t2
                + (-p0.x + 3 * p1.x - 3 * p2.x + p3.x) * t3)
            let y = 0.5 * ((2 * p1.y) + (-p0.y + p2.y) * t
                + (2 * p0.y - 5 * p1.y + 4 * p2.y - p3.y) * t2
                + (-p0.y + 3 * p1.y - 3 * p2.y + p3.y) * t3)
            out.append(CGPoint(x: x, y: y))
        }
    }
    out.append(raw.last!)
    return out
}

func drawSymbol(_ name: String, pointSize: CGFloat, at origin: CGPoint, color: NSColor) {
    guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return }
    let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
        .applying(.init(paletteColors: [color]))
    let configured = symbol.withSymbolConfiguration(config) ?? symbol
    configured.draw(at: origin, from: .zero, operation: .sourceOver, fraction: 1.0)
}

// MARK: - Candidates

/// A — Trend line: solid past, dashed forecast, with a "now" dot at the join,
/// echoing every chart's actual/forecast convention. A small sun-behind-cloud
/// glyph sits above for weather legibility at a glance.
func candidateA() {
    background()
    let raw: [CGPoint] = [
        CGPoint(x: 90, y: 330), CGPoint(x: 260, y: 500), CGPoint(x: 400, y: 400),
        CGPoint(x: 512, y: 560), CGPoint(x: 640, y: 460), CGPoint(x: 780, y: 620),
        CGPoint(x: 934, y: 540)
    ]
    let curve = smooth(raw)
    let nowIndex = curve.count / 2
    let past = Array(curve[0...nowIndex])
    let future = Array(curve[nowIndex...])

    strokePath(past, width: 34, color: .white)
    strokePath(future, width: 34, color: .white.withAlphaComponent(0.65), dash: [4, 46])

    let now = curve[nowIndex]
    let dot = NSBezierPath(ovalIn: NSRect(x: now.x - 26, y: now.y - 26, width: 52, height: 52))
    NSColor.white.setFill()
    dot.fill()

    drawSymbol("cloud.sun.fill", pointSize: 220, at: CGPoint(x: 700, y: 660), color: .white)
}

/// B — Actual vs. normal: a warm solid line (this year) crossing a cooler
/// dashed line (the historical average) — the anomaly-badge idea distilled to
/// a mark, no weather glyph needed.
func candidateB() {
    background()
    let actual = smooth([
        CGPoint(x: 80, y: 380), CGPoint(x: 300, y: 620), CGPoint(x: 512, y: 480),
        CGPoint(x: 724, y: 700), CGPoint(x: 944, y: 560)
    ])
    let normal = smooth([
        CGPoint(x: 80, y: 480), CGPoint(x: 300, y: 500), CGPoint(x: 512, y: 520),
        CGPoint(x: 724, y: 500), CGPoint(x: 944, y: 480)
    ])
    strokePath(normal, width: 22, color: .white.withAlphaComponent(0.5), dash: [2, 30])
    strokePath(actual, width: 34, color: .white)
}

/// C — Split dial: a circle whose left arc is solid (the record) and right arc
/// is dashed (the forecast), a small tick at 12 o'clock marking "now", with a
/// compact sun/cloud glyph centred. Reads well even at complication scale.
func candidateC() {
    background()
    let center = CGPoint(x: size / 2, y: size / 2)
    let radius: CGFloat = 380
    let ringRect = NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)

    let solidArc = NSBezierPath()
    solidArc.appendArc(withCenter: center, radius: radius, startAngle: 90, endAngle: 270, clockwise: false)
    solidArc.lineWidth = 40
    solidArc.lineCapStyle = .round
    NSColor.white.setStroke()
    solidArc.stroke()

    let dashedArc = NSBezierPath()
    dashedArc.appendArc(withCenter: center, radius: radius, startAngle: -90, endAngle: 90, clockwise: false)
    dashedArc.lineWidth = 40
    dashedArc.lineCapStyle = .round
    dashedArc.setLineDash([4, 44], count: 2, phase: 0)
    NSColor.white.withAlphaComponent(0.65).setStroke()
    dashedArc.stroke()
    _ = ringRect

    drawSymbol("cloud.sun.fill", pointSize: 300, at: CGPoint(x: center.x - 150, y: center.y - 150), color: .white)
}

/// D — Minimal sparkline only, no glyph: the boldest, simplest read at 16pt.
func candidateD() {
    background()
    let raw: [CGPoint] = [
        CGPoint(x: 70, y: 420), CGPoint(x: 280, y: 640), CGPoint(x: 512, y: 500),
        CGPoint(x: 760, y: 700), CGPoint(x: 954, y: 560)
    ]
    let curve = smooth(raw)
    let nowIndex = Int(Double(curve.count) * 0.55)
    strokePath(Array(curve[0...nowIndex]), width: 46, color: .white)
    strokePath(Array(curve[nowIndex...]), width: 46, color: .white.withAlphaComponent(0.6), dash: [4, 54])
    let now = curve[nowIndex]
    NSColor.white.setFill()
    NSBezierPath(ovalIn: NSRect(x: now.x - 32, y: now.y - 32, width: 64, height: 64)).fill()
}

let candidates: [(String, () -> Void)] = [
    ("A-trendline-sun", candidateA),
    ("B-actual-vs-normal", candidateB),
    ("C-split-dial", candidateC),
    ("D-sparkline-minimal", candidateD)
]

let outDir = CommandLine.arguments[1]
for (name, draw) in candidates {
    let (bitmap, context) = makeContext()
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    draw()
    NSGraphicsContext.restoreGraphicsState()
    let flat = flatten(bitmap)
    let png = flat.representation(using: .png, properties: [:])!
    let path = "\(outDir)/icon-\(name).png"
    try png.write(to: URL(fileURLWithPath: path))
    print("wrote \(path)")
}
