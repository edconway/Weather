import Charts
import SwiftUI
import WeatherCore

/// §8.4.7 — cumulative rainfall this year vs. the historical average, with
/// dashed continuations past the archive's edge.
///
/// The heaviest chart in the app: up to ~365 points × 2 lines. `ChartSeries.ytd`
/// takes a `thinning` factor; the caller passes 2 once the year is long enough
/// that every point stops being distinguishable anyway.
struct YTDRainChart: View {
    let series: ChartSeries.YTDSeries
    let formatter: UnitFormatter
    let thisYear: Int
    let timeZone: TimeZone

    @State private var liveSelection: Date?
    @State private var selectedDate: Date?

    private enum Kind: String {
        case actual, historical, projection, historicalExtension
    }

    private var selectedActual: ChartSeries.YTDPoint? {
        guard let selectedDate else { return nil }
        return series.actual.min {
            abs($0.date.timeIntervalSince(selectedDate))
                < abs($1.date.timeIntervalSince(selectedDate))
        }
    }

    private var selectedProjection: ChartSeries.YTDPoint? {
        guard let selectedDate, let lastActual = series.actual.last,
              selectedDate > lastActual.date, series.projection.count > 1 else { return nil }
        return series.projection.min {
            abs($0.date.timeIntervalSince(selectedDate))
                < abs($1.date.timeIntervalSince(selectedDate))
        }
    }

    var body: some View {
        Chart {
            ForEach(series.historical) { point in
                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Cumulative", formatter.precipitationValue(point.value)),
                    series: .value("Series", Kind.historical.rawValue))
                .foregroundStyle(Palette.historical.opacity(0.7))
                .lineStyle(StrokeStyle(lineWidth: 1.5))
            }

            ForEach(series.historicalExtension) { point in
                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Cumulative", formatter.precipitationValue(point.value)),
                    series: .value("Series", Kind.historicalExtension.rawValue))
                .foregroundStyle(Palette.historical.opacity(0.7))
                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: ChartKit.forecastDash))
            }

            ForEach(series.actual) { point in
                AreaMark(
                    x: .value("Date", point.date),
                    y: .value("Cumulative", formatter.precipitationValue(point.value)))
                .foregroundStyle(
                    .linearGradient(
                        colors: [Palette.rainSeries.opacity(0.28), Palette.rainSeries.opacity(0.02)],
                        startPoint: .top, endPoint: .bottom))
                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Cumulative", formatter.precipitationValue(point.value)),
                    series: .value("Series", Kind.actual.rawValue))
                .foregroundStyle(Palette.rainSeries)
                .lineStyle(StrokeStyle(lineWidth: 2))
            }

            ForEach(series.projection) { point in
                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Cumulative", formatter.precipitationValue(point.value)),
                    series: .value("Series", Kind.projection.rawValue))
                .foregroundStyle(Palette.rainSeries)
                .lineStyle(StrokeStyle(lineWidth: 2, dash: ChartKit.forecastDash))
            }

            if let projected = selectedProjection {
                RuleMark(x: .value("Selected", projected.date))
                    .foregroundStyle(.secondary.opacity(0.35))
                    .scrubAnnotation {
                        ScrubCard(title: label(projected), tag: "forecast") {
                            ScrubRow(
                                label: "\(thisYear) (proj.)",
                                value: formatter.precipitation(projected.value),
                                tint: Palette.rainSeries)
                        }
                    }
            } else if let actual = selectedActual {
                RuleMark(x: .value("Selected", actual.date))
                    .foregroundStyle(.secondary.opacity(0.35))
                    .scrubAnnotation { scrubCard(actual) }
            }
        }
        .chartXSelection(value: $liveSelection)
        .stickyXSelection(
            live: $liveSelection, sticky: $selectedDate,
            resetOn: series.latestDate + "-" + String(series.actual.count))
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let number = value.as(Double.self) {
                        Text(formatter.precipitationAxis(displayValue: number))
                    }
                }
            }
        }
        .chartXAxis {
            // Every other month: narrow initials would render "M, M" and "J, J",
            // which is worse than fewer, unambiguous labels.
            AxisMarks(values: .stride(by: .month, count: 2)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(date.formatted(
                            Date.FormatStyle().month(.abbreviated), in: timeZone))
                            .font(.system(size: 9))
                    }
                }
            }
        }
        .frame(height: ChartKit.ytdHeight)
        .accessibilityLabel("Year-to-date rainfall chart")
    }

    private func label(_ point: ChartSeries.YTDPoint) -> String {
        point.date.formatted(
            Date.FormatStyle().month(.abbreviated).day(), in: timeZone) + " YTD"
    }

    private func scrubCard(_ point: ChartSeries.YTDPoint) -> some View {
        let average = series.historical.first { $0.monthDay == point.monthDay }?.value
        let delta = average.map { point.value - $0 }
        return ScrubCard(title: label(point), tag: nil) {
            ScrubRow(
                label: "\(thisYear)",
                value: formatter.precipitation(point.value),
                tint: Palette.rainSeries)
            ScrubRow(
                label: "Hist. avg",
                value: formatter.precipitation(average),
                tint: .secondary)
            if let delta {
                ScrubRow(
                    label: "Delta",
                    value: (delta >= 0 ? "+" : "−") + formatter.precipitation(abs(delta)),
                    tint: delta > 0.05
                        ? Palette.rainSeries
                        : (delta < -0.05 ? Palette.hot : .secondary))
            }
        }
    }
}
