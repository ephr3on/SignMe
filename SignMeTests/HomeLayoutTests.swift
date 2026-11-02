import XCTest
@testable import SignMe

final class HomeLayoutTests: XCTestCase {
    func testDefaultShowsEverything() {
        XCTAssertEqual(HomeLayout.default.visible, HomeSection.allCases)
    }

    func testRoundTrip() {
        let layout = HomeLayout(order: [.recent, .timer, .calendar, .week, .target], hidden: [.week])
        let parsed = HomeLayout(orderRaw: layout.orderRaw, hiddenRaw: layout.hiddenRaw)
        XCTAssertEqual(parsed, layout)
        XCTAssertEqual(parsed.visible, [.recent, .timer, .calendar, .target])
    }

    func testUnknownAndMissingCards() {
        let parsed = HomeLayout(orderRaw: "calendar,bogus,timer,calendar", hiddenRaw: "bogus,timer")
        XCTAssertEqual(Array(parsed.order.prefix(2)), [.calendar, .timer])
        XCTAssertEqual(Set(parsed.order), Set(HomeSection.allCases))
        XCTAssertEqual(parsed.order.count, HomeSection.allCases.count)
        XCTAssertEqual(parsed.hidden, [.timer])
    }
}
