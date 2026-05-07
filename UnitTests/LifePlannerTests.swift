import XCTest
@testable import LifePlanner

final class LifePlannerTests: XCTestCase {
    func test_appStateDefaults() {
        let state = AppState()
        XCTAssertEqual(state.routing.selectedTab, .tasks)
        XCTAssertEqual(state.permissions.notifications, .unknown)
    }
}
