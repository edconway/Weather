import XCTest
@testable import WeatherCore

final class MMDDTests: XCTestCase {

    func testSimpleDistance() {
        XCTAssertEqual(MMDD.distance("01-15", "01-18"), 3)
        XCTAssertEqual(MMDD.distance("01-18", "01-15"), 3)
        XCTAssertEqual(MMDD.distance("08-05", "08-05"), 0)
        XCTAssertEqual(MMDD.distance("07-31", "08-01"), 1)
    }

    /// The year boundary must wrap: without it, Dec 30 and Jan 2 would look 362
    /// days apart and fall outside every ±3-day window.
    func testWrapsAroundTheYearBoundary() {
        // PLAN DEVIATION §11.2: the plan predicts 3 here. The web app's
        // `_mmddDist` measures in leap year 2020 (366 days) but wraps by
        // subtracting 365, so Dec 30 → Jan 2 comes out as 2. Ground rule 2 says
        // the web app is the reference, so 2 is the ported answer. The only
        // consequence is that a handful of late-December days are one day
        // "closer" than a calendar would say — still well inside the ±3 window
        // the value is used for.
        XCTAssertEqual(MMDD.distance("12-30", "01-02"), 2)
        XCTAssertEqual(MMDD.distance("01-02", "12-30"), 2)
        // Values below verified against `_mmddDist` in app.js, run under node.
        XCTAssertEqual(MMDD.distance("12-31", "01-01"), 0)
        XCTAssertEqual(MMDD.distance("12-29", "01-01"), 2)
        XCTAssertEqual(MMDD.distance("12-28", "01-01"), 3)
        XCTAssertEqual(MMDD.distance("12-25", "01-01"), 6)
    }

    /// Half a year apart is the maximum the wrap can produce.
    func testOppositeSidesOfTheYear() {
        XCTAssertEqual(MMDD.distance("06-01", "12-01"), 182)
        XCTAssertLessThanOrEqual(MMDD.distance("03-15", "09-15"), 183)
    }

    func testLeapDayIsUnderstood() {
        XCTAssertEqual(MMDD.distance("02-28", "02-29"), 1)
        XCTAssertEqual(MMDD.distance("02-29", "03-01"), 1)
    }

    /// Malformed keys must fall outside every window rather than crash.
    func testMalformedInputIsExcludedFromWindows() {
        XCTAssertEqual(MMDD.distance("", "01-01"), .max)
        XCTAssertEqual(MMDD.distance("13-01", "01-01"), .max)
        XCTAssertEqual(MMDD.distance("xx-yy", "01-01"), .max)
        XCTAssertFalse(MMDD.distance("nonsense", "08-05") <= 3)
    }

    /// The ±3-day window is inclusive, and spans the wrap.
    func testWindowMembership() {
        let target = "01-01"
        let inWindow = ["12-29", "12-30", "12-31", "01-01", "01-02", "01-03", "01-04"]
            .filter { MMDD.distance(target, $0) <= 3 }
        XCTAssertEqual(inWindow.count, 7)
        XCTAssertFalse(MMDD.distance(target, "01-05") <= 3)
    }
}
