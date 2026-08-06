import Foundation

/// Pre-derived chart inputs (§8.4). All values stay metric; views convert.
///
/// Assembling these here rather than in the chart views keeps the UI targets to
/// layout only, and makes "is this point actual or forecast?" testable rather
/// than an inline index comparison repeated eight times.
public enum ChartSeries {

    // MARK: - Hourly

    public struct HourlyPoint: Identifiable, Sendable, Equatable {
        public let id: Int
        /// Raw API string, kept for scrub annotations.
        public let timeString: String
        public let date: Date
        public let hour: Int
        /// Strictly before the current hour — the web's "· actual" tag.
        public let isPast: Bool
        public let temperature: Double?
        public let wetBulb: Double?
        public let precipitation: Double
        public let probability: Int?
        public let normalTemperature: Double?
        public let normalWetBulb: Double?
        public let normalRain: Double?
        public let rainP90: Double?
        public let conditionCode: Int?
        public let isDay: Bool

        public var condition: WMOCode.Descriptor { WMOCode.describe(conditionCode) }
        public var symbolName: String { condition.symbol(isDay: isDay) }
    }

    /// The full 72-hour window (24 past + 48 forecast).
    ///
    /// PLAN DEVIATION: the web app re-slices this to ±24 h because `past_days=7`
    /// used to override `past_hours`. The API now honours `past_hours=24` /
    /// `forecast_hours=48` and returns exactly 72 points, which is what §8.4.1
    /// asks for, so the window is used as-is.
    public static func hourly(
        forecast: ForecastResponse,
        conditions: CurrentConditions,
        normals: HourlyNormals?
    ) -> [HourlyPoint] {
        let dateKit = DateKit(timeZone: forecast.locationTimeZone)
        let hourly = forecast.hourly

        return hourly.time.enumerated().compactMap { index, timeString in
            guard let date = dateKit.date(fromHourString: timeString),
                  timeString.count >= 13,
                  let hour = Int(timeString.dropFirst(11).prefix(2))
            else { return nil }

            return HourlyPoint(
                id: index,
                timeString: timeString,
                date: date,
                hour: hour,
                isPast: index < conditions.nowIndex,
                temperature: hourly.temperature2m.value(at: index),
                wetBulb: hourly.wetBulbTemperature2m.value(at: index),
                precipitation: hourly.precipitation.value(at: index) ?? 0,
                probability: hourly.precipitationProbability.value(at: index),
                normalTemperature: normals?.temp.avgByHour.value(at: hour) ?? nil,
                normalWetBulb: normals?.wetBulb.avgByHour.value(at: hour) ?? nil,
                normalRain: normals?.rain.avgByHour.at(hour),
                rainP90: normals?.rain.p90ByHour.at(hour),
                conditionCode: hourly.weatherCode.value(at: index),
                isDay: (hourly.isDay.value(at: index) ?? 1) != 0)
        }
    }

    // MARK: - Daily

    public struct DailyPoint: Identifiable, Sendable, Equatable {
        public let id: Int
        public let dateString: String
        public let date: Date
        public let isToday: Bool
        /// Before today — drawn as "actual".
        public let isPast: Bool
        public let high: Double?
        public let low: Double?
        public let wetBulbHigh: Double?
        public let wetBulbLow: Double?
        public let precipitation: Double
        public let probability: Int?
        /// Rolling ±3-day normal for this calendar day, once climatology lands.
        public let normal: DayNormal?
        /// Rain normals, only present for today and the six forecast days.
        public let rainNormal: DailyRainNormal?
        public let conditionCode: Int?

        /// Days have no day/night distinction, so this always picks the day
        /// symbol variant.
        public var condition: WMOCode.Descriptor { WMOCode.describe(conditionCode) }
        public var symbolName: String { condition.symbol(isDay: true) }

        /// "Today" or a short weekday, matching the web's x labels.
        public func label(timeZone: TimeZone) -> String {
            if isToday { return "Today" }
            var style = Date.FormatStyle().weekday(.abbreviated)
            style.timeZone = timeZone
            return date.formatted(style)
        }
    }

    /// All 14 days (7 past + 7 forecast).
    public static func daily(
        forecast: ForecastResponse,
        conditions: CurrentConditions,
        tempBand: TempBand?,
        dailyRain: [DailyRainNormal]
    ) -> [DailyPoint] {
        let dateKit = DateKit(timeZone: forecast.locationTimeZone)
        let daily = forecast.daily
        let rainByDate = Dictionary(
            dailyRain.map { ($0.date, $0) }, uniquingKeysWith: { first, _ in first })

        return daily.time.enumerated().compactMap { index, dateString in
            guard let date = dateKit.date(fromDayString: dateString) else { return nil }
            return DailyPoint(
                id: index,
                dateString: dateString,
                date: date,
                isToday: index == conditions.todayIndex,
                isPast: index < conditions.todayIndex,
                high: daily.temperature2mMax.value(at: index),
                low: daily.temperature2mMin.value(at: index),
                wetBulbHigh: daily.wetBulbTemperature2mMax.value(at: index),
                wetBulbLow: daily.wetBulbTemperature2mMin.value(at: index),
                precipitation: daily.precipitationSum.value(at: index) ?? 0,
                probability: daily.precipitationProbabilityMax.value(at: index),
                // dailyAvg runs today−7 … today+6, so it lines up index-for-index
                // with the 14-day array only when today is at index 7.
                normal: tempBand?.dailyAvg.at(index - conditions.todayIndex + 7),
                rainNormal: rainByDate[dateString],
                conditionCode: daily.weatherCode.value(at: index))
        }
    }

    // MARK: - Year-to-date rain

    public struct YTDPoint: Identifiable, Sendable, Equatable {
        public let id: Int
        public let date: Date
        public let monthDay: String
        public let value: Double
    }

    public struct YTDSeries: Sendable, Equatable {
        /// This year's cumulative, through `latestDate`.
        public let actual: [YTDPoint]
        /// Historical average cumulative over the same labels.
        public let historical: [YTDPoint]
        /// Dashed forward projection from forecast sums.
        public let projection: [YTDPoint]
        /// Dashed grey continuation of the historical average.
        public let historicalExtension: [YTDPoint]
        public let latestDate: String

        public var isEmpty: Bool { actual.isEmpty }
    }

    /// `thinning` drops points to keep the heaviest chart responsive (§8.4.7);
    /// the last point is always kept so the line ends where the data does.
    public static func ytd(
        ytd: YTDRain,
        projection: [YTDRainBuilder.ProjectionPoint],
        timeZone: TimeZone,
        thinning: Int = 1
    ) -> YTDSeries {
        let dateKit = DateKit(timeZone: timeZone)
        let step = max(1, thinning)

        func points(_ values: [Double]) -> [YTDPoint] {
            values.indices.compactMap { index -> YTDPoint? in
                guard index % step == 0 || index == values.count - 1 else { return nil }
                let monthDay = ytd.labels[index]
                guard let date = dateKit.date(
                    fromDayString: "\(ytd.thisYear)-\(monthDay)") else { return nil }
                return YTDPoint(
                    id: index, date: date, monthDay: monthDay, value: values[index])
            }
        }

        // The current-year line stops at the archive's edge, not at today — that
        // gap is the publication lag and the chart should show it honestly.
        let cutoff = ytd.labels.firstIndex(of: String(ytd.latestDate.dropFirst(5)))
            .map { $0 + 1 } ?? ytd.cumCurrentYear.count
        let actual = points(Array(ytd.cumCurrentYear.prefix(cutoff)))
        let historical = points(ytd.cumHistAvg)

        // Both dashed continuations start at the last solid point so the joins
        // are seamless.
        var projectionPoints: [YTDPoint] = []
        if let anchor = actual.last {
            projectionPoints.append(anchor)
            for (offset, point) in projection.enumerated() {
                guard let date = dateKit.date(fromDayString: point.date) else { continue }
                projectionPoints.append(YTDPoint(
                    id: ytd.labels.count + offset,
                    date: date,
                    monthDay: String(point.date.dropFirst(5)),
                    value: point.cumulative))
            }
        }

        var extensionPoints: [YTDPoint] = []
        if let anchor = historical.last, !ytd.cumHistAvgExt.isEmpty,
           let latest = dateKit.date(fromDayString: ytd.latestDate) {
            extensionPoints.append(anchor)
            for (offset, value) in ytd.cumHistAvgExt.enumerated() {
                let date = dateKit.addingDays(offset + 1, to: latest)
                extensionPoints.append(YTDPoint(
                    id: ytd.labels.count + 1000 + offset,
                    date: date,
                    monthDay: dateKit.monthDayString(date),
                    value: value))
            }
        }

        return YTDSeries(
            actual: actual, historical: historical,
            projection: projectionPoints, historicalExtension: extensionPoints,
            latestDate: ytd.latestDate)
    }

    // MARK: - Climate normals

    public struct ClimatePoint: Identifiable, Sendable, Equatable {
        public let id: Int          // 0-based month
        public let monthName: String
        public let shortMonthName: String
        public let high: Double?
        public let low: Double?
        public let rain: Double?
    }

    static let monthNames = [
        "January", "February", "March", "April", "May", "June",
        "July", "August", "September", "October", "November", "December"
    ]

    public static func climate(_ climatology: Climatology) -> [ClimatePoint] {
        climatology.months.enumerated().map { index, month in
            ClimatePoint(
                id: index,
                monthName: monthNames.at(index) ?? "",
                shortMonthName: String((monthNames.at(index) ?? "").prefix(3)),
                high: month.tMax,
                low: month.tMin,
                rain: month.rain)
        }
    }
}
