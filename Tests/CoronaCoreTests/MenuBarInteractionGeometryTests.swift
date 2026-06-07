import CoronaCore
import XCTest

final class MenuBarInteractionGeometryTests: XCTestCase {
    func testRightStatusItemZoneTriggers() {
        let geometry = MenuBarInteractionGeometry()
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let items = [
            CGRect(x: 1080, y: 876, width: 24, height: 24),
            CGRect(x: 1120, y: 876, width: 80, height: 24),
            CGRect(x: 1220, y: 876, width: 140, height: 24)
        ]

        XCTAssertTrue(geometry.isPointInStatusItemTriggerZone(
            CGPoint(x: 1160, y: 890),
            itemBounds: items,
            screenFrame: screen
        ))
    }

    func testLeftApplicationMenuDoesNotTrigger() {
        let geometry = MenuBarInteractionGeometry()
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let items = [
            CGRect(x: 1080, y: 876, width: 24, height: 24),
            CGRect(x: 1120, y: 876, width: 80, height: 24)
        ]

        XCTAssertFalse(geometry.isPointInStatusItemTriggerZone(
            CGPoint(x: 120, y: 890),
            itemBounds: items,
            screenFrame: screen
        ))
    }

    func testTopEmptySpaceDoesNotTrigger() {
        let geometry = MenuBarInteractionGeometry()
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let items = [
            CGRect(x: 1080, y: 876, width: 24, height: 24),
            CGRect(x: 1120, y: 876, width: 80, height: 24)
        ]

        XCTAssertFalse(geometry.isPointInStatusItemTriggerZone(
            CGPoint(x: 800, y: 890),
            itemBounds: items,
            screenFrame: screen
        ))
    }
}
