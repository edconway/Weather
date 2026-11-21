import XCTest
@testable import WeatherCore

final class ScreenPresentationTests: XCTestCase {

    private let zone = TimeZone(identifier: "Europe/London")!

    private func now(_ hour: Int, day: Int = 5) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar.date(from: DateComponents(year: 2026, month: 8, day: day, hour: hour))!
    }

    private func forecast(
        hours: [String],
        temps: [Double],
        precip: [Double],
        wetBulb: [Double] = [],
        dailyDates: [String] = ["2026-08-05", "2026-08-06"],
        dailyPrecip: [Double]? = nil,
        highs: [Double]? = nil,
        lows: [Double]? = nil
    ) -> ForecastResponse {
        let count = dailyDates.count
        return ForecastResponse(
            latitude: 51.5, longitude: -0.1,
            timezone: "Europe/London", utcOffsetSeconds: 3600,
            daily: .init(
                time: dailyDates,
                weatherCode: Array(repeating: 1, count: count),
                temperature2mMax: highs ?? Array(repeating: 20, count: count),
                temperature2mMin: lows ?? Array(repeating: 14, count: count),
                apparentTemperatureMax: Array(repeating: 20, count: count),
                precipitationSum: dailyPrecip ?? Array(repeating: 0, count: count),
                windSpeed10mMax: Array(repeating: 12, count: count),
                uvIndexMax: Array(repeating: 4, count: count)),
            hourly: .init(
                time: hours,
                temperature2m: temps,
                wetBulbTemperature2m: wetBulb,
                precipitation: precip,
                precipitationProbability: precip.map { $0 > 0 ? 70 : 0 },
                weatherCode: precip.map { $0 >= 0.2 ? 61 : 1 },
                isDay: hours.map { _ in 1 }))
    }

    private func normals(hour: Int, temp: Double, wetBulb: Double = 12) -> HourlyNormals {
        var temps = [Double?](repeating: 16, count: 24)
        var bulbs = [Double?](repeating: 12, count: 24)
        temps[hour] = temp
        bulbs[hour] = wetBulb
        let rain = RainHourNormals(
            avgByHour: Array(repeating: 0, count: 24),
            wetHourProbabilityByHour: Array(repeating: 0, count: 24),
            p90ByHour: Array(repeating: 0, count: 24),
            yearStart: 2021, yearEnd: 2025)
        return HourlyNormals(
            temp: HourAverages(avgByHour: temps, yearStart: 2021, yearEnd: 2025),
            wetBulb: HourAverages(avgByHour: bulbs, yearStart: 2021, yearEnd: 2025),
            rain: rain)
    }

    private func band(high: Double, low: Double) -> TempBand {
        var days = Array(repeating: DayNormal(tMax: high, tMin: low, wbMax: nil, wbMin: nil), count: 14)
        days[7] = DayNormal(tMax: high, tMin: low, wbMax: nil, wbMin: nil)
        return TempBand(dailyAvg: days, month: "August", histYearStart: 2016, histYearEnd: 2025)
    }

    func testVoiceStaysEmptyUntilANormalExists() {
        let hours = ["2026-08-05T14:00"]
        let forecast = forecast(hours: hours, temps: [22], precip: [0])
        let conditions = CurrentConditions(forecast: forecast, now: now(14))
        let voice = ScreenPresentation.heroVoice(
            forecast: forecast, conditions: conditions,
            hourlyNormals: nil, tempBand: nil, dailyRain: [],
            formatter: UnitFormatter(imperial: false))
        XCTAssertNil(voice)
    }

    func testVoiceNamesAWarmerAfternoonBeforeMugginess() {
        let hours = ["2026-08-05T14:00"]
        let forecast = forecast(hours: hours, temps: [22], precip: [0], wetBulb: [20])
        let conditions = CurrentConditions(forecast: forecast, now: now(14))
        let voice = ScreenPresentation.heroVoice(
            forecast: forecast, conditions: conditions,
            hourlyNormals: normals(hour: 14, temp: 16, wetBulb: 10),
            tempBand: band(high: 20, low: 14),
            dailyRain: [],
            formatter: UnitFormatter(imperial: false))
        XCTAssertEqual(voice?.headline, "6° warmer than a normal early-August afternoon")
        XCTAssertEqual(voice?.panel, .temperature)
    }

    func testVoiceUsesMugginessOnlyWhenTheAirIsActuallyHumid() {
        let hours = ["2026-08-05T14:00"]
        let forecast = forecast(hours: hours, temps: [16], precip: [0], wetBulb: [20])
        let conditions = CurrentConditions(forecast: forecast, now: now(14))
        let voice = ScreenPresentation.heroVoice(
            forecast: forecast, conditions: conditions,
            hourlyNormals: normals(hour: 14, temp: 16, wetBulb: 10),
            tempBand: band(high: 20, low: 14),
            dailyRain: [],
            formatter: UnitFormatter(imperial: false))
        XCTAssertEqual(voice?.headline, "Much muggier than usual for the time of day")
        XCTAssertEqual(voice?.panel, .wetBulb)
    }

    func testVoicePrefersAnUnusuallyWetDay() {
        let hours = ["2026-08-05T14:00"]
        let forecast = forecast(hours: hours, temps: [22], precip: [0])
        let conditions = CurrentConditions(forecast: forecast, now: now(14))
        let rain = DailyRainNormal(
            date: "2026-08-05", forecastMm: 12, probabilityMax: 80,
            histMeanMm: 2, histMedianMm: 1, wetDayProbability: 0.3, p90Mm: 8)
        let voice = ScreenPresentation.heroVoice(
            forecast: forecast, conditions: conditions,
            hourlyNormals: normals(hour: 14, temp: 16),
            tempBand: band(high: 20, low: 14),
            dailyRain: [rain],
            formatter: UnitFormatter(imperial: false))
        XCTAssertEqual(voice?.headline, "An unusually wet day for early-August")
        XCTAssertEqual(voice?.panel, .rain)
    }

    func testOutlookSaysRainThisHourWithoutInventingMinutes() {
        let hours = ["2026-08-05T14:00", "2026-08-05T15:00"]
        let forecast = forecast(hours: hours, temps: [18, 18], precip: [1.2, 0])
        let conditions = CurrentConditions(forecast: forecast, now: now(14))
        let outlook = ScreenPresentation.rainOutlook(
            forecast: forecast, conditions: conditions, formatter: UnitFormatter(imperial: false))
        XCTAssertEqual(outlook.state, .rainingNow)
        XCTAssertEqual(outlook.heroValue, "Now")
        XCTAssertTrue(outlook.prominent)
        XCTAssertEqual(outlook.headline, "Rain this hour")
        XCTAssertEqual(outlook.sourceCaption, "Open-Meteo · hourly estimate")
        XCTAssertEqual(outlook.detail, "About ~1.2 mm this hour")
    }

    func testOutlookIsProminentWhenRainStartsWithinThreeHours() {
        let hours = (14...18).map { String(format: "2026-08-05T%02d:00", $0) }
        let forecast = forecast(
            hours: hours, temps: Array(repeating: 18, count: hours.count),
            precip: [0, 0, 1.4, 0, 0])
        let conditions = CurrentConditions(forecast: forecast, now: now(14))
        let outlook = ScreenPresentation.rainOutlook(
            forecast: forecast, conditions: conditions, formatter: UnitFormatter(imperial: false))
        XCTAssertEqual(outlook.state, .laterToday)
        XCTAssertEqual(outlook.headline, "Dry until about 4pm")
        XCTAssertTrue(outlook.prominent)
        XCTAssertEqual(outlook.heroValue, "Until 4pm")
    }

    func testOutlookStaysQuietWhenRainIsLaterToday() {
        let hours = (14...23).map { String(format: "2026-08-05T%02d:00", $0) }
        var precip = Array(repeating: 0.0, count: hours.count)
        precip[6] = 2
        let forecast = forecast(
            hours: hours, temps: Array(repeating: 18, count: hours.count), precip: precip)
        let conditions = CurrentConditions(forecast: forecast, now: now(14))
        let outlook = ScreenPresentation.rainOutlook(
            forecast: forecast, conditions: conditions, formatter: UnitFormatter(imperial: false))
        XCTAssertEqual(outlook.headline, "Dry until about 8pm")
        XCTAssertFalse(outlook.prominent)
    }

    func testDryOutlookDoesNotDrawAMinuteCurve() {
        let hours = ["2026-08-05T14:00"]
        let forecast = forecast(hours: hours, temps: [18], precip: [0])
        let conditions = CurrentConditions(forecast: forecast, now: now(14))
        let outlook = ScreenPresentation.rainOutlook(
            forecast: forecast, conditions: conditions, formatter: UnitFormatter(imperial: false))
        XCTAssertEqual(outlook.state, .dry)
        XCTAssertEqual(outlook.heroValue, "Dry")
        XCTAssertFalse(outlook.prominent)
        XCTAssertEqual(outlook.sourceCaption, "Open-Meteo · hourly estimate")
    }

    func testTodayRangePlacesNowInsideTheTrack() {
        let hours = ["2026-08-05T14:00"]
        let forecast = forecast(
            hours: hours, temps: [16], precip: [0], highs: [22], lows: [10])
        let conditions = CurrentConditions(forecast: forecast, now: now(14))
        let built = ScreenPresentation.todayRange(
            conditions: conditions,
            normal: DayNormal(tMax: 18, tMin: 12, wbMax: nil, wbMin: nil))
        let range = try XCTUnwrap(built)
        XCTAssertGreaterThan(range.normalWidth, 0)
        XCTAssertGreaterThan(range.todayWidth, 0)
        XCTAssertGreaterThan(range.nowFraction ?? -1, 0)
        XCTAssertLessThan(range.nowFraction ?? 2, 1)
        XCTAssertGreaterThanOrEqual(range.lowLabelFraction, 0.08)
        XCTAssertLessThanOrEqual(range.highLabelFraction, 0.92)
    }

    func testShortPlaceDropsARepeatedRegion() {
        XCTAssertEqual(ScreenPresentation.shortPlaceName("Singapore, Singapore"), "Singapore")
        XCTAssertEqual(ScreenPresentation.shortPlaceName("London, England"), "London, England")
    }

    func testUpdatedPhraseUsesTheLocationClock() {
        let fetched = now(14, day: 5).addingTimeInterval(30 * 60)
        let phrase = ScreenPresentation.updatedPhrase(fetchedAt: fetched, now: now(15), timeZone: zone)
        XCTAssertEqual(phrase.text, "Updated 14:30")
        XCTAssertTrue(phrase.live)

        let yesterday = ScreenPresentation.updatedPhrase(
            fetchedAt: now(22, day: 4), now: now(15), timeZone: zone)
        XCTAssertEqual(yesterday.text, "Updated yesterday 22:00")
        XCTAssertFalse(yesterday.live)
    }

    func testRainTotalsCoverTheWeekEitherSideOfToday() {
        let dates = (1...12).map { String(format: "2026-08-%02d", $0) }
        let forecast = forecast(
            hours: ["2026-08-05T14:00"], temps: [18], precip: [0],
            dailyDates: dates,
            dailyPrecip: dates.map { _ in 1 })
        let conditions = CurrentConditions(forecast: forecast, now: now(14))
        let totals = ScreenPresentation.rainTotals(
            forecast: forecast, conditions: conditions, dailyRain: [])
        XCTAssertEqual(totals.last7, 4)
        XCTAssertEqual(totals.next7, 7)
        XCTAssertNil(totals.lastNormal)
    }

    func testWetBulbCollapseCopyUsesTheHourlyNormal() {
        let hours = ["2026-08-05T14:00"]
        let forecast = forecast(hours: hours, temps: [16], precip: [0], wetBulb: [10])
        let conditions = CurrentConditions(forecast: forecast, now: now(14))
        let detail = ScreenPresentation.wetBulbHiddenDetail(
            conditions: conditions,
            hourlyNormals: normals(hour: 14, temp: 16, wetBulb: 13),
            formatter: UnitFormatter(imperial: false))
        XCTAssertEqual(detail, "3° below the usual for the hour. Charts hidden while it stays under 15°.")
        XCTAssertEqual(ScreenPresentation.maxWetBulb(forecast), 10)
    }
}
