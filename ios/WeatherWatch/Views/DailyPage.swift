import Charts
import SwiftUI
import WeatherCore

/// §9.3 — 7 days as a floating high/low bar chart: the same range-bar language
/// as Apple's own 10-day forecast, tinted by how each day compares with the
/// historical normal once synced data has arrived. Tap a bar to see its exact
/// figures.
struct DailyPage: View {
    let store: WatchStore

    @State private var liveSelection: String?
    @State private var selectedDate: String?

    private var points: [ChartSeries.DailyPoint] { store.forecastDays }

    private var selected: ChartSeries.DailyPoint? {
        points.first { $0.dateString == selectedDate }
    }

    private var temperatureDomain: ClosedRange<Double> {
        let values = points.flatMap { [$0.high, $0.low] }.compactMap { $0 }
            .map(store.formatter.temperatureValue)
        guard let lo = values.min(), let hi = values.max() else { return 0...1 }
        let lower = (lo - 2).rounded(.down)
        let upper = (hi + 6).rounded(.up)  // headroom for the icon above each bar
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
            ForEach(points) { point in
                if let high = point.high, let low = point.low {
                    BarMark(
                        x: .value("Day", point.dateString),
                        yStart: .value("Low", store.formatter.temperatureValue(low)),
                        yEnd: .value("High", store.formatter.temperatureValue(high)),
                        width: .ratio(0.42))
                    .foregroundStyle(tint(point))
                    .cornerRadius(20)
                    .annotation(position: .top, spacing: 2) {
                        Image(systemName: point.symbolName)
                            .symbolRenderingMode(.multicolor)
                            .font(.system(size: 11))
                    }
                }
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

    /// Warm if the day's midpoint sits above the historical normal, cool if
    /// below, green if within it — gray until normals have synced (§9.2).
    private func tint(_ point: ChartSeries.DailyPoint) -> Color {
        guard let normal = point.normal,
              let normalHigh = normal.tMax, let normalLow = normal.tMin,
              let high = point.high, let low = point.low
        else { return .gray }
        let midpoint = (high + low) / 2
        let normalMidpoint = (normalHigh + normalLow) / 2
        if midpoint - normalMidpoint >= 1 { return WatchPalette.warm }
        if normalMidpoint - midpoint >= 1 { return WatchPalette.cool }
        return WatchPalette.neutral
    }

    private func scrubCard(_ point: ChartSeries.DailyPoint) -> some View {
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
