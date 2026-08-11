import XCTest
@testable import WeatherCore

/// Widget tap → panel scroll (§10, follow-up Task E).
final class DeepLinkTests: XCTestCase {

    func testEveryPanelRoundTrips() {
        for panel in PanelID.allCases {
            let url = AppConfig.panelDeepLink(panel)
            XCTAssertEqual(url.scheme, AppConfig.deepLinkScheme)
            XCTAssertEqual(url.host, "panel")
            XCTAssertEqual(AppConfig.panel(from: url), panel, "round trip for \(panel)")
        }
    }

    func testTodayLinkIsNotAPanelLink() {
        XCTAssertNil(AppConfig.panel(from: AppConfig.todayDeepLink))
    }

    func testForeignSchemeIsRejected() {
        let foreign = URL(string: "otherapp://panel/panel-rain")!
        XCTAssertNil(AppConfig.panel(from: foreign))
    }

    func testUnknownPanelPathIsRejected() {
        let bogus = URL(string: "\(AppConfig.deepLinkScheme)://panel/not-a-real-panel")!
        XCTAssertNil(AppConfig.panel(from: bogus))
    }

    func testWrongHostIsRejected() {
        let wrongHost = URL(string: "\(AppConfig.deepLinkScheme)://today/panel-rain")!
        XCTAssertNil(AppConfig.panel(from: wrongHost))
    }
}
