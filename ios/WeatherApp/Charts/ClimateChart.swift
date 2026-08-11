import Charts
import SwiftUI
import WeatherCore

/// §8.4.8 — PLAN DEVIATION §1.4.8: the web app's dual-axis chart (temperature
/// lines + rainfall bars) becomes two stacked charts sharing the month axis,
/// because Swift Charts has no second y-axis. Scrubbing either one selects the
/// same month in both.
struct ClimateChart: View {
    let points: [ChartSeries.ClimatePoint]
    let formatter: UnitFormatter

    @State private var selectedMonth: Int?
    @State private var scrubID: AnyHashable = UUID()

    @Environment(ActiveScrubCoordinator.self) private var coordinator

    private var selected: ChartSeries.ClimatePoint? {
        selectedMonth.flatMap { month in points.first { $0.id == month } }
    }

    var body: some View {
        // The gap keeps the rainfall chart's top tick clear of the temperature
        // chart's bottom tick.
        VStack(alignment: .leading, spacing: 14) {
            temperatureChart
            rainfallChart
            if let selected {
                summary(selected)
            }
        }
        // Drop the selection when the location changes, so the summary row never
        // describes one city with another's numbers.
        .onChange(of: points.first?.high) { _, _ in selectedMonth = nil }
        // See StickyXSelection: clears this chart's summary row when a
        // different chart on the screen becomes active.
        .onChange(of: coordinator.activeID) { _, activeID in
            guard selectedMonth != nil, activeID != scrubID else { return }
            selectedMonth = nil
        }
    }

    private var temperatureChart: some View {
        Chart {
            ForEach(points) { point in
                if let high = point.high {
                    LineMark(
                        x: .value("Month", point.shortMonthName),
                        y: .value("Avg high", formatter.temperatureValue(high)),
                        series: .value("Series", "high"))
                    .foregroundStyle(Palette.hot)
                    .interpolationMethod(.catmullRom)
                }
                if let low = point.low {
                    LineMark(
                        x: .value("Month", point.shortMonthName),
                        y: .value("Avg low", formatter.temperatureValue(low)),
                        series: .value("Series", "low"))
                    .foregroundStyle(Palette.cold)
                    .interpolationMethod(.catmullRom)
                }
            }
            if let selected {
                RuleMark(x: .value("Month", selected.shortMonthName))
                    .foregroundStyle(.secondary.opacity(0.35))
            }
        }
        .chartXSelection(value: monthSelection)
        .chartTapFallback(monthSelection)
        // The month labels live under the rainfall chart only — the two charts
        // share one x-axis, so repeating them would just be noise.
        .chartXAxis {
            AxisMarks { _ in AxisGridLine() }
        }
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let number = value.as(Double.self) {
                        Text(formatter.temperatureAxis(number))
                    }
                }
            }
        }
        .frame(height: ChartKit.climateTempHeight)
        .accessibilityLabel("Average monthly high and low temperature chart")
    }

    private var rainfallChart: some View {
        Chart {
            ForEach(points) { point in
                if let rain = point.rain {
                    BarMark(
                        x: .value("Month", point.shortMonthName),
                        y: .value("Avg rainfall", formatter.precipitationValue(rain)))
                    .foregroundStyle(Palette.rainSeries.opacity(
                        selected == nil || selected?.id == point.id ? 0.85 : 0.35))
                    .cornerRadius(3)
                }
            }
        }
        .chartXSelection(value: monthSelection)
        .chartTapFallback(monthSelection)
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let number = value.as(Double.self) {
                        Text(formatter.precipitationAxis(displayValue: number))
                    }
                }
            }
        }
        .frame(height: ChartKit.climateRainHeight)
        .accessibilityLabel("Average monthly rainfall chart")
    }

    /// Both charts bind to the same month so a scrub in either highlights both.
    ///
    /// The setter ignores `nil`, which `chartXSelection` sends when the gesture
    /// ends — see `StickyXSelection` for why the selection has to persist.
    private var monthSelection: Binding<String?> {
        Binding(
            get: { selected?.shortMonthName },
            set: { name in
                guard let name else { return }
                selectedMonth = points.first { $0.shortMonthName == name }?.id
                coordinator.activeID = scrubID
            })
    }

    private func summary(_ point: ChartSeries.ClimatePoint) -> some View {
        HStack(spacing: 14) {
            Text(point.monthName).font(.caption2.weight(.bold))
            Label(formatter.temperature(point.high), systemImage: "arrow.up")
                .font(.caption2).foregroundStyle(Palette.hot)
            Label(formatter.temperature(point.low), systemImage: "arrow.down")
                .font(.caption2).foregroundStyle(Palette.cold)
            Label(formatter.precipitation(point.rain), systemImage: "drop.fill")
                .font(.caption2).foregroundStyle(Palette.rainSeries)
            Spacer(minLength: 0)
        }
        .labelStyle(.titleAndIcon)
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
    }
}
