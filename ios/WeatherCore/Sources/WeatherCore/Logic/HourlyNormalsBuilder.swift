import Foundation

/// Buckets five years of ±7-day hourly archive samples by hour of day (§6.6) —
/// a port of the reduction inside `getHourlyNormals`.
public enum HourlyNormalsBuilder {

    public static func build(
        windows: [ArchiveResponse?], thisYear: Int
    ) -> HourlyNormals {
        var tempSums = [Double](repeating: 0, count: 24)
        var tempCounts = [Int](repeating: 0, count: 24)
        var wetBulbSums = [Double](repeating: 0, count: 24)
        var wetBulbCounts = [Int](repeating: 0, count: 24)
        var rainSums = [Double](repeating: 0, count: 24)
        var rainCounts = [Int](repeating: 0, count: 24)
        var wetCounts = [Int](repeating: 0, count: 24)
        var rainValues = [[Double]](repeating: [], count: 24)

        for window in windows {
            guard let hourly = window?.hourly else { continue }
            for (index, timeString) in hourly.time.enumerated() {
                // "YYYY-MM-DDTHH:mm" — characters 11..<13 are the hour.
                guard timeString.count >= 13 else { continue }
                let hourText = timeString.dropFirst(11).prefix(2)
                guard let hour = Int(hourText), (0..<24).contains(hour) else { continue }

                if let value = hourly.temperature2m.value(at: index) {
                    tempSums[hour] += value
                    tempCounts[hour] += 1
                }
                if let value = hourly.wetBulbTemperature2m.value(at: index) {
                    wetBulbSums[hour] += value
                    wetBulbCounts[hour] += 1
                }
                if let value = hourly.precipitation.value(at: index) {
                    rainSums[hour] += value
                    rainCounts[hour] += 1
                    if value >= 0.1 { wetCounts[hour] += 1 }
                    rainValues[hour].append(value)
                }
            }
        }

        let yearStart = thisYear - 5
        let yearEnd = thisYear - 1

        // Temperatures: no samples → nil. Rain: no samples → 0 mm.
        let temp = HourAverages(
            avgByHour: (0..<24).map { tempCounts[$0] > 0 ? tempSums[$0] / Double(tempCounts[$0]) : nil },
            yearStart: yearStart, yearEnd: yearEnd)
        let wetBulb = HourAverages(
            avgByHour: (0..<24).map { wetBulbCounts[$0] > 0 ? wetBulbSums[$0] / Double(wetBulbCounts[$0]) : nil },
            yearStart: yearStart, yearEnd: yearEnd)
        let rain = RainHourNormals(
            avgByHour: (0..<24).map { rainCounts[$0] > 0 ? rainSums[$0] / Double(rainCounts[$0]) : 0 },
            wetHourProbabilityByHour: (0..<24).map {
                rainCounts[$0] > 0 ? Double(wetCounts[$0]) / Double(rainCounts[$0]) : 0
            },
            p90ByHour: (0..<24).map { Stats.p90(rainValues[$0]) },
            yearStart: yearStart, yearEnd: yearEnd)

        return HourlyNormals(temp: temp, wetBulb: wetBulb, rain: rain)
    }
}
