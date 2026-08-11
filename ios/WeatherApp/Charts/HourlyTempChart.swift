import Charts
import SwiftUI
import WeatherCore

/// §8.4.1 / §8.4.3 — up to 48 hourly points (±24 h around now) of temperature
/// (or wet bulb) against the 5-year average for that hour of day.
struct HourlyTempChart: View {
    enum Series {
        case temperature
        case wetBulb

        var scrubLabel: String {
            switch self {
            case .temperature: return "Temp"
            case .wetBulb: return "Wet bulb"
            }
        }

        var eyebrow: String {
            switch self {
            case .temperature: return "48-Hour Temperature"
            case .wetBulb: return "48-Hour Wet Bulb"
            }
        }

        var accessibilityName: String {
            switch self {
            case .temperature: return "48-hour temperature chart"
            case .wetBulb: return "48-hour wet bulb chart"
            }
        }

        var legendLabel: String {
            switch self {
            case .temperature: return "Temperature"
            case .wetBulb: return "Wet bulb"
            }
        }
    }

    let points: [ChartSeries.HourlyPoint]
    let series: Series
    let formatter: UnitFormatter
    let timeZone: TimeZone
    var detailText: String? = nil
    var onOpenDetail: (() -> Void)? = nil
    /// When true, the plot is taller (detail sheet).
    var expanded: Bool = false

    @State private var liveSelection: Date?
    @State private var selectedDate: Date?
    @State private var scrubID = UUID()

    private func value(_ point: ChartSeries.HourlyPoint) -> Double? {
        switch series {
        case .temperature: return point.temperature
        case .wetBulb: return point.wetBulb
        }
    }

    private func normal(_ point: ChartSeries.HourlyPoint) -> Double? {
        switch series {
        case .temperature: return point.normalTemperature
        case .wetBulb: return point.normalWetBulb
        }
    }

    private var tint: Color {
        series == .temperature ? Palette.hot : Palette.wetBulb
    }

    private var nowDate: Date? {
        points.first(where: { !$0.isPast })?.date
    }

    private var nowPoint: ChartSeries.HourlyPoint? {
        points.first(where: { !$0.isPast })
    }

    private var selected: ChartSeries.HourlyPoint? {
        guard let selectedDate else { return nil }
        return points.min {
            abs($0.date.timeIntervalSince(selectedDate))
                < abs($1.date.timeIntervalSince(selectedDate))
        }
    }

    private var yDomain: ClosedRange<Double> {
        ChartScales.temperatureDomain(
            points.flatMap { [value($0), normal($0)] }
                .map { $0.map(formatter.temperatureValue) })
    }

    private var nightRanges: [NightRange] {
        NightShading.ranges(in: points)
    }

    private var readout: ChartReadout {
        let point = selected ?? nowPoint
        guard let point, let value = value(point) else {
            return .placeholder
        }
        let primary = formatter.temperatureShort(value)
        let when: String
        if selected == nil || point.date == nowDate {
            when = "Now"
        } else {
            let day = point.date.formatted(
                Date.FormatStyle().weekday(.abbreviated).hour(.defaultDigits(amPM: .abbreviated)),
                in: timeZone)
            when = day
        }
        let tag = point.isPast ? " · actual" : (selected == nil ? "" : " · forecast")
        if let normal = normal(point) {
            let delta = value - normal
            let absDelta = formatter.temperatureShort(abs(delta))
            let relation = delta > 0.05 ? "above" : (delta < -0.05 ? "below" : "near")
            if abs(delta) <= 0.05 {
                return ChartReadout(
                    primary: primary,
                    context: "\(when)\(tag) · near the 5-yr average",
                    primaryTint: tint)
            }
            return ChartReadout(
                primary: primary,
                context: "\(when)\(tag) · \(absDelta) \(relation) 5-yr avg",
                primaryTint: tint)
        }
        return ChartReadout(primary: primary, context: "\(when)\(tag)", primaryTint: tint)
    }

    private var legend: [ChartLegendItem] {
        [
            ChartLegendItem(series.legendLabel, swatch: .solid(tint)),
            ChartLegendItem("5-yr average", swatch: .dashed(Palette.historical)),
        ]
    }

    var body: some View {
        ChartModule(
            eyebrow: series.eyebrow,
            readout: readout,
            detailText: detailText,
            legend: legend,
            onOpenDetail: onOpenDetail
        ) {
            plot
        }
    }

    private var plot: some View {
        Chart {
            ForEach(nightRanges) { range in
                RectangleMark(
                    xStart: .value("Night start", range.start),
                    xEnd: .value("Night end", range.end))
                .foregroundStyle(Color.secondary.opacity(ChartKit.nightShadeOpacity))
            }

            ForEach(points) { point in
                if let value = value(point), point.isPast {
                    LineMark(
                        x: .value("Time", point.date),
                        y: .value(series.scrubLabel, formatter.temperatureValue(value)),
                        series: .value("Series", "actual"))
                    .foregroundStyle(tint)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .interpolationMethod(.catmullRom)
                }
            }
            ForEach(points) { point in
                if let value = value(point), !point.isPast || isLastPast(point) {
                    LineMark(
                        x: .value("Time", point.date),
                        y: .value(series.scrubLabel, formatter.temperatureValue(value)),
                        series: .value("Series", "forecast"))
                    .foregroundStyle(tint)
                    .lineStyle(StrokeStyle(lineWidth: 2, dash: ChartKit.forecastDash))
                    .interpolationMethod(.catmullRom)
                }
            }
            ForEach(points) { point in
                if let normal = normal(point) {
                    LineMark(
                        x: .value("Time", point.date),
                        y: .value("Normal", formatter.temperatureValue(normal)),
                        series: .value("Series", "normal"))
                    .foregroundStyle(Palette.historical.opacity(0.55))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: ChartKit.historicalDash))
                    .interpolationMethod(.catmullRom)
                }
            }

            if let nowDate {
                RuleMark(x: .value("Now", nowDate))
                    .foregroundStyle(.secondary.opacity(0.45))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .annotation(position: .top, alignment: .center) {
                        NowCapsule()
                    }
            }

            if let selected, let value = value(selected) {
                RuleMark(x: .value("Selected", selected.date))
                    .foregroundStyle(tint.opacity(0.45))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                PointMark(
                    x: .value("Time", selected.date),
                    y: .value(series.scrubLabel, formatter.temperatureValue(value)))
                .foregroundStyle(tint)
                .symbolSize(70)
                .annotation(position: .overlay) {
                    Circle()
                        .strokeBorder(Color(.systemBackground), lineWidth: 2)
                        .frame(width: 10, height: 10)
                }
            }
        }
        .chartXSelection(value: $liveSelection)
        .chartTapFallback($liveSelection)
        .stickyXSelection(
            id: scrubID, live: $liveSelection, sticky: $selectedDate,
            resetOn: points.first?.timeString ?? "")
        .chartSelectionHaptic(selectedDate)
        .chartYScale(domain: yDomain)
        .chartYAxis { ChartAxes.temperatureYAxis(formatter: formatter) }
        .chartXAxis { ChartAxes.hourlyXAxis(timeZone: timeZone) }
        .frame(height: expanded ? ChartKit.hourlyHeight + 60 : ChartKit.hourlyHeight)
        .accessibilityLabel(series.accessibilityName)
        .accessibilityChartDescriptor(
            HourlyTempChartDescriptor(
                points: points, series: series, formatter: formatter))
    }

    private func isLastPast(_ point: ChartSeries.HourlyPoint) -> Bool {
        guard let firstFuture = points.firstIndex(where: { !$0.isPast }), firstFuture > 0
        else { return false }
        return point.id == points[firstFuture - 1].id
    }
}

extension Calendar {
    static func hour(of date: Date, in timeZone: TimeZone) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.component(.hour, from: date)
    }
}
