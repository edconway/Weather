import Charts
import SwiftUI
import WeatherCore

/// Last 3 days + today + next 3 as high/low lines, with a compact readout,
/// on-plot peak/trough labels, and a TODAY spine.
struct DailyPage: View {
    let store: WatchStore

    @State private var liveSelection: String?
    @State private var selectedDate: String?

    private var points: [ChartSeries.DailyPoint] { store.recentAndForecastDays }

    private var selected: ChartSeries.DailyPoint? {
        points.first { $0.dateString == selectedDate }
    }

    private var todayPoint: ChartSeries.DailyPoint? {
        points.first(where: \.isToday)
    }

    private var todayDateString: String? {
        todayPoint?.dateString
    }

    /// Day with the warmest high in the window.
    private var peakHighPoint: ChartSeries.DailyPoint? {
        points.filter { $0.high != nil }
            .max { ($0.high ?? -.infinity) < ($1.high ?? -.infinity) }
    }

    /// Day with the coldest low in the window.
    private var troughLowPoint: ChartSeries.DailyPoint? {
        points.filter { $0.low != nil }
            .min { ($0.low ?? .infinity) < ($1.low ?? .infinity) }
    }

    private var temperatureDomain: ClosedRange<Double> {
        let values = points.flatMap { [$0.high, $0.low, $0.normal?.tMax, $0.normal?.tMin] }
            .compactMap { $0 }.map(store.formatter.temperatureValue)
        guard let lo = values.min(), let hi = values.max() else { return 0...1 }
        // Tight domain so hi/lo lines stretch; small headroom for peak label.
        let lower = lo - 1.2
        let upper = hi + 1.8
        return lower < upper ? lower...upper : lower...(lower + 1)
    }

    private var readoutPoint: ChartSeries.DailyPoint? {
        selected ?? todayPoint ?? points.first
    }

    private var hasNormalBand: Bool {
        points.contains { $0.normal?.tMax != nil && $0.normal?.tMin != nil }
    }

    private var readoutContext: String {
        let point = readoutPoint
        guard let point else { return "—" }
        let when = (selected == nil && point.isToday)
            ? "Today"
            : point.label(timeZone: store.locationTimeZone)
        let tag = point.isPast ? " · actual" : ""
        if let top = point.normal?.tMax, let bottom = point.normal?.tMin, let hi = point.high {
            let midNormal = (top + bottom) / 2
            let delta = hi - midNormal
            let absDelta = store.formatter.temperatureShort(abs(delta))
            if abs(delta) <= 0.5 {
                return "\(when)\(tag) · near usual"
            }
            let relation = delta > 0 ? "hotter" : "colder"
            return "\(when)\(tag) · \(absDelta) \(relation) than usual"
        }
        return "\(when)\(tag)"
    }

    var body: some View {
        Group {
            if points.isEmpty {
                Text("No daily data")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                GeometryReader { geo in
                    let headerHeight: CGFloat = 22
                    let chartHeight = max(90, geo.size.height - headerHeight - 2)
                    VStack(alignment: .leading, spacing: 1) {
                        readoutHeader
                            .frame(height: headerHeight, alignment: .topLeading)
                        chart
                            .frame(height: chartHeight)
                    }
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
                }
                .padding(.horizontal, 1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .toolbar(.hidden)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("7-day high and low temperature chart")
        .accessibilityValue(
            "\(store.formatter.temperatureShort(readoutPoint?.high)) high, "
            + "\(store.formatter.temperatureShort(readoutPoint?.low)) low. \(readoutContext)")
    }

    private var readoutHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(store.formatter.temperatureShort(readoutPoint?.high))
                .foregroundStyle(WatchPalette.hot)
            Text("/")
                .foregroundStyle(.tertiary)
            Text(store.formatter.temperatureShort(readoutPoint?.low))
                .foregroundStyle(WatchPalette.cold)
            Text(store.formatter.temperatureUnit)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
            Text(readoutContext)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
            if hasNormalBand {
                Text("avg")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(WatchPalette.historical)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(WatchPalette.historical.opacity(0.22), in: Capsule())
                    .accessibilityLabel("Historical average range shown")
            }
        }
        .font(.system(size: 17, weight: .semibold, design: .rounded))
        .padding(.bottom, 1)
    }

    private var chart: some View {
        Chart {
            ForEach(points) { point in
                if let normalHigh = point.normal?.tMax, let normalLow = point.normal?.tMin {
                    AreaMark(
                        x: .value("Day", point.dateString),
                        yStart: .value("Normal low", store.formatter.temperatureValue(normalLow)),
                        yEnd: .value("Normal high", store.formatter.temperatureValue(normalHigh)))
                    .foregroundStyle(WatchPalette.historical.opacity(0.32))
                    .interpolationMethod(.catmullRom)
                }
            }

            // Dashed edges so the climate band reads even on Always-On.
            ForEach(points) { point in
                if let normalHigh = point.normal?.tMax {
                    LineMark(
                        x: .value("Day", point.dateString),
                        y: .value("Normal high", store.formatter.temperatureValue(normalHigh)),
                        series: .value("Series", "normalHigh"))
                    .foregroundStyle(WatchPalette.historical.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 2]))
                    .interpolationMethod(.catmullRom)
                }
            }
            ForEach(points) { point in
                if let normalLow = point.normal?.tMin {
                    LineMark(
                        x: .value("Day", point.dateString),
                        y: .value("Normal low", store.formatter.temperatureValue(normalLow)),
                        series: .value("Series", "normalLow"))
                    .foregroundStyle(WatchPalette.historical.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 2]))
                    .interpolationMethod(.catmullRom)
                }
            }

            if let todayDateString {
                RectangleMark(x: .value("Today", todayDateString))
                    .foregroundStyle(Color.secondary.opacity(0.1))
            }

            ForEach(points) { point in
                if let high = point.high {
                    LineMark(
                        x: .value("Day", point.dateString),
                        y: .value("High", store.formatter.temperatureValue(high)),
                        series: .value("Series", "high"))
                    .foregroundStyle(WatchPalette.hot.opacity(point.isPast ? 0.4 : 1))
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.catmullRom)
                    PointMark(
                        x: .value("Day", point.dateString),
                        y: .value("High", store.formatter.temperatureValue(high)))
                    .foregroundStyle(WatchPalette.hot.opacity(point.isPast ? 0.4 : 1))
                    .symbolSize(point.isPast ? 12 : 22)
                }
            }

            ForEach(points) { point in
                if let low = point.low {
                    LineMark(
                        x: .value("Day", point.dateString),
                        y: .value("Low", store.formatter.temperatureValue(low)),
                        series: .value("Series", "low"))
                    .foregroundStyle(WatchPalette.cold.opacity(point.isPast ? 0.4 : 1))
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.catmullRom)
                    PointMark(
                        x: .value("Day", point.dateString),
                        y: .value("Low", store.formatter.temperatureValue(low)))
                    .foregroundStyle(WatchPalette.cold.opacity(point.isPast ? 0.4 : 1))
                    .symbolSize(point.isPast ? 12 : 22)
                }
            }

            if let peak = peakHighPoint, let high = peak.high {
                PointMark(
                    x: .value("Day", peak.dateString),
                    y: .value("High", store.formatter.temperatureValue(high)))
                .foregroundStyle(WatchPalette.hot)
                .symbolSize(36)
                .annotation(position: .top, spacing: 1) {
                    extremeLabel(store.formatter.temperatureShort(high), tint: WatchPalette.hot)
                }
            }

            if let trough = troughLowPoint, let low = trough.low {
                PointMark(
                    x: .value("Day", trough.dateString),
                    y: .value("Low", store.formatter.temperatureValue(low)))
                .foregroundStyle(WatchPalette.cold)
                .symbolSize(36)
                .annotation(position: .bottom, spacing: 1) {
                    extremeLabel(store.formatter.temperatureShort(low), tint: WatchPalette.cold)
                }
            }

            if let todayDateString {
                RuleMark(x: .value("Today", todayDateString))
                    .foregroundStyle(.secondary.opacity(0.45))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }

            if let selected, let high = selected.high,
               selected.dateString != peakHighPoint?.dateString {
                RuleMark(x: .value("Selected", selected.dateString))
                    .foregroundStyle(WatchPalette.hot.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                PointMark(
                    x: .value("Day", selected.dateString),
                    y: .value("High", store.formatter.temperatureValue(high)))
                .foregroundStyle(WatchPalette.hot)
                .symbolSize(36)
            }
        }
        .chartXSelection(value: $liveSelection)
        .stickyXSelection(
            live: $liveSelection, sticky: $selectedDate,
            resetOn: points.first?.dateString ?? "")
        .chartXScale(domain: points.map(\.dateString))
        .chartYScale(domain: temperatureDomain)
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks(values: points.map(\.dateString)) { value in
                AxisValueLabel {
                    if let dateString = value.as(String.self),
                       let point = points.first(where: { $0.dateString == dateString }) {
                        Text(point.isToday ? "•" : dayInitial(point))
                            .font(.system(size: 8, weight: point.isToday ? .semibold : .regular))
                            .foregroundStyle(
                                point.isToday
                                    ? .primary
                                    : (point.isPast ? .tertiary : .secondary))
                    }
                }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .onTapGesture { location in
                        guard let plotFrame = proxy.plotFrame else { return }
                        let origin = geo[plotFrame].origin
                        let x = location.x - origin.x
                        if let day: String = proxy.value(atX: x) {
                            selectedDate = day
                        }
                    }
            }
        }
    }

    private func extremeLabel(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(tint)
    }

    private func dayInitial(_ point: ChartSeries.DailyPoint) -> String {
        String(point.label(timeZone: store.locationTimeZone).prefix(1))
    }
}
