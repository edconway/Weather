import Charts
import SwiftUI
import WeatherCore

/// §9.3 — 7 days as high/low temperature lines over a historical-normal band,
/// matching the iOS app's `DailyTempChart`. Tap a point to see its exact
/// figures.
struct DailyPage: View {
    let store: WatchStore

    @State private var liveSelection: String?
    @State private var selectedDate: String?

    private var points: [ChartSeries.DailyPoint] { store.forecastDays }

    private var selected: ChartSeries.DailyPoint? {
        points.first { $0.dateString == selectedDate }
    }

    private var todayDateString: String? {
        points.first(where: \.isToday)?.dateString
    }

    private var temperatureDomain: ClosedRange<Double> {
        // Includes the historical band so it never clips at the domain edge.
        let values = points.flatMap { [$0.high, $0.low, $0.normal?.tMax, $0.normal?.tMin] }
            .compactMap { $0 }.map(store.formatter.temperatureValue)
        guard let lo = values.min(), let hi = values.max() else { return 0...1 }
        let lower = (lo - 2).rounded(.down)
        let upper = (hi + 6).rounded(.up)  // headroom for the icon above each point
        return lower < upper ? lower...upper : lower...(lower + 1)
    }

    var body: some View {
        Group {
            if points.isEmpty {
                Text("No daily data")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                chart
            }
        }
        .navigationTitle("7 Days")
        .accessibilityElement(children: .contain)
        .accessibilityLabel("7-day high and low temperature chart")
    }

    private var chart: some View {
        Chart {
            // Historical-normal band, drawn first so the lines sit on top —
            // matches the iOS app's DailyTempChart.
            ForEach(points) { point in
                if let normalHigh = point.normal?.tMax, let normalLow = point.normal?.tMin {
                    AreaMark(
                        x: .value("Day", point.dateString),
                        yStart: .value("Normal low", store.formatter.temperatureValue(normalLow)),
                        yEnd: .value("Normal high", store.formatter.temperatureValue(normalHigh)))
                    .foregroundStyle(WatchPalette.historical.opacity(0.22))
                    .interpolationMethod(.catmullRom)
                }
            }

            ForEach(points) { point in
                if let high = point.high {
                    LineMark(
                        x: .value("Day", point.dateString),
                        y: .value("High", store.formatter.temperatureValue(high)),
                        series: .value("Series", "high"))
                    .foregroundStyle(WatchPalette.hot)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.catmullRom)
                    PointMark(
                        x: .value("Day", point.dateString),
                        y: .value("High", store.formatter.temperatureValue(high)))
                    .foregroundStyle(WatchPalette.hot)
                    .symbolSize(20)
                    .annotation(position: .top, spacing: 2) {
                        Image(systemName: point.symbolName)
                            .symbolRenderingMode(.multicolor)
                            .font(.system(size: 11))
                    }
                }
            }

            ForEach(points) { point in
                if let low = point.low {
                    LineMark(
                        x: .value("Day", point.dateString),
                        y: .value("Low", store.formatter.temperatureValue(low)),
                        series: .value("Series", "low"))
                    .foregroundStyle(WatchPalette.cold)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.catmullRom)
                    PointMark(
                        x: .value("Day", point.dateString),
                        y: .value("Low", store.formatter.temperatureValue(low)))
                    .foregroundStyle(WatchPalette.cold)
                    .symbolSize(20)
                }
            }

            if let todayDateString {
                RuleMark(x: .value("Today", todayDateString))
                    .foregroundStyle(.white.opacity(0.25))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }

            if let selected {
                RuleMark(x: .value("Selected", selected.dateString))
                    .foregroundStyle(.white.opacity(0.15))
                    .annotation(position: .bottom, spacing: 2) {
                        scrubCard(selected)
                    }
            }
        }
        .chartXSelection(value: $liveSelection)
        .stickyXSelection(
            live: $liveSelection, sticky: $selectedDate,
            resetOn: points.first?.dateString ?? "")
        .chartXScale(domain: points.map(\.dateString))
        .chartYScale(domain: temperatureDomain)
        .chartXAxis {
            AxisMarks(values: points.map(\.dateString)) { value in
                AxisValueLabel {
                    if let dateString = value.as(String.self),
                       let point = points.first(where: { $0.dateString == dateString }) {
                        Text(point.isToday ? "•" : dayInitial(point))
                            .font(.system(size: 9, weight: point.isToday ? .bold : .regular))
                            .foregroundStyle(point.isToday ? .primary : .secondary)
                    }
                }
            }
        }
        .chartYAxis(.hidden)
        // See HourlyPage: `chartXSelection`'s gesture did not respond to taps
        // in the watchOS simulator, so this is a belt-and-braces fallback.
        // The x-axis is categorical here, so the proxy value type is String.
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .onTapGesture { location in
                        let origin = geo[proxy.plotFrame!].origin
                        let x = location.x - origin.x
                        if let day: String = proxy.value(atX: x) {
                            selectedDate = day
                        }
                    }
            }
        }
    }

    private func scrubCard(_ point: ChartSeries.DailyPoint) -> some View {
        VStack(spacing: 1) {
            HStack(spacing: 5) {
                Text(point.isToday ? "Today" : point.label(timeZone: store.locationTimeZone))
                    .font(.system(size: 9, weight: .semibold))
                Text(store.formatter.temperature(point.low))
                    .font(.system(size: 9))
                    .foregroundStyle(WatchPalette.cold)
                Text(store.formatter.temperature(point.high))
                    .font(.system(size: 9))
                    .foregroundStyle(WatchPalette.hot)
            }
            if let normalHigh = point.normal?.tMax, let normalLow = point.normal?.tMin {
                Text("Hist. \(store.formatter.temperature(normalLow))–\(store.formatter.temperature(normalHigh))")
                    .font(.system(size: 8))
                    .foregroundStyle(WatchPalette.historical)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
    }

    /// Single-letter weekday — matches Calendar's own week-view convention and
    /// is the only way seven labels fit across a 40mm screen.
    private func dayInitial(_ point: ChartSeries.DailyPoint) -> String {
        String(point.label(timeZone: store.locationTimeZone).prefix(1))
    }
}
