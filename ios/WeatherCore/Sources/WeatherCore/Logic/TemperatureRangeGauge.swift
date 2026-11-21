import SwiftUI

/// Today's low–high as a colour bar, with the historic average in a felt-tip
/// bracket and the current temperature marked by a curved arrow.
public struct TemperatureRangeGauge: View {
    public var data: TemperatureRangeData
    public var style: TemperatureGaugeStyle
    public var unit: UnitTemperature
    public var weatherBackground: Color
    public var ink: Ink
    public var seed: TemperatureGaugeSeed

    public init(
        data: TemperatureRangeData,
        style: TemperatureGaugeStyle = .hero,
        unit: UnitTemperature = .celsius,
        weatherBackground: Color,
        ink: Ink = .chalk,
        seed: TemperatureGaugeSeed = TemperatureGaugeSeed(locationID: "", day: "")
    ) {
        self.data = data
        self.style = style
        self.unit = unit
        self.weatherBackground = weatherBackground
        self.ink = ink
        self.seed = seed
    }

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.gaugeIncreasedContrast) private var gaugeIncreasedContrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.gaugePreviewReduceMotion) private var gaugePreviewReduceMotion
    @State private var width: CGFloat = 320
    @State private var grown = true
    @State private var inkTrim: CGFloat = 1

    public enum Ink: Equatable {
        case chalk
        case highlighter

        var color: Color {
            switch self {
            case .chalk: return .white
            case .highlighter: return Color(red: 0xD6 / 255, green: 0xF2 / 255, blue: 0x5C / 255)
            }
        }
    }

    public var body: some View {
        let placement = TemperatureRangeLayout.placement(
            data: data,
            style: style,
            unit: unit,
            width: width,
            seed: seed,
            stackedLabels: dynamicTypeSize.isAccessibilitySize,
            allowArrow: style == .hero && !dynamicTypeSize.isAccessibilitySize)
        canvas(placement)
            .frame(maxWidth: .infinity)
            .frame(height: placement.height)
            .background {
                GeometryReader { geo in
                    Color.clear.preference(key: GaugeWidthKey.self, value: geo.size.width)
                }
            }
            .onPreferenceChange(GaugeWidthKey.self) { width = max($0, 1) }
            .onAppear { playIntro() }
            .onChange(of: seed) { _, _ in playIntro() }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(TemperatureRangeLayout.voiceOver(data, unit: unit))
    }

    private var strongContrast: Bool { contrast == .increased || gaugeIncreasedContrast }

    private var suppressesMotion: Bool { reduceMotion || gaugePreviewReduceMotion }

    private func markerFont(width: Double) -> Font {
        Font.custom(
            "Permanent Marker",
            size: TemperatureRangeLayout.markerFontSize(for: width),
            relativeTo: .callout)
    }

    private func canvas(_ placement: GaugePlacement) -> some View {
        let trackOpacity = strongContrast ? 0.30 : 0.16
        let markerStroke = style.drawsHandwriting
        let dash: [CGFloat] = markerStroke || strongContrast ? [] : [6, 5]
        let stroke: CGFloat = markerStroke ? (strongContrast ? 6 : 5) : (strongContrast ? 3 : 2.2)
        let shown = grown ? (placement.barEnd - placement.barStart) : 0
        let shownStart = (placement.barStart + placement.barEnd) / 2 - shown / 2
        return ZStack(alignment: .topLeading) {
            Capsule()
                .fill(Color.white.opacity(trackOpacity))
                .frame(width: placement.usableWidth, height: style.trackHeight)
                .offset(x: placement.inset, y: placement.trackTop)

            LinearGradient(stops: gradient(placement), startPoint: .leading, endPoint: .trailing)
                .frame(width: placement.usableWidth, height: style.trackHeight)
                .offset(x: placement.inset, y: placement.trackTop)
                .mask(alignment: .topLeading) {
                    Capsule()
                        .frame(width: max(shown, 0), height: style.trackHeight)
                        .offset(x: shownStart - placement.inset)
                }

            if let dot = placement.dot {
                dotMark
                    .position(x: dot.x, y: dot.y)
                    .animation(animatesDot ? .spring(duration: 0.45) : nil, value: dot.x)
            }

            GaugeAnnotations(
                placement: placement,
                ink: ink.color,
                hand: style.drawsHandwriting ? markerFont(width: Double(width)) : .body,
                dash: dash,
                stroke: stroke,
                trim: inkTrim)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var dotMark: some View {
        ZStack {
            Circle()
                .fill(weatherBackground)
                .frame(width: style.dotDiameter + TemperatureRangeLayout.ringWidth * 2,
                       height: style.dotDiameter + TemperatureRangeLayout.ringWidth * 2)
            Circle()
                .fill(Color.white)
                .frame(width: style.dotDiameter, height: style.dotDiameter)
        }
    }

    private var animatesDot: Bool {
        style != .widget && !suppressesMotion
    }

    private func gradient(_ placement: GaugePlacement) -> [Gradient.Stop] {
        TemperatureColorScale.gradientStops(domain: placement.domain).map { stop in
            Gradient.Stop(
                color: Color(red: stop.color.red, green: stop.color.green, blue: stop.color.blue),
                location: stop.location)
        }
    }

    private func playIntro() {
        let skip = suppressesMotion || style == .widget || UserDefaults.standard.bool(forKey: playedKey)
        if skip {
            grown = true
            inkTrim = 1
            return
        }
        var reset = Transaction()
        reset.disablesAnimations = true
        withTransaction(reset) {
            grown = false
            inkTrim = 0
        }
        withAnimation(.spring(duration: 0.4)) { grown = true }
        withAnimation(.easeInOut(duration: 0.5).delay(0.4)) { inkTrim = 1 }
        UserDefaults.standard.set(true, forKey: playedKey)
    }

    private var playedKey: String {
        "temperatureRangeGauge.intro.\(seed.locationID).\(seed.day)"
    }
}

/// Felt-tip historic label, bracket, and the curved current-temperature arrow.
struct GaugeAnnotations: View {
    let placement: GaugePlacement
    let ink: Color
    let hand: Font
    let dash: [CGFloat]
    let stroke: CGFloat
    let trim: CGFloat

    var body: some View {
        ZStack(alignment: .topLeading) {
            if !placement.bracketCurves.isEmpty {
                GaugeCurves(curves: placement.bracketCurves)
                    .trim(from: 0, to: trim)
                    .stroke(
                        ink,
                        style: StrokeStyle(lineWidth: stroke, lineCap: .round, lineJoin: .round, dash: dash))
            }
            if let label = placement.historicLabel, let text = placement.historicText {
                handwritten(text, in: label)
            }
            if let arrow = placement.arrow {
                GaugeCurves(curves: arrow.curves)
                    .trim(from: 0, to: trim)
                    .stroke(
                        ink,
                        style: StrokeStyle(lineWidth: stroke, lineCap: .round, lineJoin: .round, dash: dash))
                GaugeChevron(a: arrow.tip, b: arrow.chevronLeft, c: arrow.chevronRight)
                    .stroke(ink, style: StrokeStyle(lineWidth: stroke, lineCap: .round, lineJoin: .round))
                    .opacity(trim > 0.95 ? 1 : 0)
                if let text = placement.nowText {
                    handwritten(text, in: arrow.label)
                }
            }
            valueLabels
        }
    }

    @ViewBuilder
    private var valueLabels: some View {
        if let combined = placement.combinedLabel {
            value("\(placement.lowText)–\(placement.highText)", in: combined)
        } else {
            if let low = placement.lowLabel {
                value(placement.lowText, in: low)
            }
            if let high = placement.highLabel {
                value(placement.highText, in: high)
            }
        }
    }

    private func handwritten(_ text: String, in rect: GaugeRect) -> some View {
        Text(text)
            .font(hand)
            .foregroundStyle(ink)
            .fixedSize()
            .position(x: rect.midX, y: rect.midY)
    }

    private func value(_ text: String, in rect: GaugeRect) -> some View {
        Text(text)
            .font(.body.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(ink)
            .position(x: rect.midX, y: rect.midY)
    }
}

struct GaugeCurves: Shape {
    var curves: [GaugeCubic]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for curve in curves {
            path.move(to: CGPoint(x: curve.start.x, y: curve.start.y))
            path.addCurve(
                to: CGPoint(x: curve.end.x, y: curve.end.y),
                control1: CGPoint(x: curve.c1.x, y: curve.c1.y),
                control2: CGPoint(x: curve.c2.x, y: curve.c2.y))
        }
        return path
    }
}

struct GaugeChevron: Shape {
    var a: GaugePoint
    var b: GaugePoint
    var c: GaugePoint

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: b.x, y: b.y))
        path.addLine(to: CGPoint(x: a.x, y: a.y))
        path.addLine(to: CGPoint(x: c.x, y: c.y))
        return path
    }
}

/// Preview-only switch. `colorSchemeContrast` is read-only, so the gallery
/// cannot write it. The gauge still honours the system value.
private struct GaugeIncreasedContrastKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var gaugeIncreasedContrast: Bool {
        get { self[GaugeIncreasedContrastKey.self] }
        set { self[GaugeIncreasedContrastKey.self] = newValue }
    }
}

/// Preview-only switch. `accessibilityReduceMotion` is read-only, so the gallery
/// cannot write it. The gauge still honours the system value.
private struct GaugePreviewReduceMotionKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var gaugePreviewReduceMotion: Bool {
        get { self[GaugePreviewReduceMotionKey.self] }
        set { self[GaugePreviewReduceMotionKey.self] = newValue }
    }
}

private struct GaugeWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 320
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

#Preview("Temperature range gauge") {
    TemperatureRangeGallery()
}

/// Every edge case from the gauge spec, on a darkened weather background.
struct TemperatureRangeGallery: View {
    private let darkened = Color(red: 0x1B / 255, green: 0x24 / 255, blue: 0x33 / 255)
    private let midBlue = Color(red: 0x3F / 255, green: 0x72 / 255, blue: 0xB5 / 255)
    private let seed = TemperatureGaugeSeed(locationID: "london", day: "2026-11-15")

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                card("Today inside the average", background: darkened, data: .init(
                    todayLow: 7, todayHigh: 10, current: 8, averageLow: 5, averageHigh: 12))
                card("Today wholly colder", background: darkened, data: .init(
                    todayLow: -4, todayHigh: 2, current: 0, averageLow: 6, averageHigh: 12))
                card("Today wholly warmer", background: darkened, data: .init(
                    todayLow: 24, todayHigh: 31, current: 27, averageLow: 14, averageHigh: 20))
                card("Shared end", background: darkened, data: .init(
                    todayLow: 3, todayHigh: 12, current: 8, averageLow: 6, averageHigh: 12))
                card("Very narrow range", background: darkened, data: .init(
                    todayLow: 9, todayHigh: 9.5, current: 9.2, averageLow: 8, averageHigh: 11))
                card("Current outside today's range", background: darkened, data: .init(
                    todayLow: 3, todayHigh: 12, current: 13, averageLow: 6, averageHigh: 12))
                card("No current temperature", background: darkened, data: .init(
                    todayLow: 7, todayHigh: 14, current: nil, averageLow: 6, averageHigh: 13))
                card("No historic average", background: darkened, data: .init(
                    todayLow: 4, todayHigh: 11, current: 7))
                card("Inverted input", background: darkened, data: .init(
                    todayLow: 12, todayHigh: 3, current: 8, averageLow: 12, averageHigh: 6))
                card("Extreme values", background: darkened, data: .init(
                    todayLow: -40, todayHigh: 50, current: 10, averageLow: 0, averageHigh: 15))
                card("Fahrenheit", background: darkened, unit: .fahrenheit, data: .init(
                    todayLow: 7, todayHigh: 10, current: 8, averageLow: 5, averageHigh: 12))
                card("Mid blue, chalk", background: midBlue, data: .init(
                    todayLow: 2, todayHigh: 8, current: 3, averageLow: 4, averageHigh: 12))
                card("Highlighter", background: darkened, ink: .highlighter, data: .init(
                    todayLow: 16, todayHigh: 24, current: 21, averageLow: 14, averageHigh: 20))
                card("List row", background: darkened, style: .row, data: .init(
                    todayLow: 7, todayHigh: 10, current: 8, averageLow: 5, averageHigh: 12,
                    scaleOverride: 0...30))
                card("Widget", background: darkened, style: .widget, data: .init(
                    todayLow: 7, todayHigh: 10, current: 8, averageLow: 5, averageHigh: 12))
                card("Increase contrast", background: darkened, data: .init(
                    todayLow: 7, todayHigh: 10, current: 8, averageLow: 5, averageHigh: 12))
                .environment(\.gaugeIncreasedContrast, true)
                card("Reduce motion", background: darkened, data: .init(
                    todayLow: 7, todayHigh: 10, current: 8, averageLow: 5, averageHigh: 12))
                .environment(\.gaugePreviewReduceMotion, true)
            }
            .padding(16)
        }
        .background(Color.black)
    }

    private func card(
        _ title: String,
        background: Color,
        style: TemperatureGaugeStyle = .hero,
        unit: UnitTemperature = .celsius,
        ink: TemperatureRangeGauge.Ink = .chalk,
        data: TemperatureRangeData
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.7))
            TemperatureRangeGauge(
                data: data, style: style, unit: unit, weatherBackground: background, ink: ink, seed: seed)
        }
        .padding(16)
        .background(background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
