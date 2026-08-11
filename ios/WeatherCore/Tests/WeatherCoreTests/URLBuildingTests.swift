import XCTest
@testable import WeatherCore

final class URLBuildingTests: XCTestCase {

    private func query(_ url: URL) -> [String: String] {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        return Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map {
            ($0.name, $0.value ?? "")
        })
    }

    /// §4.1 — the request must match the web app's, plus `is_day` (§1.4.1) and
    /// `sunrise`/`sunset` for the corner complication's next sun event.
    func testForecastURL() {
        let url = OpenMeteoClient.forecastURL(latitude: 51.5074, longitude: -0.1278)
        XCTAssertEqual(url.host, "api.open-meteo.com")
        XCTAssertEqual(url.path, "/v1/forecast")

        let q = query(url)
        XCTAssertEqual(q["timezone"], "auto")
        XCTAssertEqual(q["forecast_days"], "7")
        XCTAssertEqual(q["past_days"], "7")
        XCTAssertEqual(q["past_hours"], "24")
        XCTAssertEqual(q["forecast_hours"], "48")
        XCTAssertEqual(
            q["daily"],
            "weather_code,temperature_2m_max,temperature_2m_min,"
            + "wet_bulb_temperature_2m_max,wet_bulb_temperature_2m_min,"
            + "apparent_temperature_max,precipitation_sum,precipitation_probability_max,"
            + "wind_speed_10m_max,uv_index_max,sunrise,sunset")
        XCTAssertEqual(
            q["hourly"],
            "temperature_2m,wet_bulb_temperature_2m,apparent_temperature,precipitation,"
            + "precipitation_probability,rain,showers,snowfall,weather_code,is_day")
    }

    /// §4.3
    func testSearchURLEscapesTheQuery() {
        let url = OpenMeteoClient.searchURL(query: "São Paulo")
        XCTAssertEqual(url.host, "geocoding-api.open-meteo.com")
        let q = query(url)
        XCTAssertEqual(q["name"], "São Paulo")
        XCTAssertEqual(q["count"], "6")
        XCTAssertEqual(q["language"], "en")
        XCTAssertEqual(q["format"], "json")
        XCTAssertFalse(url.absoluteString.contains(" "), "the space must be percent-encoded")
    }

    /// §4.2a — ten full years ending last December.
    func testClimatologyURL() {
        let url = ArchiveClient.climatologyURL(latitude: 51.5, longitude: -0.1, thisYear: 2026)
        XCTAssertEqual(url.host, "archive-api.open-meteo.com")
        let q = query(url)
        XCTAssertEqual(q["start_date"], "2016-01-01")
        XCTAssertEqual(q["end_date"], "2025-12-31")
        XCTAssertEqual(
            q["daily"],
            "temperature_2m_max,temperature_2m_min,wet_bulb_temperature_2m_max,"
            + "wet_bulb_temperature_2m_min,precipitation_sum")
        XCTAssertNil(q["hourly"])
    }

    /// §4.2b — five windows, ±7 days, in the five preceding years.
    func testHourlyNormalsURLs() {
        let dateKit = DateKit(timeZone: Fixture.londonTimeZone)
        let urls = ArchiveClient.hourlyNormalsURLs(
            latitude: 51.5, longitude: -0.1, now: Fixture.now, dateKit: dateKit)
        XCTAssertEqual(urls.count, 5)

        let windows = urls.map { query($0) }.map { ($0["start_date"]!, $0["end_date"]!) }
        XCTAssertEqual(windows[0].0, "2025-07-29")
        XCTAssertEqual(windows[0].1, "2025-08-12")
        XCTAssertEqual(windows[4].0, "2021-07-29")
        XCTAssertEqual(windows[4].1, "2021-08-12")
        XCTAssertEqual(query(urls[0])["hourly"],
                       "temperature_2m,wet_bulb_temperature_2m,precipitation")
    }

    /// The web app builds the window with `new Date(yr, mo, dy ± 7)`, so a day
    /// near a month boundary rolls into the neighbouring month.
    func testHourlyNormalsWindowRollsOverMonthBoundaries() {
        let dateKit = DateKit(timeZone: .gmt)
        var components = DateComponents()
        components.year = 2026
        components.month = 1
        components.day = 3
        components.hour = 9
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let now = calendar.date(from: components)!

        let urls = ArchiveClient.hourlyNormalsURLs(
            latitude: 0, longitude: 0, now: now, dateKit: dateKit)
        let first = query(urls[0])
        XCTAssertEqual(first["start_date"], "2024-12-27")
        XCTAssertEqual(first["end_date"], "2025-01-10")
    }

    /// §4.2c
    func testYTDRainURL() {
        let url = ArchiveClient.ytdRainURL(
            latitude: 51.5, longitude: -0.1, todayString: "2026-08-05")
        let q = query(url)
        XCTAssertEqual(q["start_date"], "2000-01-01")
        XCTAssertEqual(q["end_date"], "2026-08-05")
        XCTAssertEqual(q["daily"], "precipitation_sum")
    }
}
