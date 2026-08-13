import Charts
import SwiftUI
import WeatherCore

/// 14 days of high/low against the grey rolling-normal band.
///
/// Grammar matches `makeTempChart` in charts.js: past dashed/ghosted, forecast
/// solid with degree labels, "Hist. avg" sitting in the band, High/Low at the
/// right edge. Categorical x on the date string so weekday names don't collide.
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

    private var highTint: Color { series == .temperature ? Palette.hot : Palette.wetBulb }
    private var lowTint: Color { series == .temperature ? Palette.cold : Palette.wetBulb.opacity(0.75) }

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

    var body: some View {
        ChartModule(
            eyebrow: series.eyebrow,
            readout: readout,
            detailText: detailText,
            legend: [],
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

            if let first = points.first,
               let top = normalHigh(first), let bottom = normalLow(first) {
                PointMark(
                    x: .value("Day", first.dateString),
                    y: .value(
                        "Band mid",
                        formatter.temperatureValue((top + bottom) / 2)))
                .opacity(0)
                .annotation(position: .overlay, alignment: .leading) {
                    Text("Hist. avg")
                        .font(.system(size: 8.5))
                        .foregroundStyle(.secondary.opacity(0.8))
                        .padding(.leading, 2)
                }
            }

            if let todayDateString {
                RectangleMark(x: .value("Today", todayDateString))
                    .foregroundStyle(Color.secondary.opacity(0.08))
            }

            // Past (including today for a continuous join) — dashed ghost.
            ForEach(points) { point in
                if point.isPast || point.isToday, let value = high(point) {
                    LineMark(
                        x: .value("Day", point.dateString),
                        y: .value("High", formatter.temperatureValue(value)),
                        series: .value("Series", "high-past"))
                    .foregroundStyle(highTint.opacity(ChartKit.pastSeriesOpacity))
                    .lineStyle(StrokeStyle(lineWidth: 2, dash: ChartKit.pastDash))
                    .interpolationMethod(.catmullRom)
                }
                if point.isPast || point.isToday, let value = low(point) {
                    LineMark(
                        x: .value("Day", point.dateString),
                        y: .value("Low", formatter.temperatureValue(value)),
                        series: .value("Series", "low-past"))
                    .foregroundStyle(lowTint.opacity(ChartKit.pastSeriesOpacity))
                    .lineStyle(StrokeStyle(lineWidth: 2, dash: ChartKit.pastDash))
                    .interpolationMethod(.catmullRom)
                }
            }

            // Forecast (including today) — solid, labelled.
            ForEach(points) { point in
                if !point.isPast, let value = high(point) {
                    LineMark(
                        x: .value("Day", point.dateString),
                        y: .value("High", formatter.temperatureValue(value)),
                        series: .value("Series", "high-forecast"))
                    .foregroundStyle(highTint)
                    .interpolationMethod(.catmullRom)
                    PointMark(
                        x: .value("Day", point.dateString),
                        y: .value("High", formatter.temperatureValue(value)))
                    .foregroundStyle(highTint)
                    .symbolSize(30)
                    .annotation(position: .top, spacing: 2) {
                        ChartValueLabel(
                            text: formatter.temperatureShort(value), color: highTint)
                    }
                }
                if !point.isPast, let value = low(point) {
                    LineMark(
                        x: .value("Day", point.dateString),
                        y: .value("Low", formatter.temperatureValue(value)),
                        series: .value("Series", "low-forecast"))
                    .foregroundStyle(lowTint)
                    .interpolationMethod(.catmullRom)
                    PointMark(
                        x: .value("Day", point.dateString),
                        y: .value("Low", formatter.temperatureValue(value)))
                    .foregroundStyle(lowTint)
                    .symbolSize(30)
                    .annotation(position: .bottom, spacing: 2) {
                        ChartValueLabel(
                            text: formatter.temperatureShort(value), color: lowTint)
                    }
                }
            }

            ForEach(points) { point in
                if point.isPast, let value = high(point) {
                    PointMark(
                        x: .value("Day", point.dateString),
                        y: .value("High", formatter.temperatureValue(value)))
                    .foregroundStyle(highTint.opacity(ChartKit.pastSeriesOpacity))
                    .symbolSize(16)
                }
                if point.isPast, let value = low(point) {
                    PointMark(
                        x: .value("Day", point.dateString),
                        y: .value("Low", formatter.temperatureValue(value)))
                    .foregroundStyle(lowTint.opacity(ChartKit.pastSeriesOpacity))
                    .symbolSize(16)
                }
            }

            if let last = points.last, let hi = high(last), let lo = low(last) {
                PointMark(
                    x: .value("Day", last.dateString),
                    y: .value("High", formatter.temperatureValue(hi)))
                .opacity(0)
                .annotation(position: .trailing, spacing: 4) {
                    ChartEndLabel(text: "High", color: highTint)
                }
                PointMark(
                    x: .value("Day", last.dateString),
                    y: .value("Low", formatter.temperatureValue(lo)))
                .opacity(0)
                .annotation(position: .trailing, spacing: 4) {
                    ChartEndLabel(text: "Low", color: lowTint)
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
                    .foregroundStyle(highTint.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                PointMark(
                    x: .value("Day", selected.dateString),
                    y: .value("High", formatter.temperatureValue(hi)))
                .foregroundStyle(highTint)
                .symbolSize(70)
            }
        }
        .chartXSelection(value: $liveSelection)
        .chartScrub($liveSelection)
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
        .chartPlotStyle { $0.padding(.trailing, 36) }
        .frame(height: expanded ? ChartKit.dailyHeight + 60 : ChartKit.dailyHeight)
        .accessibilityLabel(series.accessibilityName)
        .accessibilityChartDescriptor(
            DailyTempChartDescriptor(
                points: points, series: series,
                formatter: formatter, timeZone: timeZone))
    }

    private func showsLabel(for point: ChartSeries.DailyPoint) -> Bool {
        DayLabelDensity.shows(point, in: points)
    }
}
