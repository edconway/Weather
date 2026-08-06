import Foundation

/// Cumulative year-to-date rainfall vs. the historical average (§6.7) — a port
/// of `getRainYTD`.
public enum YTDRainBuilder {

    /// One point of the dashed current-year projection drawn past `latestDate`.
    public struct ProjectionPoint: Sendable, Equatable {
        public let date: String        // "YYYY-MM-DD"
        public let cumulative: Double  // mm

        public init(date: String, cumulative: Double) {
            self.date = date
            self.cumulative = cumulative
        }
    }

    public static func build(
        response: ArchiveResponse,
        now: Date,
        timeZone: TimeZone,
        startYear: Int = 2000
    ) -> YTDRain? {
        guard let daily = response.daily else { return nil }
        let dateKit = DateKit(timeZone: timeZone)
        let thisYear = dateKit.year(now)
        let todayString = dateKit.dateString(now)

        // year → "MM-DD" → mm
        var byYear: [Int: [String: Double]] = [:]
        // Dates that actually carry a value, used to find the archive's true edge.
        var lastDateWithData: String?

        for (index, timeString) in daily.time.enumerated() {
            guard timeString.count >= 10, let year = Int(timeString.prefix(4)) else { continue }
            let mmdd = String(timeString.dropFirst(5).prefix(5))
            let value = daily.precipitationSum.value(at: index)
            byYear[year, default: [:]][mmdd] = value ?? 0
            if value != nil, timeString <= todayString,
               lastDateWithData.map({ timeString > $0 }) ?? true {
                lastDateWithData = timeString
            }
        }

        // Labels: Jan 1 of this year through today, location-local.
        var labels: [String] = []
        var cursor = dateKit.noon(year: thisYear, month: 1, day: 1)
        while dateKit.dateString(cursor) <= todayString {
            labels.append(dateKit.monthDayString(cursor))
            cursor = dateKit.addingDays(1, to: cursor)
        }
        guard !labels.isEmpty else { return nil }

        // Current year's running cumulative; a day with no archive row counts 0.
        let currentYearValues = byYear[thisYear] ?? [:]
        var runningTotal = 0.0
        let cumCurrentYear = labels.map { mmdd -> Double in
            runningTotal += currentYearValues[mmdd] ?? 0
            return runningTotal
        }

        let histYears = byYear.keys.filter { $0 >= startYear && $0 < thisYear }.sorted()
        var histCumByYear: [Int: [Double]] = [:]
        for year in histYears {
            let values = byYear[year] ?? [:]
            var total = 0.0
            histCumByYear[year] = labels.map { mmdd in
                total += values[mmdd] ?? 0
                return total
            }
        }
        let cumHistAvg = labels.indices.map { index -> Double in
            let values = histYears.compactMap { histCumByYear[$0]?.at(index) }
            guard !values.isEmpty else { return 0 }
            return values.reduce(0, +) / Double(values.count)
        }

        // PLAN DEVIATION §6.7: the web app takes the last date present in the
        // response; the plan asks for the last date that actually *has* data.
        // With Open-Meteo's 2–5 day publication lag those differ, and the plan's
        // definition is the one that makes the "through {date}" subtitle honest.
        let latestDate = lastDateWithData ?? todayString

        // Historical-average extension over the next (up to) 7 calendar days,
        // stopping at year end.
        var extendedTotal = cumHistAvg.last ?? 0
        var cumHistAvgExt: [Double] = []
        if let latest = dateKit.date(fromDayString: latestDate) {
            for step in 1...7 {
                let day = dateKit.addingDays(step, to: latest)
                if dateKit.year(day) > thisYear { break }
                let mmdd = dateKit.monthDayString(day)
                let values = histYears.map { byYear[$0]?[mmdd] ?? 0 }
                let mean = values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
                extendedTotal += mean
                cumHistAvgExt.append(extendedTotal)
            }
        }

        return YTDRain(
            labels: labels,
            cumCurrentYear: cumCurrentYear,
            cumHistAvg: cumHistAvg,
            cumHistAvgExt: cumHistAvgExt,
            thisYear: thisYear,
            startYear: startYear,
            histYears: histYears.count,
            latestDate: latestDate)
    }

    /// The dashed current-year projection: forecast daily totals for the days
    /// after `latestDate`, accumulated on top of the last actual value.
    public static func projection(
        forecast: ForecastResponse, ytd: YTDRain
    ) -> [ProjectionPoint] {
        guard let startIndex = forecast.daily.time.firstIndex(where: { $0 > ytd.latestDate })
        else { return [] }

        var total = ytd.cumCurrentYear.last ?? 0
        var points: [ProjectionPoint] = []
        let end = min(startIndex + 7, forecast.daily.time.count)
        for index in startIndex..<end {
            total += forecast.daily.precipitationSum.value(at: index) ?? 0
            points.append(ProjectionPoint(date: forecast.daily.time[index], cumulative: total))
        }
        return points
    }
}
