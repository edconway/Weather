import XCTest
@testable import WeatherCore

final class DuoArrangementTests: XCTestCase {

    func testCoverAndOpenDisplayStayOneColumn() {
        XCTAssertEqual(
            DuoArrangement.arrangement(containerWidth: 390, containerHeight: 844, division: nil),
            .column)
        XCTAssertEqual(
            DuoArrangement.arrangement(containerWidth: 466, containerHeight: 678, division: nil),
            .column)
        XCTAssertEqual(
            DuoArrangement.arrangement(containerWidth: 951, containerHeight: 669, division: nil),
            .column)
        XCTAssertEqual(
            DuoArrangement.arrangement(containerWidth: 669, containerHeight: 951, division: nil),
            .column)
    }

    func testBookFoldSplitsOnEitherSideOfTheHinge() {
        let hinge = DuoDivision(x: 465.5, y: 0, width: 20, height: 669)
        XCTAssertEqual(
            DuoArrangement.arrangement(containerWidth: 951, containerHeight: 669, division: hinge),
            .book(leading: 465.5, gap: 20, trailing: 465.5))
    }

    func testTentFoldStacksAboveAndBelowTheHinge() {
        let hinge = DuoDivision(x: 0, y: 465.5, width: 669, height: 20)
        XCTAssertEqual(
            DuoArrangement.arrangement(containerWidth: 669, containerHeight: 951, division: hinge),
            .tent(top: 465.5, gap: 20, bottom: 465.5))
    }

    func testAFoldThatLeavesNoRoomStaysOneColumn() {
        let sliver = DuoDivision(x: 900, y: 0, width: 20, height: 669)
        XCTAssertEqual(
            DuoArrangement.arrangement(containerWidth: 951, containerHeight: 669, division: sliver),
            .column)
    }
}
