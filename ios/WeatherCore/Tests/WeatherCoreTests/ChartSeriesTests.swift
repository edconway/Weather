import XCTest
@testable import WeatherCore

/// Regression test for the ±24 h hourly-chart window (matches
/// `makeHourlyTempChart`'s clamp in charts.js) — the raw API response carries
/// 72 hours (24 past + 48 forecast) so widgets/complications have lookahead,
/// but the chart-facing view must discard hours 25–48 of the forecast rather
/// than displaying the full window.
final class ChartSeriesTests: XCTestCase {

    func testHourlyWindowClampsToPlusMinus24Hours() throws {
        let forecast = try Fixture.forecast
        let conditions = CurrentConditions(forecast: forecast, now: Fixture.now)
        XCTAssertEqual(conditions.nowIndex, 25, "fixture assumption from CurrentConditionsTests")

        let points = ChartSeries.hourly(forecast: forecast, conditions: conditions, normals: nil)

        XCTAssertEqual(points.count, 48)
        XCTAssertEqual(points.first?.id, 1)
        XCTAssertEqual(points.last?.id, 48)
        XCTAssertEqual(points.filter(\.isPast).count, 24)
        XCTAssertEqual(points.filter { !$0.isPast }.count, 24)
    }
}
