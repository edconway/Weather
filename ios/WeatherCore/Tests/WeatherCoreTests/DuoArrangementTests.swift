import XCTest
@testable import WeatherCore

final class DuoArrangementTests: XCTestCase {

    func testCoverAndAPhoneWithoutAHingeStayOneColumn() {
        XCTAssertEqual(
            DuoArrangement.arrangement(containerWidth: 390, containerHeight: 844, division: nil),
            .column)
        XCTAssertEqual(
            DuoArrangement.arrangement(containerWidth: 466, containerHeight: 678, division: nil),
            .column)
        XCTAssertEqual(
            DuoArrangement.arrangement(containerWidth: 678, containerHeight: 466, division: nil),
            .column)
        // Width alone never splits. A wide window with no division rect stays one column.
        XCTAssertEqual(
            DuoArrangement.arrangement(containerWidth: 951, containerHeight: 669, division: nil),
            .column)
    }

    func testUnfoldedBookMeetsAtTheHinge() {
        // Inner display, flat, landscape. The division is reported and inactive.
        let hinge = DuoDivision(x: 455, y: 0, width: 40, height: 669)
        XCTAssertEqual(
            DuoArrangement.arrangement(
                containerWidth: 951, containerHeight: 669,
                division: hinge, hingeSeparates: false),
            .book(leading: 475, gap: 0, trailing: 476))
    }

    func testBookFoldLeavesTheHingeEmpty() {
        let hinge = DuoDivision(x: 455, y: 0, width: 40, height: 669)
        XCTAssertEqual(
            DuoArrangement.arrangement(
                containerWidth: 951, containerHeight: 669,
                division: hinge, hingeSeparates: true),
            .book(leading: 455, gap: 40, trailing: 456))
    }

    func testUnfoldedTentMeetsAtTheHinge() {
        let hinge = DuoDivision(x: 0, y: 455.5, width: 669, height: 40)
        XCTAssertEqual(
            DuoArrangement.arrangement(
                containerWidth: 669, containerHeight: 951,
                division: hinge, hingeSeparates: false),
            .tent(top: 475.5, gap: 0, bottom: 475.5))
    }

    func testTentFoldLeavesTheHingeEmpty() {
        let hinge = DuoDivision(x: 0, y: 455.5, width: 669, height: 40)
        XCTAssertEqual(
            DuoArrangement.arrangement(
                containerWidth: 669, containerHeight: 951,
                division: hinge, hingeSeparates: true),
            .tent(top: 455.5, gap: 40, bottom: 455.5))
    }

    func testAFoldThatLeavesNoRoomStaysOneColumn() {
        let sliver = DuoDivision(x: 900, y: 0, width: 20, height: 669)
        XCTAssertEqual(
            DuoArrangement.arrangement(containerWidth: 951, containerHeight: 669, division: sliver),
            .column)
    }

    func testOcclusionOnTheTrailingEdgePadsThatEdge() {
        let camera = DuoDivision(x: 900, y: 20, width: 80, height: 40)
        let padding = DuoOcclusionLayout.padding(
            frames: [camera], containerWidth: 951, containerHeight: 669)
        XCTAssertEqual(padding.trailing, 51, accuracy: 0.001)
        XCTAssertEqual(padding.leading, 0, accuracy: 0.001)
        XCTAssertEqual(padding.top, 0, accuracy: 0.001)
    }

    func testOcclusionAboveTheViewPadsTheTop() {
        let camera = DuoDivision(x: 180, y: -10, width: 40, height: 50)
        let padding = DuoOcclusionLayout.padding(
            frames: [camera], containerWidth: 400, containerHeight: 800)
        XCTAssertEqual(padding.top, 40, accuracy: 0.001)
        XCTAssertEqual(padding.leading, 0, accuracy: 0.001)
    }

    func testAnOcclusionOutsideTheViewAddsNoPadding() {
        let outside = DuoDivision(x: -80, y: 10, width: 20, height: 20)
        XCTAssertEqual(
            DuoOcclusionLayout.padding(frames: [outside], containerWidth: 390, containerHeight: 800),
            .zero)
    }
}
