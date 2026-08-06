import Foundation

/// Builds `Climatology` from the single 10-year daily archive response (§6.3).
///
/// Port of `getClimatology`'s reduction step. The monthly figures use **two-level
/// averaging**: each year's month is reduced to its own mean first, and those
/// per-year means are then averaged. Flattening every day into one pool gives a
/// different (and wrong) answer whenever months have unequal coverage.
public enum ClimatologyBuilder {

    public static func build(
        response: ArchiveResponse, thisYear: Int
    ) -> Climatology? {
        guard let daily = response.daily else { return nil }

        struct MonthYearBucket {
            var tMax: [Double] = []
            var tMin: [Double] = []
            var rain: Double = 0
        }

        var byMonthYear: [String: MonthYearBucket] = [:]
        var byMMDD: [String: DayPool] = [:]

        for (index, timeString) in daily.time.enumerated() {
            guard timeString.count >= 10 else { continue }
            let monthKey = String(timeString.prefix(7))     // "YYYY-MM"
            let mmdd = String(timeString.dropFirst(5).prefix(5))  // "MM-DD"

            let tMax = daily.temperature2mMax.value(at: index)
            let tMin = daily.temperature2mMin.value(at: index)
            let wbMax = daily.wetBulbTemperature2mMax.value(at: index)
            let wbMin = daily.wetBulbTemperature2mMin.value(at: index)
            let rain = daily.precipitationSum.value(at: index)

            var monthBucket = byMonthYear[monthKey] ?? MonthYearBucket()
            if let tMax { monthBucket.tMax.append(tMax) }
            if let tMin { monthBucket.tMin.append(tMin) }
            // Monthly rainfall is a **total**, not a mean.
            if let rain { monthBucket.rain += rain }
            byMonthYear[monthKey] = monthBucket

            var dayPool = byMMDD[mmdd] ?? DayPool()
            if let tMax { dayPool.maxes.append(tMax) }
            if let tMin { dayPool.mins.append(tMin) }
            if let wbMax { dayPool.wbMaxes.append(wbMax) }
            if let wbMin { dayPool.wbMins.append(wbMin) }
            if let rain { dayPool.rains.append(rain) }
            byMMDD[mmdd] = dayPool
        }

        // Level 2: average the per-year month means (and per-year month totals).
        var monthMaxMeans = [[Double]](repeating: [], count: 12)
        var monthMinMeans = [[Double]](repeating: [], count: 12)
        var monthRainTotals = [[Double]](repeating: [], count: 12)

        for (monthKey, bucket) in byMonthYear {
            guard let month = Int(monthKey.suffix(2)), (1...12).contains(month) else { continue }
            let slot = month - 1
            if let mean = Stats.mean(bucket.tMax) { monthMaxMeans[slot].append(mean) }
            if let mean = Stats.mean(bucket.tMin) { monthMinMeans[slot].append(mean) }
            monthRainTotals[slot].append(bucket.rain)
        }

        let months = (0..<12).map { slot in
            MonthNormal(
                tMax: Stats.mean(monthMaxMeans[slot]),
                tMin: Stats.mean(monthMinMeans[slot]),
                rain: Stats.mean(monthRainTotals[slot]))
        }

        return Climatology(
            months: months,
            byMMDD: byMMDD,
            yearStart: thisYear - 10,
            yearEnd: thisYear - 1)
    }
}
