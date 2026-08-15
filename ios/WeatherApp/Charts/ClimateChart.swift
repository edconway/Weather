import Charts
import SwiftUI
import WeatherCore

/// §8.4.8 — PLAN DEVIATION §1.4.8: the web app's dual-axis chart (temperature
/// lines + rainfall bars) becomes two stacked charts sharing the month axis,
/// because Swift Charts has no second y-axis. Scrubbing either one selects the
/// same month in both.
///
/// Month labels stay categorical **strings**, but the domain is locked to
/// Jan…Dec order and high/low are drawn in separate passes. (An earlier Int
/// x-scale + `chartXSelection` path crashed Charts on device when this panel
/// appeared.)
struct ClimateChart: View {
    let points: [ChartSeries.ClimatePoint]
    let formatter: UnitFormatter
    var detailText: String? = nil
    var onOpenDetail: (() -> Void)? = nil
    var expanded: Bool = false

    @State private var selectedMonth: Int?
    @State private var scrubID: AnyHashable = UUID()

    @Environment(ActiveScrubCoordinator.self) private var coordinator

    private var currentMonth: Int {
        Calendar.current.component(.month, from: Date()) - 1
    }

    private var monthNames: [String] { points.map(\.shortMonthName) }

    private var currentPoint: ChartSeries.ClimatePoint? {
        points.first { $0.id == currentMonth }
    }

    private var selected: ChartSeries.ClimatePoint? {
        selectedMonth.flatMap { month in points.first { $0.id == month } }
    }

    private var readout: ChartReadout {
        let point = selected ?? currentPoint ?? points.first
        guard let point else { return .placeholder }
        let when = selected == nil && point.id == currentMonth
            ? "\(point.monthName) · this month"
            : point.monthName
        let high = formatter.temperatureShort(point.high)
        let low = formatter.temperatureShort(point.low)
        let rain = formatter.precipitationCompact(point.rain)
        return ChartReadout(
            primary: "\(high) / \(low)",
            context: "\(when) · \(rain) rain")
    }

    private var legend: [ChartLegendItem] {
        [
            ChartLegendItem("Avg high", swatch: .solid(Palette.hot)),
            ChartLegendItem("Avg low", swatch: .solid(Palette.cold)),
            ChartLegendItem("Rainfall", swatch: .solid(Palette.rainSeries.opacity(0.85))),
        ]
    }

    var body: some View {
        ChartModule(
            eyebrow: "Climate Overview",
            readout: readout,
            detailText: detailText,
            legend: legend,
            onOpenDetail: onOpenDetail
        ) {
            VStack(alignment: .leading, spacing: 14) {
                temperatureChart
                rainfallChart
            }
        }
        .onChange(of: points.first?.high) { _, _ in selectedMonth = nil }
        .onChange(of: coordinator.activeID) { _, activeID in
            guard selectedMonth != nil, activeID != scrubID else { return }
            selectedMonth = nil
        }
    }

    private var temperatureChart: some View {
        Chart {
            if let current = currentPoint {
                RectangleMark(x: .value("Month", current.shortMonthName))
                    .foregroundStyle(Color.yellow.opacity(0.09))
            }

            ForEach(points) { point in
                if let high = point.high {
                    LineMark(
                        x: .value("Month", point.shortMonthName),
                        y: .value("Avg high", formatter.temperatureValue(high)),
                        series: .value("Series", "high"))
                    .foregroundStyle(Palette.hot)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .interpolationMethod(.linear)
                }
            }
            ForEach(points) { point in
                if let low = point.low {
                    LineMark(
                        x: .value("Month", point.shortMonthName),
                        y: .value("Avg low", formatter.temperatureValue(low)),
                        series: .value("Series", "low"))
                    .foregroundStyle(Palette.cold)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .interpolationMethod(.linear)
                }
            }
            ForEach(points) { point in
                if let high = point.high {
                    PointMark(
                        x: .value("Month", point.shortMonthName),
                        y: .value("Avg high", formatter.temperatureValue(high)))
                    .foregroundStyle(Palette.hot)
                    .symbolSize(point.id == currentMonth ? 48 : 28)
                }
                if let low = point.low {
                    PointMark(
                        x: .value("Month", point.shortMonthName),
                        y: .value("Avg low", formatter.temperatureValue(low)))
                    .foregroundStyle(Palette.cold)
                    .symbolSize(point.id == currentMonth ? 48 : 28)
                }
            }

            if let selected {
                RuleMark(x: .value("Month", selected.shortMonthName))
                    .foregroundStyle(.secondary.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 1))
            }
        }
        .chartXSelection(value: monthSelection)
        .chartTapFallback(monthSelection)
        .chartXScale(domain: monthNames)
        .chartXAxis {
            AxisMarks(values: monthNames) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                    .foregroundStyle(Color.secondary.opacity(0.18))
            }
        }
        .chartYAxis { ChartAxes.temperatureYAxis(formatter: formatter) }
        .frame(height: expanded ? ChartKit.climateTempHeight + 40 : ChartKit.climateTempHeight)
        .accessibilityLabel("Average monthly high and low temperature chart")
    }

    private var rainfallChart: some View {
        Chart {
            ForEach(points) { point in
                if let rain = point.rain {
                    BarMark(
                        x: .value("Month", point.shortMonthName),
                        y: .value("Avg rainfall", formatter.precipitationValue(rain)),
                        width: .ratio(0.65))
                    .foregroundStyle(Palette.rainSeries.opacity(
                        selected == nil || selected?.id == point.id ? 0.85 : 0.35))
                    .cornerRadius(3)
                }
            }
        }
        .chartXSelection(value: monthSelection)
        .chartTapFallback(monthSelection)
        .chartXScale(domain: monthNames)
        .chartYAxis { ChartAxes.precipitationYAxis(formatter: formatter) }
        .chartXAxis {
            AxisMarks(values: monthNames) { value in
                AxisValueLabel {
                    if let name = value.as(String.self),
                       let point = points.first(where: { $0.shortMonthName == name }) {
                        Text(name)
                            .font(.caption2.weight(point.id == currentMonth ? .bold : .regular))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(height: expanded ? ChartKit.climateRainHeight + 30 : ChartKit.climateRainHeight)
        .accessibilityLabel("Average monthly rainfall chart")
    }

    /// Both charts bind to the same month so a scrub in either highlights both.
    private var monthSelection: Binding<String?> {
        Binding(
            get: { selected?.shortMonthName },
            set: { name in
                guard let name else { return }
                selectedMonth = points.first { $0.shortMonthName == name }?.id
                coordinator.activeID = scrubID
            })
    }
}
