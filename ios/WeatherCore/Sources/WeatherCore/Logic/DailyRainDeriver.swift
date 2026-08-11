import Foundation

/// Per-forecast-day rain normals (§6.5) — a port of `deriveDailyRain`.
///
/// Index 0 is today, which is what the rain anomaly badge reads.
public enum DailyRainDeriver {

    public static func derive(
        forecast: ForecastResponse,
        climatology: Climatology,
        todayIndex: Int
    ) -> [DailyRainNormal] {
        let daily = forecast.daily
        let pools = Array(climatology.byMMDD)
        // PLAN DEVIATION: the web app hardcodes `t0 = min(7, len-1)` here even
        // though it string-matches everywhere else. We pass in the string-matched
        // index instead, per §14.1.
        let start = min(max(0, todayIndex), max(0, daily.time.count - 1))
        let end = min(start + 7, daily.time.count)
        guard start < end else { return [] }

        return (start..<end).map { index in
            let dateString = daily.time[index]
            let mmdd = String(dateString.dropFirst(5).prefix(5))

            var rains: [Double] = []
            for (poolMMDD, pool) in pools where MMDD.distance(mmdd, poolMMDD) <= 3 {
                rains.append(contentsOf: pool.rains)
            }

            return DailyRainNormal(
                date: dateString,
                forecastMm: daily.precipitationSum.value(at: index) ?? 0,
                probabilityMax: daily.precipitationProbabilityMax.value(at: index),
                histMeanMm: Stats.meanOrZero(rains),
                histMedianMm: Stats.median(rains),
                wetDayProbability: Stats.wetShare(rains),
                p90Mm: Stats.p90(rains))
        }
    }
}
