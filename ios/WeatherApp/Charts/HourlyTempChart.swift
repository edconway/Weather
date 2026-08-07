import Charts
import SwiftUI
import WeatherCore

/// §8.4.1 / §8.4.3 — up to 48 hourly points (±24 h around now) of temperature
/// (or wet bulb) against the 5-year average for that hour of day.
///
/// One view covers both series because the only differences are which value is
/// plotted and the scrub label; the web has two near-identical functions.
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

        var accessibilityName: String {
            switch self {
            case .temperature: return "48-hour temperature chart"
            case .wetBulb: return "48-hour wet bulb chart"
            }
        }
    }

    let points: [ChartSeries.HourlyPoint]
    let series: Series
    let formatter: UnitFormatter
    let timeZone: TimeZone

    @State private var liveSelection: Date?
    @State private var selectedDate: Date?

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

    var body: some View {
        Chart {
            // Past and future are separate series so the dash only applies
            // forward; a single series with a conditional dash is not possible.
            ForEach(points) { point in
                if let value = value(point), point.isPast {
                    LineMark(
                        x: .value("Time", point.date),
                        y: .value(series.scrubLabel, formatter.temperatureValue(value)),
                        series: .value("Series", "actual"))
                    .foregroundStyle(tint)
                    .interpolationMethod(.catmullRom)
                }
            }
            ForEach(points) { point in
                // The first forecast point is drawn in both series so the solid
                // and dashed segments meet without a gap.
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
                    .foregroundStyle(.secondary.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .annotation(position: .top, alignment: .center) {
                        Text("Now")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
            }

            if let selected, let value = value(selected) {
                RuleMark(x: .value("Selected", selected.date))
                    .foregroundStyle(.secondary.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .scrubAnnotation {
                        scrubCard(selected, value: value)
                    }
                PointMark(
                    x: .value("Time", selected.date),
                    y: .value(series.scrubLabel, formatter.temperatureValue(value)))
                .foregroundStyle(tint)
                .symbolSize(60)
            }
        }
        .chartXSelection(value: $liveSelection)
        .stickyXSelection(
            live: $liveSelection, sticky: $selectedDate,
            resetOn: points.first?.timeString ?? "")
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
            AxisMarks(values: .stride(by: .hour, count: 12)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        let hour = Calendar.hour(of: date, in: timeZone)
                        Text(hourLabel(hour))
                    }
                }
            }
        }
        .frame(height: ChartKit.hourlyHeight)
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

    private func scrubCard(_ point: ChartSeries.HourlyPoint, value: Double) -> some View {
        let dayLabel = point.date.formatted(
            Date.FormatStyle().weekday(.abbreviated).month(.abbreviated).day(),
            in: timeZone)
        return ScrubCard(
            title: "\(dayLabel) \(hourLabel(point.hour))",
            tag: point.isPast ? "actual" : nil
        ) {
            ScrubRow(
                label: series.scrubLabel,
                value: formatter.temperature(value),
                tint: tint)
            ScrubRow(
                label: "5-yr avg",
                value: formatter.temperature(normal(point)),
                tint: .secondary)
        }
    }
}

extension Calendar {
    static func hour(of date: Date, in timeZone: TimeZone) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.component(.hour, from: date)
    }
}
