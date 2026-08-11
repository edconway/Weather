import XCTest
@testable import WeatherCore

final class SunEventTests: XCTestCase {

    private func forecast(
        timezone: String = "Europe/London",
        offset: Int = 3600,
        times: [String],
        sunrise: [String?],
        sunset: [String?]
    ) -> ForecastResponse {
        ForecastResponse(
            latitude: 51.5, longitude: -0.13, timezone: timezone, utcOffsetSeconds: offset,
            daily: .init(time: times, sunrise: sunrise, sunset: sunset),
            hourly: .init(time: []))
    }

    private func date(
        _ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int = 0, zone: String = "Europe/London"
    ) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        return calendar.date(from: DateComponents(
            year: y, month: m, day: d, hour: h, minute: min))!
    }

    // MARK: - Fixture

    func testNextEventFromTheFixture() throws {
        let forecast = try Fixture.forecast
        // Sanity-check the fixture actually carries sun times.
        XCTAssertEqual(forecast.daily.sunrise.count, 14)
        XCTAssertEqual(forecast.daily.sunset.count, 14)
        XCTAssertEqual(forecast.daily.sunrise[7], "2026-08-05T05:30")
        XCTAssertEqual(forecast.daily.sunset[7], "2026-08-05T20:42")

        // Fixture "now" is 12:00 — sunset is next.
        let event = try XCTUnwrap(SunEvent.next(forecast: forecast, now: Fixture.now))
        XCTAssertEqual(event.kind, .sunset)
        XCTAssertEqual(event.timeString, "2026-08-05T20:42")
    }

    /// Before dawn the next event is today's sunrise; after dusk it is
    /// tomorrow's — the flip the corner complication exists to show.
    func testEventFlipsAcrossTheDay() throws {
        let forecast = try Fixture.forecast

        let beforeDawn = try XCTUnwrap(
            SunEvent.next(forecast: forecast, now: date(2026, 8, 5, 4)))
        XCTAssertEqual(beforeDawn.kind, .sunrise)
        XCTAssertEqual(beforeDawn.timeString, "2026-08-05T05:30")

        let afterDusk = try XCTUnwrap(
            SunEvent.next(forecast: forecast, now: date(2026, 8, 5, 21)))
        XCTAssertEqual(afterDusk.kind, .sunrise)
        XCTAssertEqual(afterDusk.timeString, "2026-08-06T05:32", "tomorrow's sunrise")

        // One minute before sunset, sunset is still next.
        let justBeforeSunset = try XCTUnwrap(
            SunEvent.next(forecast: forecast, now: date(2026, 8, 5, 20, 41)))
        XCTAssertEqual(justBeforeSunset.kind, .sunset)

        // One minute after, it has moved on.
        let justAfterSunset = try XCTUnwrap(
            SunEvent.next(forecast: forecast, now: date(2026, 8, 5, 20, 43)))
        XCTAssertEqual(justAfterSunset.kind, .sunrise)
    }

    /// The comparison is strictly "after now", so an event exactly at the
    /// current minute is already past.
    func testEventExactlyNowIsNotNext() {
        let response = forecast(
            times: ["2026-08-05"],
            sunrise: ["2026-08-05T05:30"],
            sunset: ["2026-08-05T20:42"])
        let event = SunEvent.next(forecast: response, now: date(2026, 8, 5, 20, 42))
        XCTAssertNil(event, "no later event exists in this one-day response")
    }

    /// §14.2 — the decision runs on the *location's* clock, not the device's.
    func testUsesTheLocationTimezone() {
        // 2026-08-05 08:00 in Los Angeles is 2026-08-06 03:00 in Auckland,
        // which is before Auckland's 07:30 sunrise.
        let response = forecast(
            timezone: "Pacific/Auckland", offset: 12 * 3600,
            times: ["2026-08-05", "2026-08-06"],
            sunrise: ["2026-08-05T07:31", "2026-08-06T07:30"],
            sunset: ["2026-08-05T17:35", "2026-08-06T17:36"])

        let instant = date(2026, 8, 5, 8, zone: "America/Los_Angeles")
        let event = try? XCTUnwrap(SunEvent.next(forecast: response, now: instant))
        XCTAssertEqual(event?.kind, .sunrise)
        XCTAssertEqual(event?.timeString, "2026-08-06T07:30")
    }

    /// Polar summer: Open-Meteo returns nulls, and "no next event" is the
    /// truthful answer rather than a fabricated time.
    func testNullSunTimesYieldNoEvent() {
        let response = forecast(
            timezone: "Europe/Oslo", offset: 7200,
            times: ["2026-06-21", "2026-06-22"],
            sunrise: [nil, nil],
            sunset: [nil, nil])
        XCTAssertNil(SunEvent.next(forecast: response, now: date(2026, 6, 21, 12)))
    }

    func testMissingSunArraysYieldNoEvent() throws {
        let response = forecast(
            times: ["2026-08-05"], sunrise: [], sunset: [])
        XCTAssertNil(SunEvent.next(forecast: response, now: Fixture.now))
    }

    // MARK: - Rendering

    func testCurvedLabelText() throws {
        let entries = WidgetSnapshotBuilder.entries(
            forecast: try Fixture.forecast, location: Fixture.london, payload: nil,
            imperial: false, now: Fixture.now)
        let entry = try XCTUnwrap(entries.first)

        XCTAssertEqual(entry.nextSunEvent?.kind, .sunset)
        XCTAssertEqual(entry.timeZoneIdentifier, "Europe/London")
        // Rendered in the location's zone; the literal clock digits must survive.
        let text = try XCTUnwrap(entry.sunEventText)
        XCTAssertTrue(text.hasPrefix("↓"), "sunset marker, got \(text)")
        XCTAssertTrue(text.contains("42"), "should carry the 20:42 minutes, got \(text)")

        let spoken = try XCTUnwrap(entry.sunEventAccessibilityText)
        XCTAssertTrue(spoken.hasPrefix("sunset at "), spoken)
    }

    /// Polar summer: no sun event, so the arc shows today's range instead.
    func testCurvedLabelFallsBackToRange() {
        let entry = WeatherEntrySnapshot(
            date: Fixture.now, locationName: "Longyearbyen", temperature: 6,
            high: 8, low: 3, rainChance: 10, conditionCode: 3, isDay: true,
            temperatureDelta: nil, imperial: false,
            nextSunEvent: nil, timeZoneIdentifier: "Europe/Oslo")
        XCTAssertNil(entry.sunEventText)
        XCTAssertEqual(
            CurrentConditionsContent(entry: entry, layout: .corner).cornerCurvedText,
            "H8 L3")
    }

    /// `SUNSET 20:45` — the arc carries the event name and time; the corner
    /// itself carries the temperature.
    func testCurvedLabelNamesTheSunEvent() {
        let entry = WeatherEntrySnapshot(
            date: Fixture.now, locationName: "London", temperature: 21,
            high: 24, low: 15, rainChance: 40, conditionCode: 2, isDay: true,
            temperatureDelta: 3, imperial: false,
            nextSunEvent: SunEvent(kind: .sunset, timeString: "2026-08-05T20:45"),
            timeZoneIdentifier: "Europe/London")

        let text = CurrentConditionsContent(entry: entry, layout: .corner).cornerCurvedText
        XCTAssertTrue(text.hasPrefix("SUNSET "), text)
        XCTAssertTrue(text.contains("45"), text)
        // The arc is wide but not unlimited.
        XCTAssertLessThanOrEqual(text.count, 16, "curved label must stay compact: \(text)")
    }

    func testCurvedLabelNamesSunriseBeforeDawn() throws {
        let entries = WidgetSnapshotBuilder.entries(
            forecast: try Fixture.forecast, location: Fixture.london, payload: nil,
            imperial: false, now: date(2026, 8, 5, 4))
        let entry = try XCTUnwrap(entries.first)
        let text = CurrentConditionsContent(entry: entry, layout: .corner).cornerCurvedText
        XCTAssertTrue(text.hasPrefix("SUNRISE "), text)
    }

    /// Later timeline entries recompute the event, so the corner flips on its
    /// own between reloads.
    func testEntriesRecomputeTheEventPerHour() throws {
        let forecast = try Fixture.forecast
        // 18:00 → the 20:42 sunset is next; six hourly entries stay before it.
        let evening = WidgetSnapshotBuilder.entries(
            forecast: forecast, location: Fixture.london, payload: nil,
            imperial: false, now: date(2026, 8, 5, 18))
        XCTAssertFalse(evening.isEmpty)
        let kinds = Set(evening.compactMap { $0.nextSunEvent?.kind })
        XCTAssertTrue(kinds.contains(.sunset))
        // Entries past 20:42 must have flipped to sunrise.
        if evening.count >= 4 {
            XCTAssertEqual(evening[3].nextSunEvent?.kind, .sunrise,
                           "21:00 entry is past sunset")
        }
    }
}
