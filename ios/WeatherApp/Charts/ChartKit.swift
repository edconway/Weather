import Charts
import SwiftUI
import WeatherCore

/// Shared chart conventions for the native Health-style presentation.
enum ChartKit {
    static let hourlyHeight: CGFloat = 200
    static let dailyHeight: CGFloat = 210
    static let ytdHeight: CGFloat = 220
    static let climateTempHeight: CGFloat = 150
    static let climateRainHeight: CGFloat = 90

    /// Dash pattern used for every "forecast" segment.
    static let forecastDash: [CGFloat] = [5, 4]
    /// Dash pattern for historical overlays.
    static let historicalDash: [CGFloat] = [4, 3]

    static let nightShadeOpacity: Double = 0.05
    static let normalBandOpacity: Double = 0.14
    static let pastSeriesOpacity: Double = 0.4
}

/// A contiguous night span for `RectangleMark` shading.
struct NightRange: Identifiable, Equatable {
    let id: Int
    let start: Date
    let end: Date
}

enum NightShading {
    /// Collapse consecutive `!isDay` hourly points into shaded spans.
    static func ranges(in points: [ChartSeries.HourlyPoint]) -> [NightRange] {
        var result: [NightRange] = []
        var runStart: Date?
        var runEnd: Date?
        var index = 0

        func flush() {
            guard let start = runStart, let end = runEnd else { return }
            result.append(NightRange(id: index, start: start, end: end))
            index += 1
            runStart = nil
            runEnd = nil
        }

        for point in points {
            if !point.isDay {
                if runStart == nil {
                    runStart = point.date
                }
                // Extend half an hour past the hour so adjacent night hours join.
                runEnd = point.date.addingTimeInterval(30 * 60)
            } else {
                flush()
            }
        }
        flush()
        return result
    }
}

/// Shared axis styling — hairline dotted grids, leading Y axis, sparse labels.
enum ChartAxes {
    static func temperatureYAxis(formatter: UnitFormatter) -> some AxisContent {
        AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                .foregroundStyle(Color.secondary.opacity(0.18))
            AxisValueLabel {
                if let number = value.as(Double.self) {
                    Text(formatter.temperatureAxis(number))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    static func precipitationYAxis(formatter: UnitFormatter) -> some AxisContent {
        AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                .foregroundStyle(Color.secondary.opacity(0.18))
            AxisValueLabel {
                if let number = value.as(Double.self) {
                    Text(formatter.precipitationAxis(displayValue: number))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    static func hourlyXAxis(timeZone: TimeZone) -> some AxisContent {
        AxisMarks(values: .stride(by: .hour, count: 12)) { value in
            AxisValueLabel {
                if let date = value.as(Date.self) {
                    Text(hourLabel(Calendar.hour(of: date, in: timeZone)))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// Capsule annotation used for the "NOW" / "TODAY" marker.
struct NowCapsule: View {
    var label: String = "NOW"

    var body: some View {
        Text(label)
            .font(.system(size: 8, weight: .bold))
            .tracking(0.3)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(.background.secondary, in: Capsule())
    }
}

extension ChartContent {
    /// Positions a scrub annotation without letting it run off the plot area.
    /// Kept for the climate / detail-sheet cases that still need an overlay.
    func scrubAnnotation<Content: View>(
        @ViewBuilder content: @escaping () -> Content
    ) -> some ChartContent {
        annotation(
            position: .top,
            spacing: 2,
            overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))
        ) {
            content()
        }
    }
}

/// One row of a scrub annotation (detail sheet / legacy).
struct ScrubRow: View {
    let label: String
    let value: String
    var tint: Color = .primary

    var body: some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(tint)
        }
    }
}

/// The floating card shown while scrubbing (detail sheet only).
struct ScrubCard<Content: View>: View {
    let title: String
    /// " · actual" / " · forecast", matching the web's tooltip tags.
    let tag: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 0) {
                Text(title).font(.caption2.weight(.bold))
                if let tag {
                    Text(" · \(tag)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            content
        }
        .padding(8)
        .frame(minWidth: 130, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .shadow(radius: 3, y: 1)
        .padding(.horizontal, 4)
    }
}

/// Hour label matching the web's `_hourLbl`: "Midnight", "Noon", "3am", "5pm".
func hourLabel(_ hour: Int) -> String {
    switch hour {
    case 0: return "Midnight"
    case 12: return "Noon"
    case ..<12: return "\(hour)am"
    default: return "\(hour - 12)pm"
    }
}

extension Date {
    func formatted(_ style: Date.FormatStyle, in timeZone: TimeZone) -> String {
        var copy = style
        copy.timeZone = timeZone
        return formatted(copy)
    }
}

extension View {
    /// `chartXSelection`'s built-in gesture doesn't reliably pick up every
    /// tap (the same unreliability documented for the watchOS charts); this
    /// explicit tap handler is a belt-and-braces fallback so scrubbing works
    /// regardless of the underlying gesture recognizer.
    func chartTapFallback<Value: Plottable>(_ selection: Binding<Value?>) -> some View {
        chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .onTapGesture { location in
                        // `plotFrame` can be nil during the first layout pass;
                        // force-unwrapping here crashed the app on device.
                        guard let plotFrame = proxy.plotFrame else { return }
                        let origin = geo[plotFrame].origin
                        let x = location.x - origin.x
                        if let value: Value = proxy.value(atX: x) {
                            selection.wrappedValue = value
                        }
                    }
            }
        }
    }

    /// Selection haptic when the sticky scrub value changes.
    func chartSelectionHaptic<Value: Equatable>(_ selection: Value?) -> some View {
        sensoryFeedback(.selection, trigger: selection)
    }
}
