import Charts
import SwiftUI
import WeatherCore

/// Next 12 hours: watch-native gradient line, thin 5-yr avg, rain strip, Digital Crown scrub.
struct HourlyPage: View {
    let store: WatchStore

    @State private var liveSelection: Date?
    @State private var selectedDate: Date?
    @State private var crownValue: Double = 0
    @FocusState private var crownFocused: Bool

    private var points: [ChartSeries.HourlyPoint] { store.next12Hours }

    private var selected: ChartSeries.HourlyPoint? {
        guard let selectedDate else { return nil }
        return points.min {
            abs($0.date.timeIntervalSince(selectedDate))
                < abs($1.date.timeIntervalSince(selectedDate))
        }
    }

    private var tickIndices: [Int] {
        guard points.count > 1 else { return points.indices.map { $0 } }
        let count = min(4, points.count)
        return (0..<count).map { i in
            min(points.count - 1, i * (points.count - 1) / (count - 1))
        }
    }

    private var temperatureDomain: ClosedRange<Double> {
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
                .focusable()
                .focused($crownFocused)
                .digitalCrownRotation(
                    $crownValue,
                    from: 0,
                    through: Double(max(0, points.count - 1)),
                    by: 1.0,
                    sensitivity: .medium,
                    isContinuous: false,
                    isHapticFeedbackEnabled: true)
                .onAppear {
                    crownFocused = true
                    crownValue = 0
                    selectedDate = points.first?.date
                }
                .onChange(of: crownValue) { _, value in
                    let index = min(max(0, Int(value.rounded())), max(0, points.count - 1))
                    if points.indices.contains(index) {
                        selectedDate = points[index].date
                    }
                }
            }
        }
        .navigationTitle("Hourly")
        .accessibilityElement(children: .contain)
        .accessibilityLabel("12-hour temperature and rain chance chart")
    }

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
                            colors: [Palette.hot.opacity(0.45), Palette.hot.opacity(0.02)],
                            startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.catmullRom)

                    LineMark(
                        x: .value("Time", point.date),
                        y: .value("Temp", converted))
                    .foregroundStyle(Palette.hot)
                    .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.catmullRom)
                }
            }

            ForEach(points) { point in
                if let normal = point.normalTemperature {
                    LineMark(
                        x: .value("Time", point.date),
                        y: .value("Normal", store.formatter.temperatureValue(normal)),
                        series: .value("Series", "normal"))
                    .foregroundStyle(Palette.historical.opacity(0.6))
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
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                guard let frame = proxy.plotFrame else { return }
                                let origin = geo[frame].origin
                                let x = value.location.x - origin.x
                                if let date: Date = proxy.value(atX: x) {
                                    selectedDate = date
                                }
                            }
                    )
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
                    .foregroundStyle(Palette.historical)
            }
            if let probability = point.probability, probability > 0 {
                Text("\(probability)%")
                    .font(.system(size: 9))
                    .foregroundStyle(Palette.rainSeries)
            }
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
    }

    private var precipitationChart: some View {
        Chart(points) { point in
            BarMark(
                x: .value("Time", point.date, unit: .hour),
                y: .value("Precip", store.formatter.precipitationValue(point.precipitation)))
            .foregroundStyle(Palette.rainSeries.opacity(point.isPast ? 0.4 : 0.85))
            .cornerRadius(1)
        }
        .chartXSelection(value: $liveSelection)
        .chartYScale(domain: precipitationDomain)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
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
