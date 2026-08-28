import CoronaCore
import XCTest

final class MenuBarSectionSerializationTests: XCTestCase {
    private struct SettingsPayload: Codable, Equatable {
        var newItemsSection: MenuBarSection
    }

    func testLegacyRawValuePayloadsDecodeAndReencodeByteIdentically() throws {
        // Raw values written by the legacy settings section enum.
        let legacyRawValues = ["visible", "hidden", "alwaysHidden"]

        for rawValue in legacyRawValues {
            let json = Data("{\"newItemsSection\":\"\(rawValue)\"}".utf8)

            let payload = try JSONDecoder().decode(SettingsPayload.self, from: json)

            XCTAssertEqual(payload.newItemsSection.rawValue, rawValue)
            XCTAssertEqual(try JSONEncoder().encode(payload), json)
        }
    }
}
