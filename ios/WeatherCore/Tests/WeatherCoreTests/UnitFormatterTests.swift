import XCTest
@testable import WeatherCore

final class UnitFormatterTests: XCTestCase {

    private let metric = UnitFormatter(imperial: false)
    private let imperial = UnitFormatter(imperial: true)

    func testTemperature() {
        XCTAssertEqual(metric.temperature(21.4), "21°C")
        XCTAssertEqual(metric.temperature(21.6), "22°C")
        XCTAssertEqual(imperial.temperature(21.4), "71°F")   // 70.52
        XCTAssertEqual(imperial.temperature(0), "32°F")
        XCTAssertEqual(imperial.temperature(-40), "-40°F")
        XCTAssertEqual(metric.temperature(nil), "—")
        XCTAssertEqual(metric.temperatureShort(21.4), "21°")
        XCTAssertEqual(metric.temperatureNumber(21.6), 22)
    }

    /// §14.5 — a difference scales but does not offset.
    func testTemperatureDeltaDoesNotOffset() {
        XCTAssertEqual(metric.temperatureDelta(3), 3, accuracy: 1e-9)
        XCTAssertEqual(imperial.temperatureDelta(3), 5.4, accuracy: 1e-9)
        XCTAssertEqual(imperial.temperatureDelta(-3), -5.4, accuracy: 1e-9)
        XCTAssertEqual(imperial.temperatureDelta(0), 0, accuracy: 1e-9)
    }

    func testWind() {
        XCTAssertEqual(metric.wind(19.8), "20 km/h")
        XCTAssertEqual(imperial.wind(19.8), "12 mph")   // 12.30
        XCTAssertEqual(metric.wind(nil), "—")
    }

    /// Values verified against `toFixed` in node — see `UnitFormatter.fixed`.
    func testPrecipitation() {
        XCTAssertEqual(metric.precipitation(1.25), "1.3 mm", "exact halves round away from zero")
        XCTAssertEqual(metric.precipitation(1.35), "1.4 mm")
        XCTAssertEqual(metric.precipitation(0), "0.0 mm")
        XCTAssertEqual(imperial.precipitation(25.4), "1.00\"")
        XCTAssertEqual(imperial.precipitation(1.2), "0.05\"")
        XCTAssertEqual(metric.precipitation(nil), "—")

        // The compact form used in charts elides negligible amounts.
        XCTAssertEqual(metric.precipitationCompact(0.05), "—")
        XCTAssertEqual(metric.precipitationCompact(1.2), "1.2mm")
        XCTAssertEqual(imperial.precipitationCompact(0.1), "—")
        XCTAssertEqual(imperial.precipitationCompact(25.4), "1.00\"")
    }

    /// §5.3 — the exact UV bands.
    func testUVLabels() {
        XCTAssertEqual(UnitFormatter.uvLabel(0), "Low")
        XCTAssertEqual(UnitFormatter.uvLabel(2), "Low")
        XCTAssertEqual(UnitFormatter.uvLabel(2.1), "Moderate")
        XCTAssertEqual(UnitFormatter.uvLabel(5), "Moderate")
        XCTAssertEqual(UnitFormatter.uvLabel(5.1), "High")
        XCTAssertEqual(UnitFormatter.uvLabel(7), "High")
        XCTAssertEqual(UnitFormatter.uvLabel(7.1), "Very High")
        XCTAssertEqual(UnitFormatter.uvLabel(10), "Very High")
        XCTAssertEqual(UnitFormatter.uvLabel(10.1), "Extreme")

        // 4.05 is below the half in binary, so toFixed(1) — and this port — say 4.0.
        XCTAssertEqual(metric.uvIndex(4.05), "4.0 Moderate")
        XCTAssertEqual(metric.uvIndex(5.75), "5.8 High")
        XCTAssertEqual(metric.uvIndex(nil), "—")
    }

    func testRawConversionsMatchTheWebApp() {
        XCTAssertEqual(UnitFormatter.celsiusToFahrenheit(100), 212, accuracy: 1e-9)
        XCTAssertEqual(UnitFormatter.kmhToMph(100), 62.1371, accuracy: 1e-6)
        // The web app's constant is 0.0393701, not the exact 1/25.4.
        XCTAssertEqual(UnitFormatter.mmToInches(25.4), 1.00000054, accuracy: 1e-7)
    }

    func testRainChance() {
        XCTAssertEqual(metric.rainChance(25), "25%")
        XCTAssertEqual(metric.rainChance(nil), "—")
    }
}
