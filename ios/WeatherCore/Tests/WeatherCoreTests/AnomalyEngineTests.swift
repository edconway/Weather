import XCTest
@testable import WeatherCore

/// §11.2 requires one test per branch: 3 temperature, 5 rain, 4 mugginess.
final class AnomalyEngineTests: XCTestCase {

    private let metric = UnitFormatter(imperial: false)
    private let imperial = UnitFormatter(imperial: true)

    // MARK: - Helpers

    /// A forecast whose today entry has the given high/low and wet bulb.
    private func conditions(
        high: Double? = 20, low: Double? = 10, wetBulbNow: Double? = nil, hour: Int = 12
    ) -> CurrentConditions {
        let hours = (0..<24).map { String(format: "2026-08-05T%02d:00", $0) }
        let forecast = ForecastResponse(
            latitude: 0, longitude: 0, timezone: "UTC", utcOffsetSeconds: 0,
            daily: .init(
                time: ["2026-08-05"],
                weatherCode: [3],
                temperature2mMax: [high],
                temperature2mMin: [low]),
            hourly: .init(
                time: hours,
                wetBulbTemperature2m: hours.map { _ in wetBulbNow },
                isDay: hours.map { _ in 1 }))

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        var components = DateComponents()
        components.year = 2026
        components.month = 8
        components.day = 5
        components.hour = hour
        return CurrentConditions(forecast: forecast, now: calendar.date(from: components)!)
    }

    private func normal(
        tMax: Double? = nil, tMin: Double? = nil, wbMax: Double? = nil, wbMin: Double? = nil
    ) -> DayNormal {
        DayNormal(tMax: tMax, tMin: tMin, wbMax: wbMax, wbMin: wbMin)
    }

    private func rainNormal(
        forecastMm: Double, histMeanMm: Double, p90Mm: Double = 0
    ) -> DailyRainNormal {
        DailyRainNormal(
            date: "2026-08-05", forecastMm: forecastMm, probabilityMax: nil,
            histMeanMm: histMeanMm, histMedianMm: histMeanMm,
            wetDayProbability: 0.4, p90Mm: p90Mm)
    }

    // MARK: - Temperature: 3 branches

    /// |delta| < 1 °C
    func testTemperatureNearNormal() {
        // forecast mean 15.4, historical mean 15.0 → delta 0.4
        let anomaly = AnomalyEngine.temperature(
            conditions: conditions(high: 20.4, low: 10.4),
            todayNormal: normal(tMax: 20, tMin: 10),
            formatter: metric)
        XCTAssertEqual(anomaly?.text, "Near normal")
        XCTAssertEqual(anomaly?.kind, .neutral)
        XCTAssertEqual(anomaly?.panel, .temperature)
    }

    /// delta > 0
    func testTemperatureWarmerThanNormal() {
        // forecast mean 18, historical mean 15 → +3 °C
        let anomaly = AnomalyEngine.temperature(
            conditions: conditions(high: 23, low: 13),
            todayNormal: normal(tMax: 20, tMin: 10),
            formatter: metric)
        XCTAssertEqual(anomaly?.text, "3°C warmer than normal")
        XCTAssertEqual(anomaly?.kind, .warm)
    }

    /// delta < 0
    func testTemperatureColderThanNormal() {
        // forecast mean 11, historical mean 15 → −4 °C
        let anomaly = AnomalyEngine.temperature(
            conditions: conditions(high: 16, low: 6),
            todayNormal: normal(tMax: 20, tMin: 10),
            formatter: metric)
        XCTAssertEqual(anomaly?.text, "4°C colder than normal")
        XCTAssertEqual(anomaly?.kind, .cold)
    }

    /// §14.5 — a temperature *difference* scales by 9/5 with no +32 offset.
    func testTemperatureDeltaConvertsByScaleOnly() {
        let anomaly = AnomalyEngine.temperature(
            conditions: conditions(high: 23, low: 13),
            todayNormal: normal(tMax: 20, tMin: 10),
            formatter: imperial)
        // 3 °C difference → 5.4 °F → rounds to 5, *not* 37.
        XCTAssertEqual(anomaly?.text, "5°F warmer than normal")
    }

    func testTemperatureIsSuppressedWithoutNormals() {
        XCTAssertNil(AnomalyEngine.temperature(
            conditions: conditions(), todayNormal: nil, formatter: metric))
        XCTAssertNil(AnomalyEngine.temperature(
            conditions: conditions(), todayNormal: normal(tMax: 20, tMin: nil),
            formatter: metric))
        XCTAssertNil(AnomalyEngine.temperature(
            conditions: conditions(high: nil, low: nil),
            todayNormal: normal(tMax: 20, tMin: 10), formatter: metric))
    }

    // MARK: - Rain: 5 branches

    /// forecast < 0.1 and mean ≥ 1
    func testRainDrierThanNormalWhenDryButUsuallyWet() {
        let anomaly = AnomalyEngine.rain(today: rainNormal(forecastMm: 0.0, histMeanMm: 2.5))
        XCTAssertEqual(anomaly?.text, "Drier than normal")
        XCTAssertEqual(anomaly?.kind, .dry)
        XCTAssertEqual(anomaly?.panel, .rain)
    }

    /// forecast < 0.1 and mean < 1
    func testRainDryDayExpectedWhenNormallyDry() {
        let anomaly = AnomalyEngine.rain(today: rainNormal(forecastMm: 0.05, histMeanMm: 0.3))
        XCTAssertEqual(anomaly?.text, "Dry day expected")
        XCTAssertEqual(anomaly?.kind, .dry)
    }

    /// p90 > 0 and forecast ≥ p90
    func testRainUnusuallyWet() {
        let anomaly = AnomalyEngine.rain(
            today: rainNormal(forecastMm: 12, histMeanMm: 2, p90Mm: 9))
        XCTAssertEqual(anomaly?.text, "Unusually wet")
        XCTAssertEqual(anomaly?.kind, .wet)
    }

    /// forecast > mean * 1.5 and (forecast − mean) ≥ 1
    func testRainWetterThanNormal() {
        // 5 > 3 and 5 − 2 = 3 ≥ 1, but below the p90 of 9.
        let anomaly = AnomalyEngine.rain(
            today: rainNormal(forecastMm: 5, histMeanMm: 2, p90Mm: 9))
        XCTAssertEqual(anomaly?.text, "Wetter than normal")
        XCTAssertEqual(anomaly?.kind, .wet)
    }

    /// mean > 0.5 and forecast < mean * 0.5
    func testRainDrierThanNormal() {
        let anomaly = AnomalyEngine.rain(
            today: rainNormal(forecastMm: 0.5, histMeanMm: 4, p90Mm: 9))
        XCTAssertEqual(anomaly?.text, "Drier than normal")
        XCTAssertEqual(anomaly?.kind, .dry)
    }

    /// Everything else.
    func testRainNearNormal() {
        let anomaly = AnomalyEngine.rain(
            today: rainNormal(forecastMm: 2.2, histMeanMm: 2.0, p90Mm: 9))
        XCTAssertEqual(anomaly?.text, "Near normal rainfall")
        XCTAssertEqual(anomaly?.kind, .neutral)
    }

    /// The 1 mm floor stops trivial absolute differences reading as "wetter".
    func testRainSmallAbsoluteExcessStaysNearNormal() {
        // 0.6 > 0.2 * 1.5 = 0.3, but 0.6 − 0.2 = 0.4 < 1.
        let anomaly = AnomalyEngine.rain(
            today: rainNormal(forecastMm: 0.6, histMeanMm: 0.2, p90Mm: 5))
        XCTAssertEqual(anomaly?.text, "Near normal rainfall")
    }

    func testRainIsSuppressedWithoutNormals() {
        XCTAssertNil(AnomalyEngine.rain(today: nil))
    }

    /// The badge branches must agree with the chart chips they sit beside.
    func testClassificationMatchesTheBadgeBranches() {
        XCTAssertEqual(rainNormal(forecastMm: 0, histMeanMm: 2.5).classification, .dry)
        XCTAssertEqual(rainNormal(forecastMm: 12, histMeanMm: 2, p90Mm: 9).classification, .heavy)
        XCTAssertEqual(rainNormal(forecastMm: 5, histMeanMm: 2, p90Mm: 9).classification, .wetter)
        XCTAssertEqual(rainNormal(forecastMm: 0.5, histMeanMm: 4, p90Mm: 9).classification, .drier)
        XCTAssertEqual(rainNormal(forecastMm: 2.2, histMeanMm: 2, p90Mm: 9).classification, .nearAverage)
    }

    // MARK: - Mugginess: 4 branches

    private func hourAverages(_ value: Double?) -> HourAverages {
        HourAverages(
            avgByHour: [Double?](repeating: value, count: 24),
            yearStart: 2021, yearEnd: 2025)
    }

    /// |pct| < 5
    func testMugginessNearNormal() {
        let anomaly = AnomalyEngine.mugginess(
            conditions: conditions(wetBulbNow: 20.4),
            hourlyWetBulb: hourAverages(20), todayNormal: nil)
        XCTAssertEqual(anomaly?.text, "Near normal mugginess")
        XCTAssertEqual(anomaly?.kind, .neutral)
        XCTAssertEqual(anomaly?.panel, .wetBulb)
    }

    /// pct > 0
    func testMugginessMoreMuggy() {
        // (25 − 20) / 20 = +25 %
        let anomaly = AnomalyEngine.mugginess(
            conditions: conditions(wetBulbNow: 25),
            hourlyWetBulb: hourAverages(20), todayNormal: nil)
        XCTAssertEqual(anomaly?.text, "Feels 25% more muggy than usual")
        XCTAssertEqual(anomaly?.kind, .muggy)
    }

    /// pct < 0
    func testMugginessLessMuggy() {
        // (15 − 20) / 20 = −25 %
        let anomaly = AnomalyEngine.mugginess(
            conditions: conditions(wetBulbNow: 15),
            hourlyWetBulb: hourAverages(20), todayNormal: nil)
        XCTAssertEqual(anomaly?.text, "Feels 25% less muggy than usual")
        XCTAssertEqual(anomaly?.kind, .muggyLow)
    }

    /// Suppressed below 8 °C — the ratio is meaningless in cool weather.
    func testMugginessSuppressedWhenNormalIsBelowEightDegrees() {
        XCTAssertNil(AnomalyEngine.mugginess(
            conditions: conditions(wetBulbNow: 12),
            hourlyWetBulb: hourAverages(7.9), todayNormal: nil))
        // Exactly 8 is still shown.
        XCTAssertNotNil(AnomalyEngine.mugginess(
            conditions: conditions(wetBulbNow: 12),
            hourlyWetBulb: hourAverages(8), todayNormal: nil))
    }

    func testMugginessSuppressedWithoutAnyInput() {
        XCTAssertNil(AnomalyEngine.mugginess(
            conditions: conditions(wetBulbNow: nil),
            hourlyWetBulb: hourAverages(20), todayNormal: nil))
        XCTAssertNil(AnomalyEngine.mugginess(
            conditions: conditions(wetBulbNow: 20),
            hourlyWetBulb: nil, todayNormal: nil))
    }

    /// Falls back to the daily band mean when no hourly normal exists.
    func testMugginessFallsBackToTheDailyBand() {
        let anomaly = AnomalyEngine.mugginess(
            conditions: conditions(wetBulbNow: 25),
            hourlyWetBulb: hourAverages(nil),
            todayNormal: normal(wbMax: 24, wbMin: 16))  // mean 20
        XCTAssertEqual(anomaly?.text, "Feels 25% more muggy than usual")
    }

    /// The hour matters: the normal is read at the location's current hour.
    func testMugginessReadsTheCurrentHoursNormal() {
        var byHour = [Double?](repeating: 10, count: 24)
        byHour[18] = 20
        let averages = HourAverages(avgByHour: byHour, yearStart: 2021, yearEnd: 2025)

        let atSix = AnomalyEngine.mugginess(
            conditions: conditions(wetBulbNow: 25, hour: 18),
            hourlyWetBulb: averages, todayNormal: nil)
        XCTAssertEqual(atSix?.text, "Feels 25% more muggy than usual")

        let atNoon = AnomalyEngine.mugginess(
            conditions: conditions(wetBulbNow: 25, hour: 12),
            hourlyWetBulb: averages, todayNormal: nil)
        XCTAssertEqual(atNoon?.text, "Feels 150% more muggy than usual")
    }

    // MARK: - Composition

    func testHeroBadgeOrderIsMugginessTemperatureRain() {
        let badges = AnomalyEngine.heroBadges(
            conditions: conditions(high: 23, low: 13, wetBulbNow: 25),
            tempBand: TempBand(
                dailyAvg: (0..<14).map { _ in normal(tMax: 20, tMin: 10, wbMax: 24, wbMin: 16) },
                month: "August", histYearStart: 2016, histYearEnd: 2025),
            dailyRain: [rainNormal(forecastMm: 0, histMeanMm: 2.5)],
            hourlyNormals: nil,
            formatter: metric)

        XCTAssertEqual(badges.map(\.panel), [.wetBulb, .temperature, .rain])
        XCTAssertEqual(badges.map(\.text), [
            "Feels 25% more muggy than usual",
            "3°C warmer than normal",
            "Drier than normal"
        ])
    }

    /// §9 — the watch shows exactly one badge, temperature first.
    func testWatchBadgePriority() {
        let band = TempBand(
            dailyAvg: (0..<14).map { _ in normal(tMax: 20, tMin: 10, wbMax: 24, wbMin: 16) },
            month: "August", histYearStart: 2016, histYearEnd: 2025)

        let warm = AnomalyEngine.watchBadge(
            conditions: conditions(high: 23, low: 13, wetBulbNow: 25),
            tempBand: band, dailyRain: [rainNormal(forecastMm: 0, histMeanMm: 2.5)],
            hourlyNormals: nil, formatter: metric)
        XCTAssertEqual(warm?.panel, .temperature)

        // Temperature near normal → mugginess wins.
        let muggy = AnomalyEngine.watchBadge(
            conditions: conditions(high: 20.4, low: 10.4, wetBulbNow: 25),
            tempBand: band, dailyRain: [rainNormal(forecastMm: 0, histMeanMm: 2.5)],
            hourlyNormals: nil, formatter: metric)
        XCTAssertEqual(muggy?.panel, .wetBulb)

        // Neither → a non-neutral rain badge.
        let rainy = AnomalyEngine.watchBadge(
            conditions: conditions(high: 20.4, low: 10.4, wetBulbNow: nil),
            tempBand: band, dailyRain: [rainNormal(forecastMm: 0, histMeanMm: 2.5)],
            hourlyNormals: nil, formatter: metric)
        XCTAssertEqual(rainy?.panel, .rain)

        // Everything neutral → no badge at all.
        let quiet = AnomalyEngine.watchBadge(
            conditions: conditions(high: 20.4, low: 10.4, wetBulbNow: nil),
            tempBand: band, dailyRain: [rainNormal(forecastMm: 2.2, histMeanMm: 2, p90Mm: 9)],
            hourlyNormals: nil, formatter: metric)
        XCTAssertNil(quiet)
    }
}
