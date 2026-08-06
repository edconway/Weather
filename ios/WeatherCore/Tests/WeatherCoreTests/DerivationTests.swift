import XCTest
@testable import WeatherCore

final class DerivationTests: XCTestCase {

    private let london = TimeZone(identifier: "Europe/London")!

    // MARK: - §6.3 Climatology

    /// Two-level averaging: each year's month is reduced to its own mean first,
    /// and those means are averaged. Flattening every day into one pool gives a
    /// different answer whenever the years have unequal coverage — this toy set
    /// is built so the two disagree.
    func testMonthlyMeansUseTwoLevelAveraging() throws {
        // 2024-01: one day at 10 °C. 2025-01: three days at 20, 20, 20.
        let response = ArchiveResponse(
            daily: .init(
                time: ["2024-01-01", "2025-01-01", "2025-01-02", "2025-01-03"],
                temperature2mMax: [10, 20, 20, 20],
                temperature2mMin: [0, 10, 10, 10],
                precipitationSum: [4, 1, 1, 1]))

        let climatology = try XCTUnwrap(
            ClimatologyBuilder.build(response: response, thisYear: 2026))
        let january = climatology.months[0]

        // Two-level: (10 + 20) / 2 = 15.
        XCTAssertEqual(try XCTUnwrap(january.tMax), 15, accuracy: 1e-9)
        // Naive pooling would be (10 + 20 + 20 + 20) / 4 = 17.5.
        XCTAssertNotEqual(try XCTUnwrap(january.tMax), 17.5, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(january.tMin), 5, accuracy: 1e-9)

        // Rain is a per-year *total*, then averaged: (4 + 3) / 2 = 3.5.
        XCTAssertEqual(try XCTUnwrap(january.rain), 3.5, accuracy: 1e-9)

        // Months with no data stay nil rather than becoming 0.
        XCTAssertNil(climatology.months[5].tMax)

        XCTAssertEqual(climatology.yearStart, 2016)
        XCTAssertEqual(climatology.yearEnd, 2025)
    }

    func testByMMDDPoolsEveryYearsValueForThatCalendarDay() throws {
        let response = ArchiveResponse(
            daily: .init(
                time: ["2024-03-01", "2025-03-01", "2025-03-02"],
                temperature2mMax: [11, 13, 20],
                temperature2mMin: [1, 3, 10],
                wetBulbTemperature2mMax: [9, 11, nil],
                wetBulbTemperature2mMin: [nil, 2, 5],
                precipitationSum: [0.5, 1.5, 2]))

        let climatology = try XCTUnwrap(
            ClimatologyBuilder.build(response: response, thisYear: 2026))
        let march1 = try XCTUnwrap(climatology.byMMDD["03-01"])
        XCTAssertEqual(march1.maxes, [11, 13])
        XCTAssertEqual(march1.mins, [1, 3])
        XCTAssertEqual(march1.wbMaxes, [9, 11])
        XCTAssertEqual(march1.wbMins, [2], "nulls are skipped, not zero-filled")
        XCTAssertEqual(march1.rains, [0.5, 1.5])
    }

    func testClimatologyFromFixture() throws {
        let climatology = try XCTUnwrap(
            ClimatologyBuilder.build(response: try Fixture.climatology, thisYear: 2026))
        XCTAssertEqual(climatology.months.count, 12)
        // 366 distinct calendar days over 10 years including two leap years.
        XCTAssertEqual(climatology.byMMDD.count, 366)
        // London: July/August warmest, January/February coldest.
        let warmest = climatology.months.enumerated()
            .max { ($0.element.tMax ?? -99) < ($1.element.tMax ?? -99) }?.offset
        XCTAssertTrue([6, 7].contains(warmest ?? -1), "expected Jul or Aug, got \(warmest ?? -1)")
        for month in climatology.months {
            XCTAssertNotNil(month.tMax)
            XCTAssertNotNil(month.rain)
        }
    }

    // MARK: - §6.4 Temperature band

    func testTempBandIsFourteenDaysCentredOnToday() throws {
        let climatology = try XCTUnwrap(
            ClimatologyBuilder.build(response: try Fixture.climatology, thisYear: 2026))
        let band = TempBandDeriver.derive(
            climatology: climatology, now: Fixture.now, timeZone: london)

        XCTAssertEqual(band.dailyAvg.count, 14)
        XCTAssertEqual(band.month, "August")
        XCTAssertEqual(band.histYearStart, 2016)
        XCTAssertEqual(band.histYearEnd, 2025)

        let today = try XCTUnwrap(band.today)
        let tMax = try XCTUnwrap(today.tMax)
        let tMin = try XCTUnwrap(today.tMin)
        XCTAssertGreaterThan(tMax, tMin)
        // Early-August London normals sit in the low-to-mid twenties.
        XCTAssertGreaterThan(tMax, 18)
        XCTAssertLessThan(tMax, 30)
        XCTAssertNotNil(today.wbMax)
        XCTAssertNotNil(today.wbMin)
    }

    /// Each day pools 7 calendar days × 10 archive years.
    func testTempBandPoolsTheSevenDayWindow() throws {
        var byMMDD: [String: DayPool] = [:]
        // Give 08-05 a distinctive value and its neighbours another, so the
        // resulting mean can only come from a ±3-day pool.
        for day in 1...12 {
            let key = String(format: "08-%02d", day)
            byMMDD[key] = DayPool(maxes: [day == 5 ? 30 : 20], mins: [10])
        }
        let climatology = Climatology(
            months: (0..<12).map { _ in MonthNormal(tMax: nil, tMin: nil, rain: nil) },
            byMMDD: byMMDD, yearStart: 2016, yearEnd: 2025)

        let band = TempBandDeriver.derive(
            climatology: climatology, now: Fixture.now, timeZone: london)
        // Today (08-05) pools 08-02…08-08: one 30 and six 20s → 140/7 = 20.
        XCTAssertEqual(try XCTUnwrap(band.today?.tMax), 150.0 / 7, accuracy: 1e-9)
    }

    // MARK: - §6.5 Daily rain

    func testDailyRainCoversSevenForecastDaysStartingToday() throws {
        let forecast = try Fixture.forecast
        let climatology = try XCTUnwrap(
            ClimatologyBuilder.build(response: try Fixture.climatology, thisYear: 2026))
        let conditions = CurrentConditions(forecast: forecast, now: Fixture.now)

        let normals = DailyRainDeriver.derive(
            forecast: forecast, climatology: climatology, todayIndex: conditions.todayIndex)

        XCTAssertEqual(normals.count, 7)
        XCTAssertEqual(normals.first?.date, "2026-08-05")
        XCTAssertEqual(normals.last?.date, "2026-08-11")
        XCTAssertEqual(normals[0].forecastMm, 0.0)
        XCTAssertEqual(normals[0].probabilityMax, 25)
        // Pooled from 7 calendar days × 10 years.
        XCTAssertGreaterThan(normals[0].histMeanMm, 0)
        XCTAssertGreaterThanOrEqual(normals[0].p90Mm, normals[0].histMedianMm)
        XCTAssertTrue((0...1).contains(normals[0].wetDayProbability))
        XCTAssertEqual(normals[0].classification, .dry, "0 mm forecast")
    }

    func testDailyRainStatisticsOnAKnownPool() {
        let pool = DayPool(rains: [0, 0, 0, 0.05, 0.2, 1, 2, 3, 4, 20])
        // p90 = sorted[floor(10 * 0.9)] = sorted[9] = 20.
        XCTAssertEqual(Stats.p90(pool.rains), 20)
        XCTAssertEqual(Stats.median(pool.rains), 0.6, accuracy: 1e-9)
        XCTAssertEqual(Stats.meanOrZero(pool.rains), 3.025, accuracy: 1e-9)
        // 6 of 10 days at or above 0.1 mm.
        XCTAssertEqual(Stats.wetShare(pool.rains), 0.6, accuracy: 1e-9)
    }

    // MARK: - §6.6 Hourly normals

    func testHourlyNormalsBucketByHourOfDay() throws {
        let normals = HourlyNormalsBuilder.build(
            windows: try Fixture.hourlyNormalWindows, thisYear: 2026)

        XCTAssertEqual(normals.temp.avgByHour.count, 24)
        XCTAssertEqual(normals.rain.avgByHour.count, 24)
        XCTAssertEqual(normals.temp.yearStart, 2021)
        XCTAssertEqual(normals.temp.yearEnd, 2025)

        for hour in 0..<24 {
            XCTAssertNotNil(normals.temp.avgByHour[hour], "hour \(hour)")
            XCTAssertNotNil(normals.wetBulb.avgByHour[hour], "hour \(hour)")
            XCTAssertGreaterThanOrEqual(normals.rain.avgByHour[hour], 0)
            XCTAssertTrue((0...1).contains(normals.rain.wetHourProbabilityByHour[hour]))
        }

        // A London summer diurnal cycle: mid-afternoon beats pre-dawn.
        let preDawn = try XCTUnwrap(normals.temp.avgByHour[4])
        let afternoon = try XCTUnwrap(normals.temp.avgByHour[15])
        XCTAssertGreaterThan(afternoon, preDawn + 3)
    }

    func testHourlyNormalsHandleMissingWindows() {
        let window = ArchiveResponse(hourly: .init(
            time: ["2025-08-01T00:00", "2025-08-01T01:00"],
            temperature2m: [10, nil],
            wetBulbTemperature2m: [nil, nil],
            precipitation: [0.5, 0]))

        let normals = HourlyNormalsBuilder.build(
            windows: [window, nil, nil, nil, nil], thisYear: 2026)

        XCTAssertEqual(normals.temp.avgByHour[0], 10)
        XCTAssertNil(normals.temp.avgByHour[1], "the only sample was null")
        XCTAssertNil(normals.temp.avgByHour[7], "no samples at all")
        XCTAssertNil(normals.wetBulb.avgByHour[0])
        // Rain uses 0, not nil, for missing hours.
        XCTAssertEqual(normals.rain.avgByHour[0], 0.5)
        XCTAssertEqual(normals.rain.avgByHour[7], 0)
        XCTAssertEqual(normals.rain.wetHourProbabilityByHour[0], 1)
        XCTAssertEqual(normals.rain.wetHourProbabilityByHour[1], 0)
    }

    // MARK: - §6.7 Year-to-date rain (hand-computed toy dataset)

    /// Three years of a three-day "year", with the current year's archive
    /// stopping one day short — the publication lag (§14.3).
    func testYTDCumulativeMathOnAToyDataset() throws {
        // 2024: 1, 2, 3   2025: 3, 3, 3   2026: 10, 20, (missing)
        let response = ArchiveResponse(daily: .init(
            time: [
                "2024-01-01", "2024-01-02", "2024-01-03",
                "2025-01-01", "2025-01-02", "2025-01-03",
                "2026-01-01", "2026-01-02", "2026-01-03"
            ],
            precipitationSum: [1, 2, 3, 3, 3, 3, 10, 20, nil]))

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let now = calendar.date(from: DateComponents(
            year: 2026, month: 1, day: 3, hour: 12))!

        let ytd = try XCTUnwrap(YTDRainBuilder.build(
            response: response, now: now, timeZone: .gmt, startYear: 2024))

        XCTAssertEqual(ytd.labels, ["01-01", "01-02", "01-03"])
        XCTAssertEqual(ytd.thisYear, 2026)
        XCTAssertEqual(ytd.histYears, 2)

        // Missing day counts as 0, so the running total plateaus.
        XCTAssertEqual(ytd.cumCurrentYear, [10, 30, 30])
        // 2024 cumulative 1, 3, 6; 2025 cumulative 3, 6, 9 → means 2, 4.5, 7.5.
        XCTAssertEqual(ytd.cumHistAvg, [2, 4.5, 7.5])

        // The archive's true edge is the last day with a value, not the last row.
        XCTAssertEqual(ytd.latestDate, "2026-01-02")
    }

    /// The historical extension stops at the end of the calendar year.
    func testYTDExtensionIsCappedAtYearEnd() throws {
        var time: [String] = []
        var values: [Double?] = []
        for year in [2024, 2025, 2026] {
            for day in 27...31 {
                time.append("\(year)-12-\(day)")
                values.append(1)
            }
        }
        // Labels need the whole of 2026 up to Dec 30, but only December has data;
        // every other day simply contributes 0.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let now = calendar.date(from: DateComponents(
            year: 2026, month: 12, day: 30, hour: 12))!

        let ytd = try XCTUnwrap(YTDRainBuilder.build(
            response: ArchiveResponse(daily: .init(time: time, precipitationSum: values)),
            now: now, timeZone: .gmt, startYear: 2024))

        XCTAssertEqual(ytd.latestDate, "2026-12-30")
        // Only Dec 31 remains in the year, so the extension has a single point.
        XCTAssertEqual(ytd.cumHistAvgExt.count, 1)
        XCTAssertEqual(ytd.labels.count, 364, "2026 is not a leap year; Jan 1 – Dec 30")
    }

    /// The projection continues from the last actual value using forecast sums.
    func testYTDProjectionStartsAfterLatestDate() throws {
        let ytd = YTDRain(
            labels: ["01-01", "01-02", "01-03"],
            cumCurrentYear: [10, 30, 30], cumHistAvg: [2, 4.5, 7.5],
            cumHistAvgExt: [], thisYear: 2026, startYear: 2024, histYears: 2,
            latestDate: "2026-01-02")

        let forecast = ForecastResponse(
            latitude: 0, longitude: 0, timezone: "UTC", utcOffsetSeconds: 0,
            daily: .init(
                time: ["2026-01-01", "2026-01-02", "2026-01-03", "2026-01-04", "2026-01-05"],
                precipitationSum: [10, 20, 5, 1, nil]),
            hourly: .init(time: []))

        let projection = YTDRainBuilder.projection(forecast: forecast, ytd: ytd)
        XCTAssertEqual(projection.map(\.date), ["2026-01-03", "2026-01-04", "2026-01-05"])
        // Starts from 30 (the last actual cumulative); the null day adds nothing.
        XCTAssertEqual(projection.map(\.cumulative), [35, 36, 36])
    }

    func testYTDFromFixture() throws {
        let ytd = try XCTUnwrap(YTDRainBuilder.build(
            response: try Fixture.ytd, now: Fixture.now, timeZone: london))

        XCTAssertEqual(ytd.thisYear, 2026)
        XCTAssertEqual(ytd.startYear, 2000)
        XCTAssertEqual(ytd.labels.first, "01-01")
        XCTAssertEqual(ytd.labels.last, "08-05")
        XCTAssertEqual(ytd.labels.count, 217, "Jan 1 – Aug 5 in a non-leap year")
        XCTAssertEqual(ytd.cumCurrentYear.count, ytd.labels.count)
        XCTAssertEqual(ytd.cumHistAvg.count, ytd.labels.count)
        // The fixture was truncated to 2000–2003 plus the current year (§11.1).
        XCTAssertEqual(ytd.histYears, 4)

        // Cumulative series only ever increase.
        XCTAssertEqual(ytd.cumCurrentYear, ytd.cumCurrentYear.sorted())
        XCTAssertEqual(ytd.cumHistAvg, ytd.cumHistAvg.sorted())
        XCTAssertGreaterThan(ytd.cumHistAvg.last ?? 0, 100, "London gets >100 mm by August")
        XCTAssertFalse(ytd.cumHistAvgExt.isEmpty)
    }
}
