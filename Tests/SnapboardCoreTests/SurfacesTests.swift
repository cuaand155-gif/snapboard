import Foundation
import XCTest
@testable import SnapboardCore

final class SurfacesTests: XCTestCase {
    func testTwoDocksRemainIndependentThroughRoundTrip() throws {
        let firstItem = UUID(), secondItem = UUID()
        let laptop = CustomDock(name: "Course", itemIDs: [firstItem], displayKey: "Built-in 1440x900", placement: .left)
        let external = CustomDock(name: "Meeting", itemIDs: [secondItem], displayKey: "External 1920x1080", placement: .right, autoHide: true)
        let decoded = try JSONDecoder().decode([CustomDock].self, from: JSONEncoder().encode([laptop, external]))
        XCTAssertEqual(decoded, [laptop, external])
        XCTAssertEqual(decoded[0].itemIDs, [firstItem])
        XCTAssertEqual(decoded[1].itemIDs, [secondItem])
    }

    func testMissingDisplayFallsBackWithoutChangingSavedTarget() {
        let dock = CustomDock(name: "Work", displayKey: "External 1920x1080")
        XCTAssertEqual(dock.renderedDisplayKey(available: ["Built-in 1440x900"]), "Built-in 1440x900")
        XCTAssertEqual(dock.displayKey, "External 1920x1080")
        XCTAssertEqual(dock.renderedDisplayKey(available: ["Built-in 1440x900", "External 1920x1080"]), "External 1920x1080")
        XCTAssertNil(dock.renderedDisplayKey(available: []))
    }

    func testMenuGroupPreservesOrderAndSharedReferences() throws {
        let ids = [UUID(), UUID(), UUID()]
        let group = MenuGroup(name: "Course", itemIDs: ids)
        let decoded = try JSONDecoder().decode(MenuGroup.self, from: JSONEncoder().encode(group))
        XCTAssertEqual(decoded.itemIDs, ids)
        XCTAssertEqual(decoded, group)
    }

    func testWorkspaceScopesAndLegacyDecoding() throws {
        let workspace = UUID()
        let another = UUID()
        let dock = CustomDock(name: "Course", workspaceIDs: [workspace])
        let group = MenuGroup(name: "Course", workspaceIDs: [workspace])
        XCTAssertTrue(dock.applies(to: workspace))
        XCTAssertFalse(dock.applies(to: another))
        XCTAssertFalse(group.applies(to: nil))
        XCTAssertTrue(MenuGroup(name: "Global").applies(to: nil))

        let oldDock = try withoutWorkspaceIDs(dock)
        let oldGroup = try withoutWorkspaceIDs(group)
        XCTAssertEqual(try JSONDecoder().decode(CustomDock.self, from: oldDock).workspaceIDs, [])
        XCTAssertEqual(try JSONDecoder().decode(MenuGroup.self, from: oldGroup).workspaceIDs, [])
    }

    private func withoutWorkspaceIDs<T: Encodable>(_ value: T) throws -> Data {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
        object.removeValue(forKey: "workspaceIDs")
        return try JSONSerialization.data(withJSONObject: object)
    }
}
