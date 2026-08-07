import Charts
import SwiftUI
import WeatherCore

/// §9.2 — the next 12 hours as a chart: an icon/temperature row, a bold
/// gradient temperature line, and a slim precipitation strip — styled after
/// watchOS's own charts (Activity, Heart Rate) rather than the list this used
/// to be. No gridlines, no y-axis, large glanceable numbers, color doing the
/// work.
struct HourlyPage: View {
    let store: WatchStore

    @State private var liveSelection: Date?
    @State private var selectedDate: Date?

    private var points: [ChartSeries.HourlyPoint] { store.next12Hours }

    private var selected: ChartSeries.HourlyPoint? {
        guard let selectedDate else { return nil }
        return points.min {
            abs($0.date.timeIntervalSince(selectedDate))
                < abs($1.date.timeIntervalSince(selectedDate))
        }
    }

    /// A handful of hours get an icon/temperature callout, evenly spread
    /// rather than on every point — this is what keeps a 12-point line from
    /// turning into a wall of glyphs on a 40mm screen.
    private var tickIndices: [Int] {
        guard points.count > 1 else { return points.indices.map { $0 } }
        let count = min(4, points.count)
        return (0..<count).map { i in
            min(points.count - 1, i * (points.count - 1) / (count - 1))
        }
    }

    private var temperatureDomain: ClosedRange<Double> {
        // Includes the 5-yr average so the dashed line never clips at the
        // edge of the domain on days that run unusually hot or cold.
        let values = points.flatMap { [$0.temperature, $0.normalTemperature] }
            .compactMap { $0 }.map(store.formatter.temperatureValue)
        guard let lo = values.min(), let hi = values.max() else { return 0...1 }
        let lower = (lo - 2).rounded(.down)
        let upper = (hi + 2).rounded(.up)
        return lower < upper ? lower...upper : lower...(lower + 1)
    }

    private var precipitationDomain: ClosedRange<Double> {
        let values = points.map { store.formatter.precipitationValue($0.precipitation) }
        let floor = store.formatter.precipitationValue(0.5)
        return 0...(max(values.max() ?? 0, floor) * 1.4)
    }

    var body: some View {
        Group {
            if points.isEmpty {
                Text("No hourly data")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 3) {
                    tickRow
                    temperatureChart
                        .frame(maxHeight: .infinity)
                    precipitationChart
                        .frame(height: 22)
                }
                .padding(.horizontal, 2)
            }
        }
        .navigationTitle("Hourly")
        .accessibilityElement(children: .contain)
        .accessibilityLabel("12-hour temperature and rain chance chart")
    }

    // MARK: - Icon/temperature row

    /// A plain HStack, not chart geometry — four evenly-spaced call-outs read
    /// clearly as "start / +a few hours / +more / end" without needing to
    /// track exact pixel positions on the line beneath it.
    private var tickRow: some View {
        HStack(spacing: 0) {
            ForEach(tickIndices, id: \.self) { index in
                let point = points[index]
                VStack(spacing: 1) {
                    Image(systemName: point.symbolName)
                        .symbolRenderingMode(.multicolor)
                        .font(.system(size: 11))
                    Text(store.formatter.temperatureShort(point.temperature))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(index == 0 ? .primary : .secondary)
                    Text(hourLabel(point.hour))
                        .font(.system(size: 8))
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Temperature

    private var temperatureChart: some View {
        Chart {
            ForEach(points) { point in
                if let value = point.temperature {
                    let converted = store.formatter.temperatureValue(value)
                    AreaMark(
                        x: .value("Time", point.date),
                        yStart: .value("Baseline", temperatureDomain.lowerBound),
                        yEnd: .value("Temp", converted))
                    .foregroundStyle(
                        .linearGradient(
                            colors: [WatchPalette.hot.opacity(0.45), WatchPalette.hot.opacity(0.02)],
                            startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.catmullRom)

                    LineMark(
                        x: .value("Time", point.date),
                        y: .value("Temp", converted))
                    .foregroundStyle(WatchPalette.hot)
                    .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.catmullRom)
                }
            }

            // Dashed 5-yr average, as per the iOS app's HourlyTempChart —
            // drawn on top of the solid line so the comparison reads clearly.
            ForEach(points) { point in
                if let normal = point.normalTemperature {
                    LineMark(
                        x: .value("Time", point.date),
                        y: .value("Normal", store.formatter.temperatureValue(normal)),
                        series: .value("Series", "normal"))
                    .foregroundStyle(WatchPalette.historical.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    .interpolationMethod(.catmullRom)
                }
            }

            if let selected, let value = selected.temperature {
                RuleMark(x: .value("Selected", selected.date))
                    .foregroundStyle(.white.opacity(0.25))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                PointMark(
                    x: .value("Time", selected.date),
                    y: .value("Temp", store.formatter.temperatureValue(value)))
                .foregroundStyle(.white)
                .symbolSize(64)
                .annotation(position: .top, spacing: 2) {
                    scrubCard(selected)
                }
            }
        }
        .chartXSelection(value: $liveSelection)
        .stickyXSelection(live: $liveSelection, sticky: $selectedDate, resetOn: points.first?.timeString ?? "")
        .chartYScale(domain: temperatureDomain)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        // `chartXSelection`'s built-in gesture did not respond to taps in the
        // watchOS simulator; this explicit tap handler is a belt-and-braces
        // fallback so scrubbing works regardless.
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .onTapGesture { location in
                        let origin = geo[proxy.plotFrame!].origin
                        let x = location.x - origin.x
                        if let date: Date = proxy.value(atX: x) {
                            selectedDate = date
                        }
                    }
            }
        }
    }

    private func scrubCard(_ point: ChartSeries.HourlyPoint) -> some View {
        VStack(spacing: 0) {
            Text(hourLabel(point.hour))
                .font(.system(size: 9, weight: .semibold))
            if let normal = point.normalTemperature {
                Text(store.formatter.temperatureShort(normal))
                    .font(.system(size: 9))
                    .foregroundStyle(WatchPalette.historical)
            }
            if let probability = point.probability, probability > 0 {
                Text("\(probability)%")
                    .font(.system(size: 9))
                    .foregroundStyle(WatchPalette.rain)
            }
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Precipitation

    private var precipitationChart: some View {
        Chart(points) { point in
            BarMark(
                x: .value("Time", point.date, unit: .hour),
                y: .value("Precip", store.formatter.precipitationValue(point.precipitation)))
            .foregroundStyle(WatchPalette.rain.opacity(point.isPast ? 0.4 : 0.85))
            .cornerRadius(1)
        }
        .chartXSelection(value: $liveSelection)
        .chartYScale(domain: precipitationDomain)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
    }

    /// Compact form of the shared hour label — "12a", "3p", "Noon" is too wide here.
    private func hourLabel(_ hour: Int) -> String {
        switch hour {
        case 0: return "12a"
        case 12: return "12p"
        case ..<12: return "\(hour)a"
        default: return "\(hour - 12)p"
        }
    }
}
