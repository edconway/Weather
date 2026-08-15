import Charts
import SwiftUI
import WeatherCore

/// Past 6h + next 6h temperature line with a compact Health-style readout,
/// on-plot high/low labels, a NOW spine, and a slim precipitation strip.
struct HourlyPage: View {
    let store: WatchStore

    @State private var liveSelection: Date?
    @State private var selectedDate: Date?

    private var points: [ChartSeries.HourlyPoint] { store.recentAndNextHours }

    private var nowPoint: ChartSeries.HourlyPoint? {
        points.first(where: { !$0.isPast })
    }

    private var nowDate: Date? { nowPoint?.date }

    private var selected: ChartSeries.HourlyPoint? {
        guard let selectedDate else { return nil }
        return points.min {
            abs($0.date.timeIntervalSince(selectedDate))
                < abs($1.date.timeIntervalSince(selectedDate))
        }
    }

    /// Highest / lowest points in the window — labelled on the plot itself.
    private var peakPoint: ChartSeries.HourlyPoint? {
        points.filter { $0.temperature != nil }
            .max { ($0.temperature ?? -.infinity) < ($1.temperature ?? -.infinity) }
    }

    private var troughPoint: ChartSeries.HourlyPoint? {
        points.filter { $0.temperature != nil }
            .min { ($0.temperature ?? .infinity) < ($1.temperature ?? .infinity) }
    }

    private var temperatureDomain: ClosedRange<Double> {
        let values = points.flatMap { [$0.temperature, $0.normalTemperature] }
            .compactMap { $0 }.map(store.formatter.temperatureValue)
        guard let lo = values.min(), let hi = values.max() else { return 0...1 }
        // Tight domain so the line uses most of the plot height; annotations
        // sit just outside via a little headroom.
        let lower = lo - 0.8
        let upper = hi + 1.8
        return lower < upper ? lower...upper : lower...(lower + 1)
    }

    private var precipitationDomain: ClosedRange<Double> {
        let values = points.map { store.formatter.precipitationValue($0.precipitation) }
        let floor = store.formatter.precipitationValue(0.5)
        return 0...(max(values.max() ?? 0, floor) * 1.4)
    }

    private var axisDates: [Date] {
        guard points.count > 1 else { return points.map(\.date) }
        var dates = [points[0].date, points[points.count / 3].date,
                     points[(2 * points.count) / 3].date, points[points.count - 1].date]
        if let nowDate { dates.append(nowDate) }
        return Array(Set(dates)).sorted()
    }

    private var readoutPrimary: String {
        store.formatter.temperatureShort((selected ?? nowPoint)?.temperature)
    }

    private var readoutContext: String {
        let point = selected ?? nowPoint
        guard let point else { return "—" }
        let when: String
        if selected == nil || point.date == nowDate {
            when = "Now"
        } else {
            when = hourLabel(point.hour)
        }
        let tag = point.isPast ? " · actual" : (selected == nil ? "" : " · forecast")
        if let temp = point.temperature, let normal = point.normalTemperature {
            let delta = temp - normal
            let absDelta = store.formatter.temperatureShort(abs(delta))
            if abs(delta) <= 0.05 {
                return "\(when)\(tag) · near avg"
            }
            let relation = delta > 0 ? "above" : "below"
            return "\(when)\(tag) · \(absDelta) \(relation) avg"
        }
        if let probability = point.probability, probability > 0, !point.isPast {
            return "\(when)\(tag) · \(probability)% rain"
        }
        return "\(when)\(tag)"
    }

    var body: some View {
        Group {
            if points.isEmpty {
                Text("No hourly data")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                GeometryReader { geo in
                    let precipHeight: CGFloat = 14
                    let headerHeight: CGFloat = 22
                    let chartHeight = max(80, geo.size.height - headerHeight - precipHeight - 4)
                    VStack(alignment: .leading, spacing: 1) {
                        readoutHeader
                            .frame(height: headerHeight, alignment: .topLeading)
                        temperatureChart
                            .frame(height: chartHeight)
                        precipitationChart
                            .frame(height: precipHeight)
                    }
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
                }
                .padding(.horizontal, 1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .toolbar(.hidden)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("12-hour temperature and rain chart")
        .accessibilityValue("\(readoutPrimary). \(readoutContext)")
    }

    // MARK: - Readout

    private var readoutHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(readoutPrimary)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(WatchPalette.hot)
            Text(store.formatter.temperatureUnit)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
            Text(readoutContext)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
        }
        .padding(.bottom, 1)
    }

    // MARK: - Temperature

    private var temperatureChart: some View {
        Chart {
            ForEach(points) { point in
                if let value = point.temperature, point.isPast {
                    LineMark(
                        x: .value("Time", point.date),
                        y: .value("Temp", store.formatter.temperatureValue(value)),
                        series: .value("Series", "actual"))
                    .foregroundStyle(WatchPalette.hot)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.catmullRom)
                }
            }

            ForEach(points) { point in
                if let value = point.temperature, !point.isPast || isLastPast(point) {
                    LineMark(
                        x: .value("Time", point.date),
                        y: .value("Temp", store.formatter.temperatureValue(value)),
                        series: .value("Series", "forecast"))
                    .foregroundStyle(WatchPalette.hot)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round, dash: [4, 3]))
                    .interpolationMethod(.catmullRom)
                }
            }

            ForEach(points) { point in
                if let normal = point.normalTemperature {
                    LineMark(
                        x: .value("Time", point.date),
                        y: .value("Normal", store.formatter.temperatureValue(normal)),
                        series: .value("Series", "normal"))
                    .foregroundStyle(WatchPalette.historical.opacity(0.55))
                    .lineStyle(StrokeStyle(lineWidth: 1.25, dash: [3, 2]))
                    .interpolationMethod(.catmullRom)
                }
            }

            if let nowDate {
                RuleMark(x: .value("Now", nowDate))
                    .foregroundStyle(.secondary.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }

            if let peak = peakPoint, let value = peak.temperature {
                PointMark(
                    x: .value("Time", peak.date),
                    y: .value("Temp", store.formatter.temperatureValue(value)))
                .foregroundStyle(WatchPalette.hot)
                .symbolSize(28)
                .annotation(position: .top, spacing: 1) {
                    extremeLabel(store.formatter.temperatureShort(value), tint: WatchPalette.hot)
                }
            }

            if let trough = troughPoint, let value = trough.temperature,
               trough.id != peakPoint?.id {
                PointMark(
                    x: .value("Time", trough.date),
                    y: .value("Temp", store.formatter.temperatureValue(value)))
                .foregroundStyle(WatchPalette.hot)
                .symbolSize(28)
                .annotation(position: .bottom, spacing: 1) {
                    extremeLabel(store.formatter.temperatureShort(value), tint: WatchPalette.hot)
                }
            }

            if let selected, let value = selected.temperature,
               selected.id != peakPoint?.id, selected.id != troughPoint?.id {
                RuleMark(x: .value("Selected", selected.date))
                    .foregroundStyle(WatchPalette.hot.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                PointMark(
                    x: .value("Time", selected.date),
                    y: .value("Temp", store.formatter.temperatureValue(value)))
                .foregroundStyle(WatchPalette.hot)
                .symbolSize(40)
            }
        }
        .chartXSelection(value: $liveSelection)
        .stickyXSelection(
            live: $liveSelection, sticky: $selectedDate,
            resetOn: points.first?.timeString ?? "")
        .chartYScale(domain: temperatureDomain)
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks(values: axisDates) { value in
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        let isNow = date == nowDate
                        Text(isNow ? "Now" : hourLabel(Calendar.hour(of: date, in: store.locationTimeZone)))
                            .font(.system(size: 8, weight: isNow ? .semibold : .regular))
                            .foregroundStyle(isNow ? .primary : .tertiary)
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
                        if let date: Date = proxy.value(atX: x) {
                            selectedDate = date
                        }
                    }
            }
        }
    }

    // MARK: - Precipitation

    private var precipitationChart: some View {
        Chart(points) { point in
            BarMark(
                x: .value("Time", point.date, unit: .hour),
                y: .value("Precip", store.formatter.precipitationValue(point.precipitation)))
            .foregroundStyle(WatchPalette.rain.opacity(point.isPast ? 0.35 : 0.8))
            .cornerRadius(1)
        }
        .chartXSelection(value: $liveSelection)
        .chartYScale(domain: precipitationDomain)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
    }

    private func extremeLabel(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(tint)
    }

    private func isLastPast(_ point: ChartSeries.HourlyPoint) -> Bool {
        guard let firstFuture = points.firstIndex(where: { !$0.isPast }), firstFuture > 0
        else { return false }
        return point.id == points[firstFuture - 1].id
    }

    private func hourLabel(_ hour: Int) -> String {
        switch hour {
        case 0: return "12a"
        case 12: return "12p"
        case ..<12: return "\(hour)a"
        default: return "\(hour - 12)p"
        }
    }
}

private extension Calendar {
    static func hour(of date: Date, in timeZone: TimeZone) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.component(.hour, from: date)
    }
}
