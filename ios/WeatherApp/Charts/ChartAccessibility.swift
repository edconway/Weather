import Accessibility
import SwiftUI
import WeatherCore

/// §8.5 — AudioGraph descriptors for the two temperature charts.
///
/// VoiceOver's "Play Audio Graph" action turns each series into a tone sweep,
/// which is the only practical way to perceive a 14-point trend without sight.
struct DailyTempChartDescriptor: AXChartDescriptorRepresentable {
    let points: [ChartSeries.DailyPoint]
    let series: DailyTempChart.Series
    let formatter: UnitFormatter
    let timeZone: TimeZone

    private func high(_ point: ChartSeries.DailyPoint) -> Double? {
        series == .temperature ? point.high : point.wetBulbHigh
    }

    private func low(_ point: ChartSeries.DailyPoint) -> Double? {
        series == .temperature ? point.low : point.wetBulbLow
    }

    func makeChartDescriptor() -> AXChartDescriptor {
        let labels = points.map { $0.label(timeZone: timeZone) }
        let values = points.flatMap { [high($0), low($0)] }.compactMap { $0 }
            .map(formatter.temperatureValue)
        let lower = values.min() ?? 0
        let upper = values.max() ?? 1

        let xAxis = AXCategoricalDataAxisDescriptor(
            title: "Day",
            categoryOrder: labels)

        let yAxis = AXNumericDataAxisDescriptor(
            title: "Temperature",
            range: lower...max(upper, lower + 1),
            gridlinePositions: []
        ) { value in
            "\(Int(value.rounded()))\(formatter.temperatureUnit)"
        }

        func dataSeries(
            name: String, value: @escaping (ChartSeries.DailyPoint) -> Double?
        ) -> AXDataSeriesDescriptor {
            AXDataSeriesDescriptor(
                name: name,
                isContinuous: true,
                dataPoints: points.compactMap { point in
                    guard let raw = value(point) else { return nil }
                    return AXDataPoint(
                        x: point.label(timeZone: timeZone),
                        y: formatter.temperatureValue(raw))
                })
        }

        return AXChartDescriptor(
            title: series == .temperature
                ? "14-day temperature, high and low"
                : "14-day wet bulb, high and low",
            summary: nil,
            xAxis: xAxis,
            yAxis: yAxis,
            additionalAxes: [],
            series: [
                dataSeries(name: "High", value: high),
                dataSeries(name: "Low", value: low)
            ])
    }
}

struct HourlyTempChartDescriptor: AXChartDescriptorRepresentable {
    let points: [ChartSeries.HourlyPoint]
    let series: HourlyTempChart.Series
    let formatter: UnitFormatter

    private func value(_ point: ChartSeries.HourlyPoint) -> Double? {
        series == .temperature ? point.temperature : point.wetBulb
    }

    func makeChartDescriptor() -> AXChartDescriptor {
        let values = points.compactMap(value).map(formatter.temperatureValue)
        let lower = values.min() ?? 0
        let upper = values.max() ?? 1
        let labels = points.map { "\(hourLabel($0.hour))" }

        let xAxis = AXCategoricalDataAxisDescriptor(
            title: "Time", categoryOrder: labels)

        let yAxis = AXNumericDataAxisDescriptor(
            title: "Temperature",
            range: lower...max(upper, lower + 1),
            gridlinePositions: []
        ) { value in
            "\(Int(value.rounded()))\(formatter.temperatureUnit)"
        }

        let dataPoints = points.compactMap { point -> AXDataPoint? in
            guard let raw = value(point) else { return nil }
            return AXDataPoint(
                x: hourLabel(point.hour),
                y: formatter.temperatureValue(raw))
        }

        return AXChartDescriptor(
            title: series == .temperature
                ? "48-hour temperature"
                : "48-hour wet bulb",
            summary: nil,
            xAxis: xAxis,
            yAxis: yAxis,
            additionalAxes: [],
            series: [
                AXDataSeriesDescriptor(
                    name: series == .temperature ? "Temperature" : "Wet bulb",
                    isContinuous: true,
                    dataPoints: dataPoints)
            ])
    }
}
