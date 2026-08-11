import Charts
import SwiftUI
import WeatherCore

/// §8.4.5 — up to 48 hourly precipitation bars (±24 h around now). Probability
/// lives in the scrub annotation only; Swift Charts has no second y-axis.
struct HourlyRainChart: View {
    let points: [ChartSeries.HourlyPoint]
    let formatter: UnitFormatter
    let timeZone: TimeZone

    @State private var liveSelection: Date?
    @State private var selectedDate: Date?
    @State private var scrubID = UUID()

    private var nowDate: Date? { points.first(where: { !$0.isPast })?.date }

    private var selected: ChartSeries.HourlyPoint? {
        guard let selectedDate else { return nil }
        return points.min {
            abs($0.date.timeIntervalSince(selectedDate))
                < abs($1.date.timeIntervalSince(selectedDate))
        }
    }

    /// `yMax = max(precip, 0.5) * 1.25`, from `makeHourlyRainChart`.
    private var yDomain: ClosedRange<Double> {
        ChartScales.rainDomain(
            points.map { formatter.precipitationValue($0.precipitation) },
            floor: formatter.precipitationValue(0.5),
            headroom: 1.25)
    }

    var body: some View {
        Chart {
            ForEach(points) { point in
                BarMark(
                    x: .value("Time", point.date, unit: .hour),
                    y: .value("Precipitation", formatter.precipitationValue(point.precipitation)))
                .foregroundStyle(Palette.rainSeries.opacity(point.isPast ? 0.45 : 1))
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

            if let selected {
                RuleMark(x: .value("Selected", selected.date))
                    .foregroundStyle(.secondary.opacity(0.35))
                    .scrubAnnotation { scrubCard(selected) }
            }
        }
        .chartXSelection(value: $liveSelection)
        .chartTapFallback($liveSelection)
        .stickyXSelection(
            id: scrubID, live: $liveSelection, sticky: $selectedDate,
            resetOn: points.first?.timeString ?? "")
        .chartYScale(domain: yDomain)
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let number = value.as(Double.self) {
                        Text(formatter.precipitationAxis(displayValue: number))
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 12)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(hourLabel(Calendar.hour(of: date, in: timeZone)))
                    }
                }
            }
        }
        .frame(height: ChartKit.hourlyHeight)
        .accessibilityLabel("48-hour rainfall chart")
    }

    private func scrubCard(_ point: ChartSeries.HourlyPoint) -> some View {
        let dayLabel = point.date.formatted(
            Date.FormatStyle().weekday(.abbreviated).month(.abbreviated).day(), in: timeZone)
        return ScrubCard(
            title: "\(dayLabel) \(hourLabel(point.hour))",
            tag: point.isPast ? "actual" : nil
        ) {
            ScrubRow(
                label: "Precip",
                value: formatter.precipitationCompact(point.precipitation),
                tint: Palette.rainSeries)
            if !point.isPast, let probability = point.probability {
                ScrubRow(label: "Probability", value: "\(probability)%", tint: .secondary)
            }
            // §8.4.5's optional flourish.
            if let p90 = point.rainP90, p90 > 0, point.precipitation >= p90 {
                ScrubRow(
                    label: "Unusual",
                    value: "heavier than 9 of 10 similar hours",
                    tint: Palette.rainSeries)
            }
        }
    }
}

/// §8.4.6 — 14 daily precipitation bars with the §6.5 classification chip.
///
/// Categorical x for the same reason as `DailyTempChart`.
struct DailyRainChart: View {
    let points: [ChartSeries.DailyPoint]
    let formatter: UnitFormatter
    let timeZone: TimeZone

    @State private var liveSelection: String?
    @State private var selectedDate: String?
    @State private var scrubID = UUID()

    private var todayDateString: String? { points.first(where: \.isToday)?.dateString }

    private var selected: ChartSeries.DailyPoint? {
        points.first { $0.dateString == selectedDate }
    }

    /// `yMax = max(precip, 1) * 1.2`, from `makeDailyRainChart`.
    private var yDomain: ClosedRange<Double> {
        ChartScales.rainDomain(
            points.map { formatter.precipitationValue($0.precipitation) },
            floor: formatter.precipitationValue(1),
            headroom: 1.2)
    }

    var body: some View {
        Chart {
            ForEach(points) { point in
                BarMark(
                    x: .value("Day", point.dateString),
                    y: .value("Precipitation", formatter.precipitationValue(point.precipitation)),
                    width: .ratio(0.6))
                .foregroundStyle(point.isPast
                    ? Palette.rainSeries.opacity(0.4)   // "actual"
                    : Palette.rainSeries)               // "forecast"
                .cornerRadius(3)
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
        .chartTapFallback($liveSelection)
        .stickyXSelection(
            id: scrubID, live: $liveSelection, sticky: $selectedDate,
            resetOn: points.first?.dateString ?? "")
        .chartXScale(domain: points.map(\.dateString))
        .chartYScale(domain: yDomain)
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let number = value.as(Double.self) {
                        Text(formatter.precipitationAxis(displayValue: number))
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 14)) { value in
                AxisValueLabel {
                    if let dateString = value.as(String.self),
                       let point = points.first(where: { $0.dateString == dateString }),
                       DayLabelDensity.shows(point, in: points) {
                        Text(point.label(timeZone: timeZone))
                            .font(.system(size: 9, weight: point.isToday ? .bold : .regular))
                    }
                }
            }
        }
        .frame(height: ChartKit.dailyHeight)
        .accessibilityLabel("14-day rainfall chart")
    }

    private func scrubCard(_ point: ChartSeries.DailyPoint) -> some View {
        ScrubCard(
            title: point.label(timeZone: timeZone),
            tag: point.isPast ? "actual" : nil
        ) {
            ScrubRow(
                label: point.isPast ? "Actual" : "Forecast",
                value: formatter.precipitationCompact(point.precipitation),
                tint: Palette.rainSeries)
            if !point.isPast, let probability = point.probability {
                ScrubRow(label: "Probability", value: "\(probability)%", tint: .secondary)
            }
            if let rainNormal = point.rainNormal {
                ScrubRow(
                    label: "vs normal",
                    value: rainNormal.classification.text,
                    tint: .secondary)
                ScrubRow(
                    label: "Hist. avg",
                    value: formatter.precipitationCompact(rainNormal.histMeanMm),
                    tint: .secondary)
            }
        }
    }
}
