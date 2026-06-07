import CoronaCore
import XCTest

final class NoopMoveEventExecutorTests: XCTestCase {
    func testAcceptsMovableItem() async throws {
        let item = makeItem(windowID: 1, namespace: "app", title: "A", sourcePID: 10)
        let anchor = makeItem(windowID: 2, namespace: "control", title: "hidden", sourcePID: 10)

        try await NoopMoveEventExecutor().move(
            item: item,
            to: .leftOfItem(anchor),
            on: nil,
            skipInputPause: true,
            maxAttempts: 1
        )
    }

    func testRejectsNonMovableItem() async {
        var item = makeItem(windowID: 1, namespace: "app", title: "A", sourcePID: 10)
        item.isMovable = false
        let anchor = makeItem(windowID: 2, namespace: "control", title: "hidden", sourcePID: 10)

        do {
            try await NoopMoveEventExecutor().move(
                item: item,
                to: .leftOfItem(anchor),
                on: nil,
                skipInputPause: true,
                maxAttempts: 1
            )
            XCTFail("Expected itemNotMovable")
        } catch {
            XCTAssertEqual(error as? MoveExecutorError, .itemNotMovable("app:A"))
        }
    }
}
