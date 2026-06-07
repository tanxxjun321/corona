import CoronaCore
import XCTest

final class LayoutDraftTests: XCTestCase {
    func testMoveTransfersUIDBetweenSections() {
        var draft = LayoutDraft(order: SectionOrder(visible: ["a", "b"], hidden: ["c"]))

        draft.move("b", to: .hidden)

        XCTAssertEqual(draft.order.visible, ["a"])
        XCTAssertEqual(draft.order.hidden, ["c", "b"])
    }

    func testMoveCanInsertAtTargetIndex() {
        var draft = LayoutDraft(order: SectionOrder(visible: ["a", "b"], hidden: ["c", "d"]))

        draft.move("b", to: .hidden, at: 1)

        XCTAssertEqual(draft.order.visible, ["a"])
        XCTAssertEqual(draft.order.hidden, ["c", "b", "d"])
    }

    func testMoveWithinSameSectionAdjustsIndexAfterRemoval() {
        var draft = LayoutDraft(order: SectionOrder(visible: ["a", "b", "c", "d"]))

        draft.move("b", to: .visible, at: 3)

        XCTAssertEqual(draft.order.visible, ["a", "c", "b", "d"])
    }

    func testMoveUpAndDownReorderWithinSection() {
        var draft = LayoutDraft(order: SectionOrder(hidden: ["a", "b", "c"]))

        draft.moveUp("c", in: .hidden)
        XCTAssertEqual(draft.order.hidden, ["a", "c", "b"])

        draft.moveDown("a", in: .hidden)
        XCTAssertEqual(draft.order.hidden, ["c", "a", "b"])
    }

    func testBoundaryMovesAreNoops() {
        var draft = LayoutDraft(order: SectionOrder(hidden: ["a", "b"]))

        draft.moveUp("a", in: .hidden)
        draft.moveDown("b", in: .hidden)

        XCTAssertEqual(draft.order.hidden, ["a", "b"])
    }

    func testResetPutsAllItemsInVisible() {
        var draft = LayoutDraft(order: SectionOrder(visible: ["a"], hidden: ["b"], alwaysHidden: ["c"]))

        draft.reset(visibleUIDs: ["x", "y"])

        XCTAssertEqual(draft.order, SectionOrder(visible: ["x", "y"], hidden: [], alwaysHidden: []))
    }
}
