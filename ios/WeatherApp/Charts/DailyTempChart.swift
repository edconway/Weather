import Charts
import SwiftUI
import WeatherCore

/// §8.4.2 / §8.4.4 — 14 days of high/low against the grey rolling-normal band.
///
/// The x-axis is **categorical on the date string**, not on `Date`: weekday
/// names repeat across a 14-day window ("Wed" appears twice), and a `Date` axis
/// bins bar/point marks to day boundaries, which pushed the "Today" rule half a
/// slot away from today's data.
struct DailyTempChart: View {
    enum Series {
        case temperature
        case wetBulb

        var eyebrow: String {
            switch self {
            case .temperature: return "14-Day Temperature"
            case .wetBulb: return "14-Day Wet Bulb"
            }
        }

        var accessibilityName: String {
            switch self {
            case .temperature: return "14-day temperature chart"
            case .wetBulb: return "14-day wet bulb chart"
            }
        }
    }

    let points: [ChartSeries.DailyPoint]
    let series: Series
    let formatter: UnitFormatter
    let timeZone: TimeZone
    var detailText: String? = nil
    var onOpenDetail: (() -> Void)? = nil
    var expanded: Bool = false

    @State private var liveSelection: String?
    @State private var selectedDate: String?
    @State private var scrubID = UUID()

    private func high(_ point: ChartSeries.DailyPoint) -> Double? {
        series == .temperature ? point.high : point.wetBulbHigh
    }

    private func low(_ point: ChartSeries.DailyPoint) -> Double? {
        series == .temperature ? point.low : point.wetBulbLow
    }

    private func normalHigh(_ point: ChartSeries.DailyPoint) -> Double? {
        series == .temperature ? point.normal?.tMax : point.normal?.wbMax
    }

    private func normalLow(_ point: ChartSeries.DailyPoint) -> Double? {
        series == .temperature ? point.normal?.tMin : point.normal?.wbMin
    }

    private var todayDateString: String? {
        points.first(where: \.isToday)?.dateString
    }

    private var todayPoint: ChartSeries.DailyPoint? {
        points.first(where: \.isToday)
    }

    private var selected: ChartSeries.DailyPoint? {
        points.first { $0.dateString == selectedDate }
    }

    private var yDomain: ClosedRange<Double> {
        ChartScales.temperatureDomain(
            points.flatMap { point -> [Double?] in
                [high(point), low(point), normalHigh(point), normalLow(point)]
            }
            .map { $0.map(formatter.temperatureValue) })
    }

    private var readout: ChartReadout {
        let point = selected ?? todayPoint ?? points.first
        guard let point else { return .placeholder }
        let highText = formatter.temperatureShort(high(point))
        let lowText = formatter.temperatureShort(low(point))
        let when = selected == nil && point.isToday
            ? "Today"
            : point.label(timeZone: timeZone)
        let tag = point.isPast ? " · actual" : ""

        if let top = normalHigh(point), let bottom = normalLow(point),
           let hi = high(point) {
            let midNormal = (top + bottom) / 2
            let delta = hi - midNormal
            let absDelta = formatter.temperatureShort(abs(delta))
            if abs(delta) <= 0.5 {
                return ChartReadout(
                    primary: "\(highText) / \(lowText)",
                    context: "\(when)\(tag) · near normal")
            }
            let relation = delta > 0 ? "warmer" : "colder"
            return ChartReadout(
                primary: "\(highText) / \(lowText)",
                context: "\(when)\(tag) · \(absDelta) \(relation) than normal")
        }
        return ChartReadout(
            primary: "\(highText) / \(lowText)",
            context: "\(when)\(tag)")
    }

    private var legend: [ChartLegendItem] {
        [
            ChartLegendItem("High", swatch: .solid(Palette.hot)),
            ChartLegendItem("Low", swatch: .solid(Palette.cold)),
            ChartLegendItem("Normal range", swatch: .band(Palette.historical.opacity(0.35))),
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
            ForEach(points) { point in
                if let top = normalHigh(point), let bottom = normalLow(point) {
                    AreaMark(
                        x: .value("Day", point.dateString),
                        yStart: .value("Normal low", formatter.temperatureValue(bottom)),
                        yEnd: .value("Normal high", formatter.temperatureValue(top)))
                    .foregroundStyle(Palette.historical.opacity(ChartKit.normalBandOpacity))
                    .interpolationMethod(.catmullRom)
                }
            }

            if let todayDateString {
                RectangleMark(x: .value("Today", todayDateString))
                    .foregroundStyle(Color.secondary.opacity(0.08))
            }

            ForEach(points) { point in
                if let value = high(point) {
                    LineMark(
                        x: .value("Day", point.dateString),
                        y: .value("High", formatter.temperatureValue(value)),
                        series: .value("Series", "high"))
                    .foregroundStyle(Palette.hot)
                    .interpolationMethod(.catmullRom)
                    .opacity(point.isPast ? ChartKit.pastSeriesOpacity : 1)
                    PointMark(
                        x: .value("Day", point.dateString),
                        y: .value("High", formatter.temperatureValue(value)))
                    .foregroundStyle(Palette.hot)
                    .symbolSize(point.isPast ? 16 : 30)
                    .opacity(point.isPast ? ChartKit.pastSeriesOpacity : 1)
                }
                if let value = low(point) {
                    LineMark(
                        x: .value("Day", point.dateString),
                        y: .value("Low", formatter.temperatureValue(value)),
                        series: .value("Series", "low"))
                    .foregroundStyle(Palette.cold)
                    .interpolationMethod(.catmullRom)
                    .opacity(point.isPast ? ChartKit.pastSeriesOpacity : 1)
                    PointMark(
                        x: .value("Day", point.dateString),
                        y: .value("Low", formatter.temperatureValue(value)))
                    .foregroundStyle(Palette.cold)
                    .symbolSize(point.isPast ? 16 : 30)
                    .opacity(point.isPast ? ChartKit.pastSeriesOpacity : 1)
                }
            }

            if let todayDateString {
                RuleMark(x: .value("Today", todayDateString))
                    .foregroundStyle(.secondary.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .annotation(position: .top, alignment: .center) {
                        NowCapsule(label: "TODAY")
                    }
            }

            if let selected, let hi = high(selected) {
                RuleMark(x: .value("Selected", selected.dateString))
                    .foregroundStyle(Palette.hot.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                PointMark(
                    x: .value("Day", selected.dateString),
                    y: .value("High", formatter.temperatureValue(hi)))
                .foregroundStyle(Palette.hot)
                .symbolSize(70)
            }
        }
        .chartXSelection(value: $liveSelection)
        .chartTapFallback($liveSelection)
        .stickyXSelection(
            id: scrubID, live: $liveSelection, sticky: $selectedDate,
            resetOn: points.first?.dateString ?? "")
        .chartSelectionHaptic(selectedDate)
        .chartXScale(domain: points.map(\.dateString))
        .chartYScale(domain: yDomain)
        .chartYAxis { ChartAxes.temperatureYAxis(formatter: formatter) }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 14)) { value in
                AxisValueLabel {
                    if let dateString = value.as(String.self),
                       let point = points.first(where: { $0.dateString == dateString }),
                       showsLabel(for: point) {
                        Text(point.label(timeZone: timeZone))
                            .font(.caption2.weight(point.isToday ? .bold : .regular))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(height: expanded ? ChartKit.dailyHeight + 60 : ChartKit.dailyHeight)
        .accessibilityLabel(series.accessibilityName)
        .accessibilityChartDescriptor(
            DailyTempChartDescriptor(
                points: points, series: series,
                formatter: formatter, timeZone: timeZone))
    }

    /// 14 weekday labels will not fit; show today plus every other day, which is
    /// what the web does below 480 px. Today's immediate neighbours are dropped
    /// too — otherwise "Tue", "Today" and "Thu" overlap.
    private func showsLabel(for point: ChartSeries.DailyPoint) -> Bool {
        DayLabelDensity.shows(point, in: points)
    }
}
