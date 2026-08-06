import XCTest
@testable import WeatherCore

/// Hits the real Open-Meteo API. Skipped unless `WEATHERCORE_LIVE_TESTS=1`, so
/// CI stays hermetic (§11.1).
///
///     WEATHERCORE_LIVE_TESTS=1 swift test --filter LiveSmokeTests
final class LiveSmokeTests: XCTestCase {

    private func requireLive() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["WEATHERCORE_LIVE_TESTS"] == "1",
            "set WEATHERCORE_LIVE_TESTS=1 to run live network tests")
    }

    func testForecastForLondon() async throws {
        try requireLive()
        let forecast = try await OpenMeteoClient().forecast(latitude: 51.5, longitude: -0.12)
        XCTAssertEqual(forecast.daily.time.count, 14)
        XCTAssertEqual(forecast.hourly.time.count, 72)
        XCTAssertFalse(forecast.timezone.isEmpty)
        XCTAssertEqual(forecast.hourly.isDay.count, 72)
        // The corner complication depends on these actually coming back.
        XCTAssertEqual(forecast.daily.sunrise.count, 14)
        XCTAssertEqual(forecast.daily.sunset.count, 14)
        XCTAssertNotNil(SunEvent.next(forecast: forecast, now: Date()))
    }

    func testGeocodingSearch() async throws {
        try requireLive()
        let results = try await OpenMeteoClient().search(query: "Paris")
        XCTAssertFalse(results.isEmpty)
        XCTAssertEqual(results.first?.name, "Paris")
    }

    func testClimatologyThroughTheThrottler() async throws {
        try requireLive()
        let client = ArchiveClient(throttler: ArchiveThrottler())
        let response = try await client.climatology(
            latitude: 51.5, longitude: -0.12, thisYear: 2026)
        XCTAssertNotNil(response.daily)
        XCTAssertGreaterThan(response.daily?.time.count ?? 0, 3000)
    }
}
