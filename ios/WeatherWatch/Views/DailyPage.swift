import SwiftUI
import WeatherCore

/// 7 forecast days as compact rows: weekday, symbol, lo–hi bar vs the historical band.
struct DailyPage: View {
    let store: WatchStore

    private var points: [ChartSeries.DailyPoint] { store.forecastDays }

    private var domain: ClosedRange<Double> {
        let values = points.flatMap { [$0.high, $0.low, $0.normal?.tMax, $0.normal?.tMin] }
            .compactMap { $0 }.map(store.formatter.temperatureValue)
        guard let lo = values.min(), let hi = values.max() else { return 0...1 }
        let lower = (lo - 1).rounded(.down)
        let upper = (hi + 1).rounded(.up)
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
                List(points) { point in
                    HStack(spacing: 6) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(point.isToday ? "Today" : point.label(timeZone: store.locationTimeZone))
                                .font(.system(size: 12, weight: point.isToday ? .semibold : .regular))
                            Image(systemName: point.symbolName)
                                .symbolRenderingMode(.multicolor)
                                .font(.system(size: 12))
                        }
                        .frame(width: 44, alignment: .leading)

                        DayRangeBar(
                            low: point.low.map(store.formatter.temperatureValue),
                            high: point.high.map(store.formatter.temperatureValue),
                            normalLow: point.normal?.tMin.map(store.formatter.temperatureValue),
                            normalHigh: point.normal?.tMax.map(store.formatter.temperatureValue),
                            domain: domain)

                        VStack(alignment: .trailing, spacing: 0) {
                            Text(store.formatter.temperatureShort(point.high))
                                .foregroundStyle(Palette.hot)
                            Text(store.formatter.temperatureShort(point.low))
                                .foregroundStyle(Palette.cold)
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 32, alignment: .trailing)
                    }
                    .listRowBackground(Color.clear)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(dailyLabel(point))
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("7 Days")
        .accessibilityElement(children: .contain)
        .accessibilityLabel("7-day high and low temperature")
    }

    private func dailyLabel(_ point: ChartSeries.DailyPoint) -> String {
        let day = point.isToday ? "Today" : point.label(timeZone: store.locationTimeZone)
        return "\(day), \(store.formatter.temperature(point.low)) to \(store.formatter.temperature(point.high))"
    }
}

/// Horizontal lo–hi bar with a grey normal-range tick underneath.
private struct DayRangeBar: View {
    let low: Double?
    let high: Double?
    let normalLow: Double?
    let normalHigh: Double?
    let domain: ClosedRange<Double>

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let span = domain.upperBound - domain.lowerBound
            func x(_ value: Double) -> CGFloat {
                guard span > 0 else { return 0 }
                return CGFloat((value - domain.lowerBound) / span) * width
            }
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.12))
                if let normalLow, let normalHigh {
                    Capsule()
                        .fill(Palette.historical.opacity(0.35))
                        .frame(width: max(3, x(normalHigh) - x(normalLow)))
                        .offset(x: x(normalLow))
                }
                if let low, let high {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Palette.cold, Palette.hot],
                                startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(3, x(high) - x(low)))
                        .offset(x: x(low))
                }
            }
        }
        .frame(height: 8)
    }
}
