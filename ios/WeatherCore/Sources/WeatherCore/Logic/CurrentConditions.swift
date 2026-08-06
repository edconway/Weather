import Foundation

/// The hero numbers, plus the two array indices every other derivation needs.
///
/// Port of the top of `renderContent` in `app.js` (§6.2). Indices are always
/// located by **string match** against strings built from "now in the location's
/// timezone" — never hardcoded to 7 / 24, and never derived from `Date`
/// comparisons (§14.1, §14.2).
public struct CurrentConditions: Sendable, Equatable {
    /// Index of today in `daily.time`. Normally 7 with `past_days=7`.
    public let todayIndex: Int
    /// Index of the current hour in `hourly.time`.
    public let nowIndex: Int
    /// `"YYYY-MM-DD"` for today, location-local.
    public let todayString: String
    /// Hour of day 0…23, location-local.
    public let currentHour: Int

    public let temperature: Double?
    public let feelsLike: Double?
    public let high: Double?
    public let low: Double?
    public let wetBulbNow: Double?
    public let rainChance: Int?
    public let windSpeed: Double?
    public let uvIndex: Double?
    public let conditionCode: Int?
    public let isDay: Bool

    public var condition: WMOCode.Descriptor { WMOCode.describe(conditionCode) }
    public var symbolName: String { condition.symbol(isDay: isDay) }

    public init(forecast: ForecastResponse, now: Date) {
        let dateKit = DateKit(timeZone: forecast.locationTimeZone)
        let daily = forecast.daily
        let hourly = forecast.hourly

        let todayString = dateKit.dateString(now)
        self.todayString = todayString
        self.currentHour = dateKit.hour(now)

        // `Math.max(0, findIndex(...))` — a miss (-1) clamps to 0.
        let t0 = max(0, daily.time.firstIndex(of: todayString) ?? -1)
        self.todayIndex = t0

        // Lexicographic comparison is correct for these fixed-width ISO strings.
        let nowHourString = dateKit.hourString(now)
        let rawNow = hourly.time.firstIndex { $0 >= nowHourString } ?? -1
        let nowIndex = max(0, rawNow)
        self.nowIndex = nowIndex

        self.high = daily.temperature2mMax.value(at: t0)
        self.low = daily.temperature2mMin.value(at: t0)
        self.temperature = hourly.temperature2m.value(at: nowIndex) ?? high
        self.feelsLike = hourly.apparentTemperature.value(at: nowIndex)
            ?? daily.apparentTemperatureMax.value(at: t0)
        self.wetBulbNow = hourly.wetBulbTemperature2m.value(at: nowIndex)
        self.rainChance = daily.precipitationProbabilityMax.value(at: t0)
        self.windSpeed = daily.windSpeed10mMax.value(at: t0)
        self.uvIndex = daily.uvIndexMax.value(at: t0)

        // PLAN DEVIATION §1.4.1: the *hourly* code at the current hour, so the
        // hero and complications describe now rather than the whole day.
        self.conditionCode = hourly.weatherCode.value(at: nowIndex)
            ?? daily.weatherCode.value(at: t0)
        self.isDay = (hourly.isDay.value(at: nowIndex) ?? 1) != 0
    }
}
