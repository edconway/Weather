import XCTest
@testable import WeatherCore

final class CurrentConditionsTests: XCTestCase {

    // MARK: - Builders

    private func makeForecast(
        timezone: String,
        utcOffsetSeconds: Int,
        dailyTimes: [String],
        hourlyTimes: [String],
        daily: ForecastResponse.Daily? = nil,
        hourly: ForecastResponse.Hourly? = nil
    ) -> ForecastResponse {
        ForecastResponse(
            latitude: 0, longitude: 0,
            timezone: timezone, utcOffsetSeconds: utcOffsetSeconds,
            daily: daily ?? .init(
                time: dailyTimes,
                weatherCode: dailyTimes.map { _ in 3 },
                temperature2mMax: dailyTimes.enumerated().map { Double(20 + $0.offset) },
                temperature2mMin: dailyTimes.enumerated().map { Double(10 + $0.offset) },
                apparentTemperatureMax: dailyTimes.map { _ in 19.0 },
                precipitationSum: dailyTimes.map { _ in 0.0 },
                precipitationProbabilityMax: dailyTimes.enumerated().map { $0.offset },
                windSpeed10mMax: dailyTimes.map { _ in 12.0 },
                uvIndexMax: dailyTimes.map { _ in 4.0 }),
            hourly: hourly ?? .init(
                time: hourlyTimes,
                temperature2m: hourlyTimes.enumerated().map { Double(100 + $0.offset) },
                weatherCode: hourlyTimes.map { _ in 61 },
                isDay: hourlyTimes.map { _ in 1 }))
    }

    private func date(
        _ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0,
        in timeZone: TimeZone
    ) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        return calendar.date(from: components)!
    }

    // MARK: - Fixture

    func testFixtureIndicesAndHeroNumbers() throws {
        let forecast = try Fixture.forecast
        let conditions = CurrentConditions(forecast: forecast, now: Fixture.now)

        XCTAssertEqual(conditions.todayString, "2026-08-05")
        XCTAssertEqual(conditions.todayIndex, 7)
        XCTAssertEqual(conditions.currentHour, 12)
        // hourly starts at 2026-08-04T11:00, so 2026-08-05T12:00 is index 25.
        XCTAssertEqual(conditions.nowIndex, 25)
        XCTAssertEqual(forecast.hourly.time[conditions.nowIndex], "2026-08-05T12:00")

        XCTAssertEqual(conditions.temperature, 22.8)
        XCTAssertEqual(conditions.feelsLike, 20.8)
        XCTAssertEqual(conditions.wetBulbNow, 16.1)
        XCTAssertEqual(conditions.high, 25.2)
        XCTAssertEqual(conditions.low, 19.0)
        XCTAssertEqual(conditions.rainChance, 25)
        XCTAssertEqual(conditions.windSpeed, 19.8)
        XCTAssertEqual(conditions.uvIndex, 4.05)
        XCTAssertEqual(conditions.conditionCode, 3)
        XCTAssertTrue(conditions.isDay)
        XCTAssertEqual(conditions.condition.label, "Overcast")
        XCTAssertEqual(conditions.symbolName, "cloud.fill")
    }

    // MARK: - §11.2: index resolution

    /// §14.1 — today is *usually* index 7, but never assume it. Here the array
    /// is short a leading day, so today sits at 6.
    func testTodayIndexIsFoundByStringMatchNotByPosition() {
        let timeZone = TimeZone(identifier: "Europe/London")!
        let forecast = makeForecast(
            timezone: "Europe/London", utcOffsetSeconds: 3600,
            dailyTimes: [
                "2026-07-30", "2026-07-31", "2026-08-01", "2026-08-02",
                "2026-08-03", "2026-08-04", "2026-08-05", "2026-08-06"
            ],
            hourlyTimes: ["2026-08-05T00:00"])

        let conditions = CurrentConditions(
            forecast: forecast, now: date(2026, 8, 5, 9, in: timeZone))
        XCTAssertEqual(conditions.todayIndex, 6)
        XCTAssertEqual(conditions.high, 26)   // 20 + 6
        XCTAssertEqual(conditions.rainChance, 6)
    }

    /// A date the array does not contain clamps to 0 rather than −1.
    func testMissingTodayClampsToZero() {
        let timeZone = TimeZone(identifier: "Europe/London")!
        let forecast = makeForecast(
            timezone: "Europe/London", utcOffsetSeconds: 3600,
            dailyTimes: ["2026-01-01", "2026-01-02"],
            hourlyTimes: ["2026-01-01T00:00"])

        let conditions = CurrentConditions(
            forecast: forecast, now: date(2026, 8, 5, 9, in: timeZone))
        XCTAssertEqual(conditions.todayIndex, 0)
        XCTAssertEqual(conditions.nowIndex, 0)
    }

    func testNowIndexAtEndOfDay() {
        let timeZone = TimeZone(identifier: "Europe/London")!
        let hours = (0..<24).map { String(format: "2026-08-05T%02d:00", $0) }
            + ["2026-08-06T00:00", "2026-08-06T01:00"]
        let forecast = makeForecast(
            timezone: "Europe/London", utcOffsetSeconds: 3600,
            dailyTimes: ["2026-08-05", "2026-08-06"], hourlyTimes: hours)

        let late = CurrentConditions(
            forecast: forecast, now: date(2026, 8, 5, 23, 45, in: timeZone))
        XCTAssertEqual(late.currentHour, 23)
        XCTAssertEqual(forecast.hourly.time[late.nowIndex], "2026-08-05T23:00")

        let justAfterMidnight = CurrentConditions(
            forecast: forecast, now: date(2026, 8, 6, 0, 5, in: timeZone))
        XCTAssertEqual(justAfterMidnight.currentHour, 0)
        XCTAssertEqual(justAfterMidnight.todayString, "2026-08-06")
        XCTAssertEqual(forecast.hourly.time[justAfterMidnight.nowIndex], "2026-08-06T00:00")
    }

    /// PLAN DEVIATION §1.4.2 — "now" is the *location's* wall clock.
    ///
    /// The device sits in UTC−8 while the location is UTC+13. At the instant
    /// below it is 2026-08-05 08:00 in Los Angeles but already 2026-08-06 05:00
    /// in Auckland; the location's calendar day is what must win.
    func testNowUsesTheLocationTimezoneNotTheDevice() {
        let device = TimeZone(identifier: "America/Los_Angeles")!
        let auckland = TimeZone(identifier: "Pacific/Auckland")!
        let instant = date(2026, 8, 5, 8, in: device)

        // Sanity-check the premise before asserting on the code under test.
        var deviceCalendar = Calendar(identifier: .gregorian)
        deviceCalendar.timeZone = device
        XCTAssertEqual(deviceCalendar.component(.day, from: instant), 5)
        var aucklandCalendar = Calendar(identifier: .gregorian)
        aucklandCalendar.timeZone = auckland
        XCTAssertEqual(aucklandCalendar.component(.day, from: instant), 6)
        XCTAssertEqual(aucklandCalendar.component(.hour, from: instant), 3)

        let forecast = makeForecast(
            timezone: "Pacific/Auckland", utcOffsetSeconds: 12 * 3600,
            dailyTimes: ["2026-08-04", "2026-08-05", "2026-08-06", "2026-08-07"],
            hourlyTimes: (0..<6).map { String(format: "2026-08-06T%02d:00", $0) })

        let conditions = CurrentConditions(forecast: forecast, now: instant)
        XCTAssertEqual(conditions.todayString, "2026-08-06")
        XCTAssertEqual(conditions.todayIndex, 2)
        XCTAssertEqual(conditions.currentHour, 3)
        XCTAssertEqual(forecast.hourly.time[conditions.nowIndex], "2026-08-06T03:00")
    }

    /// When `timezone` is unusable the reported UTC offset takes over.
    func testFallsBackToTheReportedUTCOffset() {
        let forecast = makeForecast(
            timezone: "Not/AZone", utcOffsetSeconds: 5 * 3600 + 1800,  // UTC+5:30
            dailyTimes: ["2026-08-05", "2026-08-06"],
            hourlyTimes: (0..<24).map { String(format: "2026-08-06T%02d:00", $0) })

        XCTAssertEqual(forecast.locationTimeZone.secondsFromGMT(), 5 * 3600 + 1800)

        // 2026-08-05 20:00 UTC is 2026-08-06 01:30 in UTC+5:30.
        let instant = date(2026, 8, 5, 20, in: .gmt)
        let conditions = CurrentConditions(forecast: forecast, now: instant)
        XCTAssertEqual(conditions.todayString, "2026-08-06")
        XCTAssertEqual(conditions.currentHour, 1)
        XCTAssertEqual(forecast.hourly.time[conditions.nowIndex], "2026-08-06T01:00")
    }

    // MARK: - Fallbacks

    /// §6.2 — a null hourly reading falls back to the daily figure.
    func testNullHourlyValuesFallBackToDaily() {
        let timeZone = TimeZone(identifier: "Europe/London")!
        let forecast = ForecastResponse(
            latitude: 0, longitude: 0, timezone: "Europe/London", utcOffsetSeconds: 3600,
            daily: .init(
                time: ["2026-08-05"],
                weatherCode: [95],
                temperature2mMax: [25.0],
                temperature2mMin: [15.0],
                apparentTemperatureMax: [24.0]),
            hourly: .init(
                time: ["2026-08-05T09:00"],
                temperature2m: [nil],
                apparentTemperature: [nil],
                weatherCode: [nil],
                isDay: [nil]))

        let conditions = CurrentConditions(
            forecast: forecast, now: date(2026, 8, 5, 9, in: timeZone))
        XCTAssertEqual(conditions.temperature, 25.0, "falls back to the daily max")
        XCTAssertEqual(conditions.feelsLike, 24.0)
        XCTAssertEqual(conditions.conditionCode, 95)
        XCTAssertTrue(conditions.isDay, "missing is_day defaults to day")
        XCTAssertEqual(conditions.symbolName, "cloud.bolt.fill")
    }

    /// PLAN DEVIATION §1.4.1 — the *hourly* code wins over the daily one.
    func testHourlyWeatherCodeTakesPrecedence() {
        let timeZone = TimeZone(identifier: "Europe/London")!
        let forecast = makeForecast(
            timezone: "Europe/London", utcOffsetSeconds: 3600,
            dailyTimes: ["2026-08-05"],
            hourlyTimes: ["2026-08-05T22:00"],
            hourly: .init(
                time: ["2026-08-05T22:00"],
                temperature2m: [17.0],
                weatherCode: [0],
                isDay: [0]))

        let conditions = CurrentConditions(
            forecast: forecast, now: date(2026, 8, 5, 22, in: timeZone))
        XCTAssertEqual(conditions.conditionCode, 0, "hourly clear beats daily overcast")
        XCTAssertFalse(conditions.isDay)
        XCTAssertEqual(conditions.symbolName, "moon.stars.fill", "night variant at 22:00")
    }
}
