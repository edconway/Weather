import XCTest
@testable import WeatherCore

final class DecodingTests: XCTestCase {

    func testForecastFixtureDecodes() throws {
        let forecast = try Fixture.forecast

        XCTAssertEqual(forecast.timezone, "Europe/London")
        XCTAssertEqual(forecast.utcOffsetSeconds, 3600)
        XCTAssertEqual(forecast.locationTimeZone.identifier, "Europe/London")

        // past_days 7 + forecast_days 7
        XCTAssertEqual(forecast.daily.time.count, 14)
        XCTAssertEqual(forecast.daily.time.first, "2026-07-29")
        XCTAssertEqual(forecast.daily.temperature2mMax.count, 14)
        XCTAssertEqual(forecast.daily.precipitationProbabilityMax.count, 14)
        XCTAssertEqual(forecast.daily.uvIndexMax.count, 14)

        // past_hours 24 + forecast_hours 48
        XCTAssertEqual(forecast.hourly.time.count, 72)
        XCTAssertEqual(forecast.hourly.time.first, "2026-08-04T11:00")
        XCTAssertEqual(forecast.hourly.temperature2m.count, 72)
        XCTAssertEqual(forecast.hourly.isDay.count, 72, "is_day is the §1.4.1 addition")
        XCTAssertEqual(forecast.hourly.weatherCode.count, 72)
    }

    func testArchiveFixturesDecode() throws {
        let climatology = try Fixture.climatology
        let daily = try XCTUnwrap(climatology.daily)
        XCTAssertEqual(daily.time.first, "2016-01-01")
        XCTAssertEqual(daily.time.last, "2025-12-31")
        XCTAssertEqual(daily.temperature2mMax.count, daily.time.count)
        XCTAssertEqual(daily.wetBulbTemperature2mMin.count, daily.time.count)
        XCTAssertNil(climatology.hourly)

        for (index, window) in try Fixture.hourlyNormalWindows.enumerated() {
            let hourly = try XCTUnwrap(window.hourly, "window \(index + 1)")
            XCTAssertEqual(hourly.time.count, 15 * 24, "15-day window, hourly")
            XCTAssertEqual(hourly.temperature2m.count, hourly.time.count)
            XCTAssertEqual(hourly.precipitation.count, hourly.time.count)
            XCTAssertNil(window.daily)
        }

        let ytd = try Fixture.ytd
        let ytdDaily = try XCTUnwrap(ytd.daily)
        XCTAssertEqual(ytdDaily.time.first, "2000-01-01")
        XCTAssertEqual(ytdDaily.precipitationSum.count, ytdDaily.time.count)
    }

    func testGeocodingFixtureDecodes() throws {
        let results = try XCTUnwrap(Fixture.geocoding.results)
        XCTAssertEqual(results.count, 6)
        let paris = try XCTUnwrap(results.first)
        XCTAssertEqual(paris.name, "Paris")
        XCTAssertEqual(paris.countryCode, "FR")
        XCTAssertEqual(paris.admin1, "Île-de-France Region")
        XCTAssertEqual(paris.displayName, "Paris, Île-de-France Region, France")
        XCTAssertEqual(paris.detail, "Île-de-France Region, FR")
    }

    /// §14.3: `null` elements must survive decoding as `nil`, not collapse or throw.
    func testNullElementsArePreserved() throws {
        let json = """
        {
          "latitude": 51.5, "longitude": -0.12,
          "timezone": "Europe/London", "utc_offset_seconds": 3600,
          "daily": {
            "time": ["2026-08-05", "2026-08-06"],
            "weather_code": [3, null],
            "temperature_2m_max": [25.2, null],
            "temperature_2m_min": [null, 14.5],
            "precipitation_probability_max": [null, 0]
          },
          "hourly": {
            "time": ["2026-08-05T00:00", "2026-08-05T01:00"],
            "temperature_2m": [null, 18.0],
            "is_day": [0, null]
          }
        }
        """.data(using: .utf8)!

        let forecast = try JSONDecoder().decode(ForecastResponse.self, from: json)
        XCTAssertEqual(forecast.daily.weatherCode, [3, nil])
        XCTAssertEqual(forecast.daily.temperature2mMax, [25.2, nil])
        XCTAssertEqual(forecast.daily.temperature2mMin, [nil, 14.5])
        XCTAssertEqual(forecast.daily.precipitationProbabilityMax, [nil, 0])
        XCTAssertEqual(forecast.hourly.temperature2m, [nil, 18.0])
        XCTAssertEqual(forecast.hourly.isDay, [0, nil])
        // Variables that weren't requested decode as empty, not as a failure.
        XCTAssertEqual(forecast.daily.uvIndexMax, [])
        XCTAssertEqual(forecast.hourly.showers, [])
    }

    func testForecastRoundTripsThroughCacheEncoding() throws {
        let original = try Fixture.forecast
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ForecastResponse.self, from: encoded)
        XCTAssertEqual(original, decoded)
    }
}
