import XCTest
@testable import WeatherCore

final class AppleWeatherTests: XCTestCase {

    private func date(_ hour: Int, _ minute: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.date(from: DateComponents(year: 2026, month: 11, day: 14, hour: hour, minute: minute))!
    }

    private func point(_ minute: Int, intensity: Double) -> AppleMinutePoint {
        AppleMinutePoint(
            date: date(9, minute),
            intensityMillimetresPerHour: intensity,
            chance: intensity > 0 ? 0.8 : 0)
    }

    private func snapshot(
        minutes: [AppleMinutePoint] = [],
        availability: AppleMinuteAvailability = .available,
        failure: AppleWeatherFailure? = nil
    ) -> AppleWeatherSnapshot {
        AppleWeatherSnapshot(
            minutes: minutes,
            alerts: [],
            minuteAvailability: availability,
            failure: failure,
            attribution: nil,
            fetchedAt: date(9, 0),
            expiresAt: date(9, 10))
    }

    func testMillimetresPerHourFromMetresPerSecond() {
        XCTAssertEqual(
            AppleWeatherStatus.millimetresPerHour(fromMetresPerSecond: 1.0 / 3_600_000),
            1,
            accuracy: 0.000_001)
    }

    func testClassifyAuthOfflineAndOther() {
        let auth = NSError(
            domain: "WeatherDaemon.WDSJWTAuthenticatorServiceListener.Errors",
            code: 2,
            userInfo: [NSLocalizedDescriptionKey: "The operation couldn’t be completed."])
        XCTAssertEqual(AppleWeatherStatus.classify(auth), .notAuthorised)

        let entitlement = NSError(
            domain: "WeatherKit",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Missing entitlement"])
        XCTAssertEqual(AppleWeatherStatus.classify(entitlement), .notAuthorised)

        XCTAssertEqual(
            AppleWeatherStatus.classify(URLError(.notConnectedToInternet)),
            .offline)
        XCTAssertEqual(AppleWeatherStatus.classify(URLError(.timedOut)), .offline)
        XCTAssertEqual(AppleWeatherStatus.classify(URLError(.networkConnectionLost)), .offline)
        XCTAssertEqual(AppleWeatherStatus.classify(URLError(.badServerResponse)), .unavailable)
    }

    func testDisplayMinutesOnlyWhenAppleReturnedThem() {
        let minutes = [point(0, intensity: 1.2)]
        XCTAssertEqual(snapshot(minutes: minutes).displayMinutes, minutes)
        XCTAssertTrue(snapshot(minutes: [], availability: .available).displayMinutes.isEmpty)
        XCTAssertTrue(snapshot(minutes: minutes, availability: .unavailable).displayMinutes.isEmpty)
        XCTAssertTrue(
            snapshot(minutes: minutes, failure: .notAuthorised).displayMinutes.isEmpty)
    }

    func testStatusLines() {
        XCTAssertEqual(AppleWeatherStatus.appleLine(nil).badge, "Checking")
        XCTAssertEqual(AppleWeatherStatus.appleLine(snapshot(minutes: [point(0, intensity: 0.2)])).badge, "Live")
        XCTAssertEqual(
            AppleWeatherStatus.appleLine(snapshot(availability: .unavailable)).badge,
            "Limited")
        XCTAssertTrue(
            AppleWeatherStatus.appleLine(snapshot(failure: .notAuthorised)).text
                .contains("hasn't enabled"))
        XCTAssertEqual(
            AppleWeatherStatus.appleLine(snapshot(failure: .notAuthorised)).badge,
            "Off")
        XCTAssertEqual(AppleWeatherStatus.appleLine(snapshot(failure: .offline)).badge, "Retry")
        XCTAssertEqual(AppleWeatherStatus.appleLine(snapshot(failure: .unavailable)).badge, "Retry")

        let fresh = AppleWeatherStatus.openMeteoLine(
            isStale: false, updatedAt: date(9, 41), now: date(10, 0),
            timeZone: TimeZone(secondsFromGMT: 0)!)
        XCTAssertEqual(fresh.badge, "Live")
        XCTAssertTrue(fresh.text.contains("updated 09:41"))

        let stale = AppleWeatherStatus.openMeteoLine(
            isStale: true, updatedAt: date(9, 41).addingTimeInterval(-86_400),
            now: date(9, 41), timeZone: TimeZone(secondsFromGMT: 0)!)
        XCTAssertEqual(stale.badge, "Offline")
        XCTAssertTrue(stale.text.contains("last updated"))
    }

    func testSummaryDoesNotInventRain() {
        let dry = (0..<60).map { point($0, intensity: 0) }
        let summary = AppleWeatherStatus.summary(
            minutes: dry, timeZone: TimeZone(secondsFromGMT: 0)!, formatter: UnitFormatter(imperial: false))
        XCTAssertEqual(summary.headline, "No rain in the next hour")

        var shower = (0..<60).map { point($0, intensity: 0) }
        shower[20] = point(20, intensity: 3)
        let wet = AppleWeatherStatus.summary(
            minutes: shower, timeZone: TimeZone(secondsFromGMT: 0)!, formatter: UnitFormatter(imperial: false))
        XCTAssertEqual(wet.headline, "Rain at 09:20")
        XCTAssertTrue(wet.detail.contains("3.0 mm/h"))

        let now = AppleWeatherStatus.summary(
            minutes: [point(0, intensity: 1)],
            timeZone: TimeZone(secondsFromGMT: 0)!,
            formatter: UnitFormatter(imperial: false))
        XCTAssertEqual(now.headline, "Rain now")
    }

    func testHoldOffAndCache() {
        let now = date(12, 0)
        let recent = now.addingTimeInterval(-5 * 60)
        XCTAssertTrue(AppleWeatherStatus.shouldHoldOff(lastNotAuthorisedAt: recent, now: now, bypass: false))
        XCTAssertFalse(AppleWeatherStatus.shouldHoldOff(lastNotAuthorisedAt: recent, now: now, bypass: true))
        XCTAssertFalse(AppleWeatherStatus.shouldHoldOff(
            lastNotAuthorisedAt: now.addingTimeInterval(-16 * 60), now: now, bypass: false))

        XCTAssertTrue(AppleWeatherStatus.shouldCache(snapshot(), now: date(9, 0)))
        XCTAssertFalse(AppleWeatherStatus.shouldCache(snapshot(), now: date(9, 11)))
        XCTAssertFalse(AppleWeatherStatus.shouldCache(snapshot(failure: .offline), now: date(9, 0)))
    }

    func testSnapshotRoundTrip() throws {
        let original = snapshot(minutes: [point(1, intensity: 0.4)])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AppleWeatherSnapshot.self, from: data)
        XCTAssertEqual(decoded, original)

        let failed = snapshot(failure: .notAuthorised)
        let failedData = try JSONEncoder().encode(failed)
        let decodedFailure = try JSONDecoder().decode(AppleWeatherSnapshot.self, from: failedData)
        XCTAssertEqual(decodedFailure.failure, .notAuthorised)
        XCTAssertTrue(decodedFailure.displayMinutes.isEmpty)
    }
}
