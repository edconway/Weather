import XCTest
@testable import WeatherCore

/// §11.2 — "given cached fixture data, produces 6 hourly entries with correct temps".
final class WidgetSnapshotTests: XCTestCase {

    private func payload(
        for location: WeatherLocation, tMax: Double, tMin: Double, imperial: Bool = false
    ) -> WatchSyncPayload {
        WatchSyncPayload(
            latitude: location.latitude, longitude: location.longitude, name: location.name,
            imperial: imperial,
            dailyAvg: (0..<14).map { _ in
                DayNormal(tMax: tMax, tMin: tMin, wbMax: nil, wbMin: nil)
            },
            monthlyNormals: [],
            wbAvgByHour: [Double?](repeating: 15, count: 24),
            tempAvgByHour: [Double?](repeating: 16, count: 24),
            generatedAt: Fixture.now)
    }

    func testProducesSixHourlyEntries() throws {
        let forecast = try Fixture.forecast
        let entries = WidgetSnapshotBuilder.entries(
            forecast: forecast, location: Fixture.london, payload: nil,
            imperial: false, now: Fixture.now)

        XCTAssertEqual(entries.count, 6)

        // nowIndex is 25 for this fixture, so entries walk hourly.time[25...30].
        let expectedTemps = (25...30).map { forecast.hourly.temperature2m[$0] }
        XCTAssertEqual(entries.map(\.temperature), expectedTemps)

        // The first entry is stamped "now"; the rest sit on their own hour.
        XCTAssertEqual(entries[0].date, Fixture.now)
        for index in 1..<entries.count {
            XCTAssertGreaterThan(entries[index].date, entries[index - 1].date)
        }
        XCTAssertEqual(
            entries.map(\.date).dropFirst().count, 5,
            "five future entries after 'now'")

        // Hi/lo and rain chance are day-level, so they are constant.
        XCTAssertEqual(Set(entries.map(\.high)), [25.2])
        XCTAssertEqual(Set(entries.map(\.low)), [19.0])
        XCTAssertEqual(Set(entries.map(\.rainChance)), [25])
        XCTAssertEqual(entries.map(\.locationName), Array(repeating: "London", count: 6))
    }

    func testConditionAndDayNightComeFromTheHourlyArrays() throws {
        let forecast = try Fixture.forecast
        let entries = WidgetSnapshotBuilder.entries(
            forecast: forecast, location: Fixture.london, payload: nil,
            imperial: false, now: Fixture.now)

        for (offset, entry) in entries.enumerated() {
            let index = 25 + offset
            XCTAssertEqual(entry.conditionCode, forecast.hourly.weatherCode[index])
            XCTAssertEqual(entry.isDay, (forecast.hourly.isDay[index] ?? 1) != 0)
        }
    }

    /// Without normals the anomaly is absent, and `TempAnomalyContent` falls
    /// back to current conditions.
    func testDeltaIsNilWithoutNormals() throws {
        let entries = WidgetSnapshotBuilder.entries(
            forecast: try Fixture.forecast, location: Fixture.london, payload: nil,
            imperial: false, now: Fixture.now)
        XCTAssertTrue(entries.allSatisfy { $0.temperatureDelta == nil })
        XCTAssertNil(entries.first?.deltaText)
        XCTAssertNil(entries.first?.deltaSentence)
    }

    func testDeltaUsesSyncedNormals() throws {
        // Fixture today: high 25.2, low 19.0 → mean 22.1. Normal mean 18 → +4.1.
        let entries = WidgetSnapshotBuilder.entries(
            forecast: try Fixture.forecast, location: Fixture.london,
            payload: payload(for: Fixture.london, tMax: 21, tMin: 15),
            imperial: false, now: Fixture.now)

        let delta = try XCTUnwrap(entries.first?.temperatureDelta)
        XCTAssertEqual(delta, 4.1, accuracy: 1e-9)
        XCTAssertEqual(entries.first?.deltaText, "+4°")
        XCTAssertEqual(entries.first?.deltaSentence, "4°C warmer than normal")
    }

    /// §9.2 / §14.8 — normals from another city must be ignored, not shown.
    func testDistantNormalsAreRejected() throws {
        let paris = WeatherLocation(
            latitude: 48.8534, longitude: 2.3488, name: "Paris", source: .custom)
        let entries = WidgetSnapshotBuilder.entries(
            forecast: try Fixture.forecast, location: Fixture.london,
            payload: payload(for: paris, tMax: 21, tMin: 15),
            imperial: false, now: Fixture.now)

        XCTAssertTrue(entries.allSatisfy { $0.temperatureDelta == nil },
                      "Paris normals must not be applied to London")
    }

    func testNearbyNormalsAreAccepted() throws {
        // ~4 km from the fixture location: well inside the 25 km guard.
        let nearby = WeatherLocation(
            latitude: 51.54, longitude: -0.1278, name: "Camden", source: .geo)
        let entries = WidgetSnapshotBuilder.entries(
            forecast: try Fixture.forecast, location: Fixture.london,
            payload: payload(for: nearby, tMax: 21, tMin: 15),
            imperial: false, now: Fixture.now)
        XCTAssertNotNil(entries.first?.temperatureDelta)
    }

    /// §14.5 again, this time through the widget's own formatting.
    func testDeltaTextConvertsByScaleOnly() throws {
        let entries = WidgetSnapshotBuilder.entries(
            forecast: try Fixture.forecast, location: Fixture.london,
            payload: payload(for: Fixture.london, tMax: 21, tMin: 15, imperial: true),
            imperial: true, now: Fixture.now)
        // 4.1 °C → 7.38 °F → "+7°", not "+39°".
        XCTAssertEqual(entries.first?.deltaText, "+7°")
        XCTAssertEqual(entries.first?.deltaSentence, "7°F warmer than normal")
    }

    func testNearNormalRendersAsApproximately() throws {
        // Mean 22.1 vs normal 21.6 → +0.5, inside the ±1 band.
        let entries = WidgetSnapshotBuilder.entries(
            forecast: try Fixture.forecast, location: Fixture.london,
            payload: payload(for: Fixture.london, tMax: 24.7, tMin: 18.5),
            imperial: false, now: Fixture.now)
        XCTAssertEqual(entries.first?.deltaText, "≈")
        XCTAssertEqual(entries.first?.deltaSentence, "Near normal")
    }

    func testPositionInRangeIsClamped() {
        let inRange = WeatherEntrySnapshot(
            date: Fixture.now, locationName: "L", temperature: 20, high: 25, low: 15,
            rainChance: nil, conditionCode: 0, isDay: true, temperatureDelta: nil,
            imperial: false)
        XCTAssertEqual(try XCTUnwrap(inRange.positionInRange), 0.5, accuracy: 1e-9)

        // A current reading above today's forecast high is common late in the day.
        let above = WeatherEntrySnapshot(
            date: Fixture.now, locationName: "L", temperature: 30, high: 25, low: 15,
            rainChance: nil, conditionCode: 0, isDay: true, temperatureDelta: nil,
            imperial: false)
        XCTAssertEqual(try XCTUnwrap(above.positionInRange), 1)

        let degenerate = WeatherEntrySnapshot(
            date: Fixture.now, locationName: "L", temperature: 20, high: 20, low: 20,
            rainChance: nil, conditionCode: 0, isDay: true, temperatureDelta: nil,
            imperial: false)
        XCTAssertNil(degenerate.positionInRange, "a zero-width range has no position")
    }

    func testEmptyEntryIsRecognisable() {
        let empty = WeatherEntrySnapshot.empty(date: Fixture.now)
        XCTAssertTrue(empty.isEmpty)
        XCTAssertFalse(WeatherEntrySnapshot.placeholder.isEmpty)
    }

    /// A forecast whose hourly array ends soon yields fewer than six entries
    /// rather than crashing or padding with nonsense.
    func testTruncatedHourlyArrayYieldsFewerEntries() {
        let hours = (0..<3).map { String(format: "2026-08-05T%02d:00", $0 + 12) }
        let forecast = ForecastResponse(
            latitude: 51.5, longitude: -0.13, timezone: "Europe/London",
            utcOffsetSeconds: 3600,
            daily: .init(
                time: ["2026-08-05"], weatherCode: [3],
                temperature2mMax: [25], temperature2mMin: [19],
                precipitationProbabilityMax: [25]),
            hourly: .init(
                time: hours,
                temperature2m: [20, 21, 22],
                weatherCode: [3, 3, 3],
                isDay: [1, 1, 1]))

        let entries = WidgetSnapshotBuilder.entries(
            forecast: forecast, location: Fixture.london, payload: nil,
            imperial: false, now: Fixture.now)
        XCTAssertEqual(entries.count, 3)
        XCTAssertEqual(entries.map(\.temperature), [20, 21, 22])
    }
}
