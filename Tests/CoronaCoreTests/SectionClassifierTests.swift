import CoronaCore
import CoreGraphics
import XCTest

final class SectionClassifierTests: XCTestCase {
    func testClassifiesVisibleRightOfHiddenControl() {
        let boundary = SectionBoundary(hiddenControlBounds: CGRect(x: 700, y: 0, width: 10, height: 22))

        let section = SectionClassifier().classify(
            itemBounds: CGRect(x: 720, y: 0, width: 20, height: 22),
            boundary: boundary
        )

        XCTAssertEqual(section, .visible)
    }

    func testClassifiesHiddenLeftOfHiddenControl() {
        let boundary = SectionBoundary(hiddenControlBounds: CGRect(x: 700, y: 0, width: 10, height: 22))

        let section = SectionClassifier().classify(
            itemBounds: CGRect(x: 650, y: 0, width: 20, height: 22),
            boundary: boundary
        )

        XCTAssertEqual(section, .hidden)
    }

    func testClassifiesAlwaysHiddenLeftOfAlwaysHiddenControl() {
        let boundary = SectionBoundary(
            hiddenControlBounds: CGRect(x: 700, y: 0, width: 10, height: 22),
            alwaysHiddenControlBounds: CGRect(x: 500, y: 0, width: 10, height: 22)
        )

        let section = SectionClassifier().classify(
            itemBounds: CGRect(x: 450, y: 0, width: 20, height: 22),
            boundary: boundary
        )

        XCTAssertEqual(section, .alwaysHidden)
    }

    func testClassifiesWhenAlwaysHiddenControlIsRightOfHiddenControl() {
        let boundary = SectionBoundary(
            hiddenControlBounds: CGRect(x: 500, y: 0, width: 10, height: 22),
            alwaysHiddenControlBounds: CGRect(x: 650, y: 0, width: 10, height: 22)
        )

        XCTAssertEqual(
            SectionClassifier().classify(
                itemBounds: CGRect(x: 430, y: 0, width: 40, height: 22),
                boundary: boundary
            ),
            .alwaysHidden
        )
        XCTAssertEqual(
            SectionClassifier().classify(
                itemBounds: CGRect(x: 560, y: 0, width: 40, height: 22),
                boundary: boundary
            ),
            .hidden
        )
        XCTAssertEqual(
            SectionClassifier().classify(
                itemBounds: CGRect(x: 690, y: 0, width: 40, height: 22),
                boundary: boundary
            ),
            .visible
        )
    }

    func testBuildsWindowSectionMap() {
        let items = [
            makeItem(windowID: 1, namespace: "a", title: "A", sourcePID: 10),
            makeItem(windowID: 2, namespace: "b", title: "B", sourcePID: 20),
            makeItem(windowID: 3, namespace: "c", title: "C", sourcePID: 30)
        ]
        let adjusted = [
            withBounds(items[0], CGRect(x: 720, y: 0, width: 20, height: 22)),
            withBounds(items[1], CGRect(x: 650, y: 0, width: 20, height: 22)),
            withBounds(items[2], CGRect(x: 450, y: 0, width: 20, height: 22))
        ]
        let boundary = SectionBoundary(
            hiddenControlBounds: CGRect(x: 700, y: 0, width: 10, height: 22),
            alwaysHiddenControlBounds: CGRect(x: 500, y: 0, width: 10, height: 22)
        )

        let sections = SectionClassifier().classify(items: adjusted, boundary: boundary)

        XCTAssertEqual(sections[1], .visible)
        XCTAssertEqual(sections[2], .hidden)
        XCTAssertEqual(sections[3], .alwaysHidden)
    }

    func testClassifyItemsToleratesDuplicateWindowIDs() {
        let first = withBounds(
            makeItem(windowID: 7, namespace: "a", title: "A", sourcePID: 10),
            CGRect(x: 720, y: 0, width: 20, height: 22)
        )
        let second = withBounds(
            makeItem(windowID: 7, namespace: "b", title: "B", sourcePID: 20),
            CGRect(x: 650, y: 0, width: 20, height: 22)
        )
        let boundary = SectionBoundary(hiddenControlBounds: CGRect(x: 700, y: 0, width: 10, height: 22))
        let logger = RecordingDiagnosticLogger()

        let sections = SectionClassifier(logger: logger).classify(items: [first, second], boundary: boundary)

        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections[7], .visible)
        XCTAssertEqual(logger.warnings.count, 1)
    }

    private func withBounds(_ item: MenuBarItem, _ bounds: CGRect) -> MenuBarItem {
        var copy = item
        copy.bounds = bounds
        return copy
    }
}
