import XCTest
@testable import WeatherCore

final class PrecisePlaceLabelTests: XCTestCase {
    func testNeighbourhoodBeatsStreet() {
        XCTAssertEqual(
            PrecisePlaceLabel.format(
                neighbourhood: "Shoreditch",
                streetNumber: "1",
                street: "Old Street",
                city: "London",
                latitude: 51.527, longitude: -0.087),
            "Shoreditch")
    }

    func testStreetWithNumberWhenThereIsNoNeighbourhood() {
        XCTAssertEqual(
            PrecisePlaceLabel.format(
                neighbourhood: "London",
                streetNumber: "10",
                street: "Downing Street",
                city: "London",
                latitude: 51.503, longitude: -0.127),
            "10 Downing Street")
    }

    func testStreetWithoutANumber() {
        XCTAssertEqual(
            PrecisePlaceLabel.format(
                neighbourhood: nil,
                streetNumber: "  ",
                street: "Baker Street",
                city: "London",
                latitude: 51.52, longitude: -0.16),
            "Baker Street")
    }

    func testCoordinatesWhenGeocodingHasOnlyTheCity() {
        XCTAssertEqual(
            PrecisePlaceLabel.format(
                neighbourhood: nil,
                streetNumber: nil,
                street: nil,
                city: "London",
                latitude: 51.50744, longitude: -0.12786),
            "51.5074, -0.1279")
    }
}
