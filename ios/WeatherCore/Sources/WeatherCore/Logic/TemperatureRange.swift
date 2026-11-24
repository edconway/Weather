import Foundation

/// One day's temperatures for `TemperatureRangeGauge`. Celsius only.
/// Display conversion happens later, and only for text.
public struct TemperatureRangeData: Equatable, Sendable {
    public var todayLow: Double
    public var todayHigh: Double
    public var current: Double?
    public var averageLow: Double?
    public var averageHigh: Double?
    /// Shared domain for a list, for example the week's extremes. Unioned with
    /// this row's own values so a stray reading still fits.
    public var scaleOverride: ClosedRange<Double>?

    public init(
        todayLow: Double,
        todayHigh: Double,
        current: Double? = nil,
        averageLow: Double? = nil,
        averageHigh: Double? = nil,
        scaleOverride: ClosedRange<Double>? = nil
    ) {
        self.todayLow = todayLow
        self.todayHigh = todayHigh
        self.current = current
        self.averageLow = averageLow
        self.averageHigh = averageHigh
        self.scaleOverride = scaleOverride
    }

    /// Swaps a low that is above its high. Logs once per distinct pair in debug builds.
    public func normalized() -> TemperatureRangeData {
        var copy = self
        var swapped = false
        if copy.todayLow > copy.todayHigh {
            swap(&copy.todayLow, &copy.todayHigh)
            swapped = true
        }
        if let low = copy.averageLow, let high = copy.averageHigh, low > high {
            copy.averageLow = high
            copy.averageHigh = low
            swapped = true
        }
        if swapped {
            TemperatureRangeLog.inverted(todayLow: todayLow, todayHigh: todayHigh)
        }
        return copy
    }
}

public struct TemperatureGaugeSeed: Equatable, Sendable {
    public var locationID: String
    public var day: String

    public init(locationID: String, day: String) {
        self.locationID = locationID
        self.day = day
    }
}

public struct TemperatureScaleDomain: Equatable, Sendable {
    public var lower: Double
    public var upper: Double

    public var span: Double { max(upper - lower, 0.001) }
}

public enum TemperatureGaugeStyle: Equatable, Sendable {
    case hero
    case row
    case widget

    public var trackHeight: Double {
        switch self {
        case .hero: return 9
        case .row, .widget: return 6
        }
    }

    public var dotDiameter: Double {
        switch self {
        case .hero: return 20
        case .row, .widget: return 14
        }
    }

    /// Handwritten bracket, historic label, and the curved arrow.
    /// The watch Now page uses `.widget` and keeps the notes. A list row does not.
    public var drawsHandwriting: Bool {
        switch self {
        case .hero, .widget: return true
        case .row: return false
        }
    }

    public var drawsValueLabels: Bool {
        switch self {
        case .hero: return true
        case .row, .widget: return false
        }
    }

    var compactNotes: Bool { self == .widget }
}

public struct GaugePoint: Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public struct GaugeRect: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var maxX: Double { x + width }
    public var maxY: Double { y + height }
    public var midX: Double { x + width / 2 }
    public var midY: Double { y + height / 2 }

    public func contains(_ point: GaugePoint) -> Bool {
        point.x >= x && point.x <= maxX && point.y >= y && point.y <= maxY
    }

    public func inset(by amount: Double) -> GaugeRect {
        GaugeRect(x: x - amount, y: y - amount, width: width + amount * 2, height: height + amount * 2)
    }
}

public struct GaugeCubic: Equatable, Sendable {
    public var start: GaugePoint
    public var c1: GaugePoint
    public var c2: GaugePoint
    public var end: GaugePoint

    public init(start: GaugePoint, c1: GaugePoint, c2: GaugePoint, end: GaugePoint) {
        self.start = start
        self.c1 = c1
        self.c2 = c2
        self.end = end
    }

    public func point(t: Double) -> GaugePoint {
        let u = 1 - t
        let x = u * u * u * start.x + 3 * u * u * t * c1.x + 3 * u * t * t * c2.x + t * t * t * end.x
        let y = u * u * u * start.y + 3 * u * u * t * c1.y + 3 * u * t * t * c2.y + t * t * t * end.y
        return GaugePoint(x: x, y: y)
    }

    public func samples(count: Int = 16) -> [GaugePoint] {
        guard count > 1 else { return [start, end] }
        return (0..<count).map { point(t: Double($0) / Double(count - 1)) }
    }
}

public struct GaugeArrowGeometry: Equatable, Sendable {
    public var curves: [GaugeCubic]
    public var tip: GaugePoint
    /// Unit vector at the tip, pointing at the dot.
    public var finalTangent: GaugePoint
    public var chevronLeft: GaugePoint
    public var chevronRight: GaugePoint
    public var label: GaugeRect

    public var samples: [GaugePoint] {
        curves.flatMap { $0.samples() }
    }
}

public struct GaugePlacement: Equatable, Sendable {
    public var domain: TemperatureScaleDomain
    public var inset: Double
    public var usableWidth: Double
    public var barStart: Double
    public var barEnd: Double
    public var barCenterY: Double
    public var trackTop: Double
    public var dot: GaugePoint?
    public var dotRadius: Double
    public var bracketLowX: Double?
    public var bracketHighX: Double?
    public var bracketNarrow: Bool
    public var bracketTop: Double
    public var bracketLegEnd: Double
    public var bracketCurves: [GaugeCubic]
    public var historicLabel: GaugeRect?
    public var lowLabel: GaugeRect?
    public var highLabel: GaugeRect?
    public var combinedLabel: GaugeRect?
    public var arrow: GaugeArrowGeometry?
    public var height: Double
    public var labelRotationDegrees: Double
    public var lowText: String
    public var highText: String
    public var historicText: String?
    public var nowText: String?
}

public enum TemperatureRangeLayout {
    public static let preferredInset: Double = 22
    public static let ringWidth: Double = 3

    public static func domain(for data: TemperatureRangeData) -> TemperatureScaleDomain {
        let data = data.normalized()
        var values = [data.todayLow, data.todayHigh]
        if let current = data.current { values.append(current) }
        if let low = data.averageLow { values.append(low) }
        if let high = data.averageHigh { values.append(high) }
        if let scale = data.scaleOverride {
            values.append(scale.lowerBound)
            values.append(scale.upperBound)
        }
        let minValue = values.min() ?? 0
        let maxValue = values.max() ?? 0
        let pad = max((maxValue - minValue) * 0.10, 2)
        var lower = (minValue - pad).rounded(.down)
        var upper = (maxValue + pad).rounded(.up)
        if upper - lower < 1 {
            lower -= 1
            upper += 1
        }
        return TemperatureScaleDomain(lower: lower, upper: upper)
    }

    /// `x = inset + (t − lower) / (upper − lower) × usableWidth`, clamped to the track.
    public static func x(
        temperature: Double,
        domain: TemperatureScaleDomain,
        inset: Double,
        usableWidth: Double
    ) -> Double {
        let width = max(usableWidth, 0.001)
        let raw = inset + (temperature - domain.lower) / domain.span * width
        return min(inset + width, max(inset, raw))
    }

    /// Inverse of `x(temperature:)`, clamped to the track. Used to colour a
    /// slice of the bar by the temperatures it actually covers.
    public static func temperature(
        atX x: Double,
        domain: TemperatureScaleDomain,
        inset: Double,
        usableWidth: Double
    ) -> Double {
        let width = max(usableWidth, 0.001)
        let fraction = min(1, max(0, (x - inset) / width))
        return domain.lower + fraction * domain.span
    }

    public static func roundedDegrees(_ celsius: Double, unit: UnitTemperature) -> Int {
        let measurement = Measurement(value: celsius, unit: UnitTemperature.celsius).converted(to: unit)
        // swift-corelibs-foundation does not ship MeasurementFormatter. Apple builds
        // format with no decimals and no unit; both paths round half away from zero.
        #if os(Linux)
        return Int(measurement.value.rounded())
        #else
        let formatter = MeasurementFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.unitOptions = .temperatureWithoutUnit
        formatter.unitStyle = .medium
        let numbers = NumberFormatter()
        numbers.locale = Locale(identifier: "en_US_POSIX")
        numbers.maximumFractionDigits = 0
        numbers.minimumFractionDigits = 0
        numbers.roundingMode = .halfUp
        formatter.numberFormatter = numbers
        let text = formatter.string(from: measurement)
        let digits = text.filter { $0.isNumber || $0 == "-" || $0 == "−" }
        let normalized = digits.replacingOccurrences(of: "−", with: "-")
        return Int(normalized) ?? Int(measurement.value.rounded())
        #endif
    }

    public static func degreeLabel(_ celsius: Double, unit: UnitTemperature) -> String {
        "\(roundedDegrees(celsius, unit: unit))°"
    }

    /// One VoiceOver sentence. The comparison uses unrounded Celsius midpoints
    /// and treats a difference of 1°C or less as in line.
    public static func voiceOver(_ data: TemperatureRangeData, unit: UnitTemperature) -> String {
        let data = data.normalized()
        var parts = [
            "Today \(spoken(data.todayLow, unit: unit)) to \(spoken(data.todayHigh, unit: unit))"
        ]
        if let current = data.current {
            parts.append("Now \(spoken(current, unit: unit))")
        }
        if let low = data.averageLow, let high = data.averageHigh {
            parts.append("Historic average \(spoken(low, unit: unit)) to \(spoken(high, unit: unit))")
            let delta = (data.todayLow + data.todayHigh) / 2 - (low + high) / 2
            if delta > 1 {
                parts.append("Warmer than the historic average")
            } else if delta < -1 {
                parts.append("Colder than the historic average")
            } else {
                parts.append("In line with the historic average")
            }
        }
        return parts.joined(separator: ". ") + "."
    }

    public static func labelRotation(seed: TemperatureGaugeSeed) -> Double {
        -2 - unit(seed: seed, salt: 1)
    }

    /// Offsets of 1…2 points, signed. Stable for the same location and date.
    public static func wobble(seed: TemperatureGaugeSeed, count: Int = 6) -> [Double] {
        (0..<count).map { index in
            let sign = unit(seed: seed, salt: UInt64(10 + index)) < 0.5 ? -1.0 : 1.0
            let magnitude = 1 + unit(seed: seed, salt: UInt64(40 + index))
            return sign * magnitude
        }
    }

    public static func placement(
        data: TemperatureRangeData,
        style: TemperatureGaugeStyle,
        unit: UnitTemperature,
        width: Double,
        seed: TemperatureGaugeSeed,
        stackedLabels: Bool,
        allowArrow: Bool = true
    ) -> GaugePlacement {
        let data = data.normalized()
        let domain = domain(for: data)
        let inset = min(preferredInset, max(0, (width - 1) / 2))
        let usable = max(width - inset * 2, 1)
        func map(_ temperature: Double) -> Double {
            x(temperature: temperature, domain: domain, inset: inset, usableWidth: usable)
        }

        let lowText = degreeLabel(data.todayLow, unit: unit)
        let highText = degreeLabel(data.todayHigh, unit: unit)
        let valueSize = 17.0
        let lowX = map(data.todayLow)
        let highX = map(data.todayHigh)
        let bar = barSpan(lowX: lowX, highX: highX, minimum: style.trackHeight, limitStart: inset, limitEnd: inset + usable)
        let hasCurrent = data.current != nil
        let barRow = hasCurrent ? max(style.trackHeight, style.dotDiameter) : style.trackHeight

        var y = 0.0
        let handwriting = style.drawsHandwriting
        let hasAverage = data.averageLow != nil && data.averageHigh != nil
        var historicLabel: GaugeRect?
        var bracketTop = 0.0
        var bracketLegEnd = 0.0
        var bracketLowX: Double?
        var bracketHighX: Double?
        var bracketNarrow = false
        var historicText: String?
        let compact = style.compactNotes
        let markerSize = markerFontSize(for: width, compact: compact)
        let noteHeight = compact ? 16.0 : 26.0
        let bracketSpan = compact ? 14.0 : 24.0
        let nowHeight = compact ? 18.0 : 30.0
        if handwriting, hasAverage, let averageLow = data.averageLow, let averageHigh = data.averageHigh {
            // The phone keeps the historic-average wording. The watch says
            // "typical range" because the usual numbers are already on the line above.
            historicText = compact
                ? "typical range"
                : "historic average \(degreeLabel(averageLow, unit: unit))–\(degreeLabel(averageHigh, unit: unit))"
            let labelWidth = textWidth(historicText ?? "", fontSize: markerSize, handwriting: true)
            let center = slidCenter(
                (map(averageLow) + map(averageHigh)) / 2,
                labelWidth: labelWidth,
                bounds: width)
            historicLabel = GaugeRect(x: center - labelWidth / 2, y: y, width: labelWidth, height: noteHeight)
            y += noteHeight + (compact ? 2 : 4)
            bracketTop = y
            y += bracketSpan
            bracketLowX = map(averageLow)
            bracketHighX = map(averageHigh)
            bracketNarrow = abs((bracketHighX ?? 0) - (bracketLowX ?? 0)) < (compact ? 28 : 40)
        }

        let barCenterY = y + barRow / 2
        let trackTop = barCenterY - style.trackHeight / 2
        if hasAverage, handwriting {
            bracketLegEnd = trackTop - (compact ? 2 : 4)
            bracketTop = bracketLegEnd - bracketSpan
        }
        y += barRow

        var lowLabel: GaugeRect?
        var highLabel: GaugeRect?
        var combinedLabel: GaugeRect?
        if style.drawsValueLabels {
            y += 8
            let lowWidth = textWidth(lowText, fontSize: valueSize, handwriting: false)
            let highWidth = textWidth(highText, fontSize: valueSize, handwriting: false)
            let barWidth = bar.end - bar.start
            let overlap = stackedLabels || barWidth < lowWidth + highWidth + 8
            if overlap {
                let text = "\(lowText)–\(highText)"
                let combinedWidth = textWidth(text, fontSize: valueSize, handwriting: false)
                let center = slidCenter((lowX + highX) / 2, labelWidth: combinedWidth, bounds: width)
                let height = stackedLabels ? 48.0 : 24.0
                combinedLabel = GaugeRect(x: center - combinedWidth / 2, y: y, width: combinedWidth, height: height)
                y += height
            } else {
                lowLabel = labelRect(centerX: lowX, y: y, width: lowWidth, bounds: width)
                highLabel = labelRect(centerX: highX, y: y, width: highWidth, bounds: width)
                y += 24
            }
        }

        let dot: GaugePoint? = data.current.map { GaugePoint(x: map($0), y: barCenterY) }
        var nowText: String?
        var arrow: GaugeArrowGeometry?
        if handwriting, allowArrow, data.current != nil, let dot {
            let phrase = "temperature now"
            let nowWidth = textWidth(phrase, fontSize: markerSize, handwriting: true)
            let outer = style.dotDiameter / 2 + ringWidth
            // The curve lives in a lane under the numbers, or under the ring on
            // the watch, so it can rise to the dot without crossing the words.
            var laneTop = y
            if !style.drawsValueLabels {
                laneTop = max(laneTop, dot.y + outer + 4)
            }
            let laneHeight = compact ? 26.0 : 12.0
            let laneY = laneTop + laneHeight - 6
            let nowRect = nowLabelRect(
                dotX: dot.x, y: laneTop + laneHeight, width: nowWidth, bounds: width, height: nowHeight)
            let obstacles = [lowLabel, highLabel, combinedLabel].compactMap { $0 }
            let barRect = GaugeRect(x: inset, y: trackTop, width: usable, height: style.trackHeight)
            if let built = makeArrow(
                dot: dot,
                outerRadius: outer,
                label: nowRect,
                laneY: laneY,
                obstacles: obstacles,
                bar: barRect,
                bounds: width,
                chevronLength: compact ? 5 : 8) {
                arrow = built
                nowText = phrase
                y = laneTop + laneHeight + nowHeight
            }
        }

        let curves = bracketCurves(
            lowX: bracketLowX,
            highX: bracketHighX,
            top: bracketTop,
            legEnd: bracketLegEnd,
            narrow: bracketNarrow,
            seed: seed)

        return GaugePlacement(
            domain: domain,
            inset: inset,
            usableWidth: usable,
            barStart: bar.start,
            barEnd: bar.end,
            barCenterY: barCenterY,
            trackTop: trackTop,
            dot: dot,
            dotRadius: style.dotDiameter / 2,
            bracketLowX: bracketLowX,
            bracketHighX: bracketHighX,
            bracketNarrow: bracketNarrow,
            bracketTop: bracketTop,
            bracketLegEnd: bracketLegEnd,
            bracketCurves: curves,
            historicLabel: historicLabel,
            lowLabel: lowLabel,
            highLabel: highLabel,
            combinedLabel: combinedLabel,
            arrow: arrow,
            height: max(y, barRow),
            labelRotationDegrees: labelRotation(seed: seed),
            lowText: lowText,
            highText: highText,
            historicText: historicText,
            nowText: arrow == nil ? nil : nowText)
    }

    // MARK: - Pieces

    static func barSpan(
        lowX: Double, highX: Double, minimum: Double, limitStart: Double, limitEnd: Double
    ) -> (start: Double, end: Double) {
        var start = min(lowX, highX)
        var end = max(lowX, highX)
        if end - start < minimum {
            let mid = (start + end) / 2
            start = mid - minimum / 2
            end = mid + minimum / 2
        }
        if start < limitStart {
            end += limitStart - start
            start = limitStart
        }
        if end > limitEnd {
            start -= end - limitEnd
            end = limitEnd
        }
        start = max(limitStart, start)
        end = min(limitEnd, max(start + 1, end))
        return (start, end)
    }

    /// Cursive, large enough to read, small enough that "temperature now"
    /// still leaves a sweep up to the dot. The watch uses the compact size.
    static func markerFontSize(for width: Double, compact: Bool = false) -> Double {
        if compact {
            return min(13, max(11, width / 14))
        }
        let room = max(72, width / 2 - 16)
        // "temperature now": 14 letters at 0.62em and one 0.34em space.
        let emPerPoint = 14 * 0.62 + 0.34
        return min(22, max(16, room / emPerPoint))
    }

    static func textWidth(_ text: String, fontSize: Double, handwriting: Bool) -> Double {
        var width = 0.0
        for character in text {
            if character.isNumber {
                width += handwriting ? fontSize * 0.58 : fontSize * 0.62
            } else if character == " " {
                width += handwriting ? fontSize * 0.36 : fontSize * 0.28
            } else if "°–-−".contains(character) {
                width += handwriting ? fontSize * 0.50 : fontSize * 0.42
            } else {
                width += handwriting ? fontSize * 0.70 : fontSize * 0.56
            }
        }
        return width
    }

    static func slidCenter(_ center: Double, labelWidth: Double, bounds: Double) -> Double {
        let half = labelWidth / 2
        return min(max(center, half), max(half, bounds - half))
    }

    private static func labelRect(centerX: Double, y: Double, width: Double, bounds: Double) -> GaugeRect {
        let x = min(max(0, centerX - width / 2), max(0, bounds - width))
        return GaugeRect(x: x, y: y, width: width, height: 24)
    }

    /// Pins the label to the outer edge of the side that leaves the longer
    /// sweep from its inner edge up to the dot.
    private static func nowLabelRect(
        dotX: Double, y: Double, width: Double, bounds: Double, height: Double
    ) -> GaugeRect {
        let margin = 4.0
        let fitted = min(width, max(1, bounds - margin * 2))
        let rightX = bounds - margin - fitted
        let leftX = margin
        let rightSweep = rightX - dotX
        let leftSweep = dotX - (leftX + fitted)
        let x = rightSweep >= leftSweep ? rightX : leftX
        return GaugeRect(x: x, y: y, width: fitted, height: height)
    }

    private static func bracketCurves(
        lowX: Double?, highX: Double?, top: Double, legEnd: Double, narrow: Bool, seed: TemperatureGaugeSeed
    ) -> [GaugeCubic] {
        guard let lowX, let highX else { return [] }
        let left = min(lowX, highX)
        let right = max(lowX, highX)
        if narrow {
            let x = (left + right) / 2
            return [GaugeCubic(
                start: GaugePoint(x: x, y: legEnd - 10),
                c1: GaugePoint(x: x, y: legEnd - 7),
                c2: GaugePoint(x: x, y: legEnd - 3),
                end: GaugePoint(x: x, y: legEnd))]
        }
        let wobble = wobble(seed: seed)
        return [
            verticalLeg(x: left, top: top, bottom: legEnd, dx1: wobble[0], dx2: wobble[1]),
            horizontalRun(left: left, right: right, y: top, dy1: wobble[2], dy2: wobble[3]),
            verticalLeg(x: right, top: top, bottom: legEnd, dx1: wobble[4], dx2: wobble[5])
        ]
    }

    private static func verticalLeg(
        x: Double, top: Double, bottom: Double, dx1: Double, dx2: Double
    ) -> GaugeCubic {
        let y1 = top + (bottom - top) * 0.35
        let y2 = top + (bottom - top) * 0.7
        return GaugeCubic(
            start: GaugePoint(x: x, y: top),
            c1: GaugePoint(x: x + dx1, y: y1),
            c2: GaugePoint(x: x + dx2, y: y2),
            end: GaugePoint(x: x, y: bottom))
    }

    private static func horizontalRun(
        left: Double, right: Double, y: Double, dy1: Double, dy2: Double
    ) -> GaugeCubic {
        let x1 = left + (right - left) * 0.33
        let x2 = left + (right - left) * 0.66
        return GaugeCubic(
            start: GaugePoint(x: left, y: y),
            c1: GaugePoint(x: x1, y: y + dy1),
            c2: GaugePoint(x: x2, y: y + dy2),
            end: GaugePoint(x: right, y: y))
    }

    private static func makeArrow(
        dot: GaugePoint,
        outerRadius: Double,
        label: GaugeRect,
        laneY: Double,
        obstacles: [GaugeRect],
        bar: GaugeRect,
        bounds: Double,
        chevronLength: Double
    ) -> GaugeArrowGeometry? {
        let labelOnRight = label.midX >= dot.x
        let preferred: Double = labelOnRight ? 1 : -1
        let startX = min(max(labelOnRight ? label.x - 3 : label.maxX + 3, 2), bounds - 2)
        let start = GaugePoint(x: startX, y: laneY)
        let reach = outerRadius + 2.5

        func blocked(_ points: [GaugePoint], tip: GaugePoint) -> Bool {
            if points.dropLast().contains(where: { hypot($0.x - dot.x, $0.y - dot.y) < outerRadius - 0.2 }) {
                return true
            }
            let paddedWords = obstacles + [label]
            if points.contains(where: { point in paddedWords.contains { $0.inset(by: 1.5).contains(point) } }) {
                return true
            }
            if points.contains(where: { bar.inset(by: 1.2).contains($0) }) {
                return true
            }
            if points.contains(where: { $0.x < -2 || $0.x > bounds + 2 }) {
                return true
            }
            // Stay at or below the tip so the stroke cannot climb into the bar.
            if points.contains(where: { $0.y < tip.y - 0.5 }) {
                return true
            }
            return false
        }

        func aimed(_ theta: Double, _ side: Double) -> (tip: GaugePoint, tangent: GaugePoint) {
            let tip = GaugePoint(
                x: dot.x + sin(theta) * reach * side,
                y: dot.y + cos(theta) * reach)
            let towardX = dot.x - tip.x
            let towardY = dot.y - tip.y
            let norm = max(hypot(towardX, towardY), 0.001)
            return (tip, GaugePoint(x: towardX / norm, y: towardY / norm))
        }

        func finish(_ curves: [GaugeCubic], tip: GaugePoint, tangent: GaugePoint) -> GaugeArrowGeometry {
            let head = chevronPoints(tip: tip, tangent: tangent, length: chevronLength)
            return GaugeArrowGeometry(
                curves: curves,
                tip: tip,
                finalTangent: tangent,
                chevronLeft: head.left,
                chevronRight: head.right,
                label: label)
        }

        // One sweep from the words. It stays low, then turns up along a ray
        // that ends on the ring and points at the centre of the dot.
        func sweep(_ theta: Double, _ side: Double, lead: Double) -> GaugeArrowGeometry? {
            let aim = aimed(theta, side)
            let rise = start.y - aim.tip.y
            guard rise >= 8 else { return nil }
            let approach = max(10, min(rise * 0.42, 22))
            let c2 = GaugePoint(
                x: aim.tip.x - aim.tangent.x * approach,
                y: aim.tip.y - aim.tangent.y * approach)
            var c1 = GaugePoint(
                x: start.x + (c2.x - start.x) * lead,
                y: start.y - rise * 0.06)
            if abs(aim.tip.x - start.x) < 28 {
                c1.x += preferred * 12 * (1 - lead)
            }
            let curve = GaugeCubic(start: start, c1: c1, c2: c2, end: aim.tip)
            let points = curve.samples(count: 36)
            guard !blocked(points, tip: aim.tip) else { return nil }
            return finish([curve], tip: aim.tip, tangent: aim.tangent)
        }

        let angles = [0.0, 20.0, 34.0, 48.0, 60.0]
        for degrees in angles {
            let theta = degrees * Double.pi / 180
            let sides: [Double] = degrees == 0 ? [1] : [preferred, -preferred]
            for side in sides {
                for lead in [0.42, 0.62, 0.82] {
                    if let arrow = sweep(theta, side, lead: lead) {
                        return arrow
                    }
                }
            }
        }

        // The sweep crossed a number. Run under the numbers, climb outside
        // them, and turn into the dot.
        func elbow(riseX: Double, degrees: Double, side: Double) -> GaugeArrowGeometry? {
            guard riseX > 4, riseX < bounds - 4 else { return nil }
            let theta = degrees * Double.pi / 180
            let aim = aimed(theta, side)
            let rise = laneY - aim.tip.y
            guard rise >= 8 else { return nil }
            let came: Double = start.x <= riseX ? -1 : 1
            for radius in [34.0, 22, 14, 8] {
                let cornerX = riseX + came * radius
                guard cornerX > 4, cornerX < bounds - 4 else { continue }
                if (cornerX - start.x) * came > 0, abs(start.x - riseX) > 4 { continue }
                let span = cornerX - start.x
                let corner = GaugePoint(x: cornerX, y: laneY)
                let lane = GaugeCubic(
                    start: start,
                    c1: GaugePoint(x: start.x + span * 0.5, y: laneY),
                    c2: GaugePoint(x: cornerX - came * min(10, abs(span) * 0.3), y: laneY),
                    end: corner)
                let approach = max(8, min(radius * 0.7, rise * 0.4))
                let climb = GaugeCubic(
                    start: corner,
                    c1: GaugePoint(x: cornerX + (aim.tip.x - cornerX) * 0.55, y: laneY),
                    c2: GaugePoint(
                        x: aim.tip.x - aim.tangent.x * approach,
                        y: aim.tip.y - aim.tangent.y * approach),
                    end: aim.tip)
                let points = lane.samples(count: 24) + climb.samples(count: 24)
                if !blocked(points, tip: aim.tip) {
                    return finish([lane, climb], tip: aim.tip, tangent: aim.tangent)
                }
            }
            let approach = max(8, min(14, rise * 0.28))
            let span = riseX - start.x
            let lane = GaugeCubic(
                start: start,
                c1: GaugePoint(x: start.x + span * 0.45, y: laneY),
                c2: GaugePoint(x: riseX - came * 6, y: laneY),
                end: GaugePoint(x: riseX, y: laneY))
            let climb = GaugeCubic(
                start: GaugePoint(x: riseX, y: laneY),
                c1: GaugePoint(x: riseX, y: laneY - rise * 0.78),
                c2: GaugePoint(
                    x: aim.tip.x - aim.tangent.x * approach,
                    y: aim.tip.y - aim.tangent.y * approach),
                end: aim.tip)
            let points = lane.samples(count: 24) + climb.samples(count: 24)
            guard !blocked(points, tip: aim.tip) else { return nil }
            return finish([lane, climb], tip: aim.tip, tangent: aim.tangent)
        }

        var edges = [dot.x]
        for rect in obstacles {
            for margin in [8.0, 18, 30, 46] {
                edges.append(rect.x - margin)
                edges.append(rect.maxX + margin)
            }
        }
        edges.sort { lhs, rhs in
            let leftPreferred = (lhs - dot.x) * preferred >= -1
            let rightPreferred = (rhs - dot.x) * preferred >= -1
            if leftPreferred != rightPreferred { return leftPreferred }
            return abs(lhs - dot.x) < abs(rhs - dot.x)
        }
        for riseX in edges {
            for degrees in [0.0, 28, 46, 60] {
                let sides: [Double] = degrees == 0 ? [1] : [preferred, -preferred]
                for side in sides {
                    if let arrow = elbow(riseX: riseX, degrees: degrees, side: side) {
                        return arrow
                    }
                }
            }
        }
        return nil
    }

    private static func chevronPoints(
        tip: GaugePoint, tangent: GaugePoint, length: Double
    ) -> (left: GaugePoint, right: GaugePoint) {
        let angle = 32.0 * Double.pi / 180
        // A small nib. The arms trail back along the curve.
        let back = GaugePoint(x: -tangent.x, y: -tangent.y)
        func arm(_ turn: Double) -> GaugePoint {
            let c = cos(turn)
            let s = sin(turn)
            return GaugePoint(
                x: tip.x + (back.x * c - back.y * s) * length,
                y: tip.y + (back.x * s + back.y * c) * length)
        }
        return (arm(angle), arm(-angle))
    }

    private static func spoken(_ celsius: Double, unit: UnitTemperature) -> String {
        let number = roundedDegrees(celsius, unit: unit)
        if number < 0 { return "minus \(abs(number)) degrees" }
        return "\(number) degrees"
    }

    private static func unit(seed: TemperatureGaugeSeed, salt: UInt64) -> Double {
        var hash: UInt64 = 1469598103934665603
        let text = seed.locationID + "|" + seed.day
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1099511628211
        }
        hash ^= salt &* 0x9E3779B97F4A7C15
        hash ^= hash >> 30
        hash &*= 0xBF58476D1CE4E5B9
        hash ^= hash >> 27
        hash &*= 0x94D049BB133111EB
        hash ^= hash >> 31
        return Double(hash % 10_000) / 9_999
    }
}

private enum TemperatureRangeLog {
    static var seen = Set<String>()

    static func inverted(todayLow: Double, todayHigh: Double) {
        #if DEBUG
        let key = "\(todayLow)|\(todayHigh)"
        if seen.insert(key).inserted {
            fputs("TemperatureRangeData: swapped inverted low and high\n", stderr)
        }
        #endif
    }
}
