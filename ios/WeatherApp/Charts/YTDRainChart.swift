import Charts
import SwiftUI
import WeatherCore

/// §8.4.7 — cumulative rainfall this year vs. the historical average, with
/// dashed continuations past the archive's edge.
///
/// Lines only — the web chart has no area fill, so `AreaMark` is intentionally
/// absent. The heaviest chart in the app: up to ~365 points × 2 lines;
/// `ChartSeries.ytd` takes a `thinning` factor from the caller.
struct YTDRainChart: View {
    let series: ChartSeries.YTDSeries
    let formatter: UnitFormatter
    let thisYear: Int
    let timeZone: TimeZone
    var detailText: String? = nil
    var onOpenDetail: (() -> Void)? = nil
    var expanded: Bool = false

    @State private var liveSelection: Date?
    @State private var selectedDate: Date?
    @State private var scrubID = UUID()

    private enum Kind: String {
        case actual, historical, projection, historicalExtension
    }

    private var lastActual: ChartSeries.YTDPoint? { series.actual.last }

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

    private var readout: ChartReadout {
        if let projected = selectedProjection {
            return ChartReadout(
                primary: formatter.precipitation(projected.value),
                context: "\(label(projected)) · forecast",
                primaryTint: Palette.rainSeries)
        }
        let point = selectedActual ?? lastActual
        guard let point else { return .placeholder }
        let average = series.historical.first { $0.monthDay == point.monthDay }?.value
        let when = selectedActual == nil
            ? "Through \(label(point))"
            : label(point)
        if let average {
            let delta = point.value - average
            let signed = (delta >= 0 ? "+" : "−") + formatter.precipitation(abs(delta))
            let relation = delta > 0.05 ? "wetter" : (delta < -0.05 ? "drier" : "near")
            if abs(delta) <= 0.05 {
                return ChartReadout(
                    primary: formatter.precipitation(point.value),
                    context: "\(when) · near historical average",
                    primaryTint: Palette.rainSeries)
            }
            return ChartReadout(
                primary: formatter.precipitation(point.value),
                context: "\(when) · \(signed) \(relation) than avg",
                primaryTint: Palette.rainSeries)
        }
        return ChartReadout(
            primary: formatter.precipitation(point.value),
            context: when,
            primaryTint: Palette.rainSeries)
    }

    private var legend: [ChartLegendItem] { [] }

    var body: some View {
        ChartModule(
            eyebrow: "Year-to-Date Rainfall",
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

            // End-point marker matching the web's terminal circle + year label.
            if let last = lastActual {
                PointMark(
                    x: .value("Date", last.date),
                    y: .value("Cumulative", formatter.precipitationValue(last.value)))
                .foregroundStyle(Palette.rainSeries)
                .symbolSize(64)
                .annotation(position: .trailing, spacing: 4) {
                    ChartEndLabel(text: String(thisYear), color: Palette.rainSeries)
                }
            }

            if let lastHist = series.historicalExtension.last ?? series.historical.last {
                PointMark(
                    x: .value("Date", lastHist.date),
                    y: .value("Cumulative", formatter.precipitationValue(lastHist.value)))
                .opacity(0)
                .annotation(position: .trailing, spacing: 4) {
                    ChartEndLabel(
                        text: "Hist. avg", color: Palette.historical, weight: .regular)
                }
            }

            if let last = lastActual, !series.projection.isEmpty {
                RuleMark(x: .value("Today", last.date))
                    .foregroundStyle(.secondary.opacity(0.45))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .annotation(position: .top, alignment: .center) {
                        NowCapsule(label: "TODAY")
                    }
            }

            if let projected = selectedProjection {
                RuleMark(x: .value("Selected", projected.date))
                    .foregroundStyle(Palette.rainSeries.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                PointMark(
                    x: .value("Date", projected.date),
                    y: .value("Cumulative", formatter.precipitationValue(projected.value)))
                .foregroundStyle(Palette.rainSeries)
                .symbolSize(70)
            } else if let actual = selectedActual {
                RuleMark(x: .value("Selected", actual.date))
                    .foregroundStyle(Palette.rainSeries.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                PointMark(
                    x: .value("Date", actual.date),
                    y: .value("Cumulative", formatter.precipitationValue(actual.value)))
                .foregroundStyle(Palette.rainSeries)
                .symbolSize(70)
            }
        }
        .chartXSelection(value: $liveSelection)
        .chartScrub($liveSelection)
        .stickyXSelection(
            id: scrubID, live: $liveSelection, sticky: $selectedDate,
            resetOn: series.latestDate + "-" + String(series.actual.count))
        .chartSelectionHaptic(selectedDate)
        .chartYAxis { ChartAxes.precipitationYAxis(formatter: formatter) }
        .chartXAxis {
            // Every other month: narrow initials would render "M, M" and "J, J".
            AxisMarks(values: .stride(by: .month, count: 2)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                    .foregroundStyle(Color.secondary.opacity(0.18))
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(date.formatted(
                            Date.FormatStyle().month(.abbreviated), in: timeZone))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .chartPlotStyle { $0.padding(.trailing, 44) }
        .frame(height: expanded ? ChartKit.ytdHeight + 60 : ChartKit.ytdHeight)
        .accessibilityLabel("Year-to-date rainfall chart")
    }

    private func label(_ point: ChartSeries.YTDPoint) -> String {
        point.date.formatted(
            Date.FormatStyle().month(.abbreviated).day(), in: timeZone)
    }
}
