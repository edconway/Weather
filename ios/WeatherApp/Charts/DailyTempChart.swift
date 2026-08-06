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

    @State private var liveSelection: String?
    @State private var selectedDate: String?

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

    var body: some View {
        Chart {
            // The band goes first so the lines draw over it.
            ForEach(points) { point in
                if let top = normalHigh(point), let bottom = normalLow(point) {
                    AreaMark(
                        x: .value("Day", point.dateString),
                        yStart: .value("Normal low", formatter.temperatureValue(bottom)),
                        yEnd: .value("Normal high", formatter.temperatureValue(top)))
                    .foregroundStyle(Palette.historical.opacity(0.22))
                    .interpolationMethod(.catmullRom)
                }
            }

            ForEach(points) { point in
                if let value = high(point) {
                    LineMark(
                        x: .value("Day", point.dateString),
                        y: .value("High", formatter.temperatureValue(value)),
                        series: .value("Series", "high"))
                    .foregroundStyle(Palette.hot)
                    .interpolationMethod(.catmullRom)
                    .opacity(point.isPast ? 0.55 : 1)
                    PointMark(
                        x: .value("Day", point.dateString),
                        y: .value("High", formatter.temperatureValue(value)))
                    .foregroundStyle(Palette.hot)
                    .symbolSize(point.isPast ? 16 : 30)
                }
                if let value = low(point) {
                    LineMark(
                        x: .value("Day", point.dateString),
                        y: .value("Low", formatter.temperatureValue(value)),
                        series: .value("Series", "low"))
                    .foregroundStyle(Palette.cold)
                    .interpolationMethod(.catmullRom)
                    .opacity(point.isPast ? 0.55 : 1)
                    PointMark(
                        x: .value("Day", point.dateString),
                        y: .value("Low", formatter.temperatureValue(value)))
                    .foregroundStyle(Palette.cold)
                    .symbolSize(point.isPast ? 16 : 30)
                }
            }

            if let todayDateString {
                RuleMark(x: .value("Today", todayDateString))
                    .foregroundStyle(.secondary.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }

            if let selected {
                RuleMark(x: .value("Selected", selected.dateString))
                    .foregroundStyle(.secondary.opacity(0.35))
                    .scrubAnnotation { scrubCard(selected) }
            }
        }
        .chartXSelection(value: $liveSelection)
        .stickyXSelection(
            live: $liveSelection, sticky: $selectedDate,
            resetOn: points.first?.dateString ?? "")
        .chartXScale(domain: points.map(\.dateString))
        .chartYScale(domain: yDomain)
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let number = value.as(Double.self) {
                        Text(formatter.temperatureAxis(number))
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 14)) { value in
                AxisValueLabel {
                    if let dateString = value.as(String.self),
                       let point = points.first(where: { $0.dateString == dateString }),
                       showsLabel(for: point) {
                        Text(point.label(timeZone: timeZone))
                            .font(.system(size: 9, weight: point.isToday ? .bold : .regular))
                    }
                }
            }
        }
        .frame(height: ChartKit.dailyHeight)
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

    private func scrubCard(_ point: ChartSeries.DailyPoint) -> some View {
        let range: String
        if let top = normalHigh(point), let bottom = normalLow(point) {
            range = "\(formatter.temperatureShort(bottom))–\(formatter.temperatureShort(top))"
        } else {
            range = UnitFormatter.placeholder
        }
        return ScrubCard(
            title: point.label(timeZone: timeZone),
            tag: point.isPast ? "actual" : nil
        ) {
            ScrubRow(label: "High", value: formatter.temperature(high(point)), tint: Palette.hot)
            ScrubRow(label: "Low", value: formatter.temperature(low(point)), tint: Palette.cold)
            ScrubRow(label: "Hist. range", value: range, tint: .secondary)
        }
    }
}
