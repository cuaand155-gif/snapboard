import Foundation
import XCTest
@testable import SnapboardCore

final class DockPresetTests: XCTestCase {
    private func encoded(_ value: Any) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: value, format: .binary, options: 0)
    }

    private func snapshot(_ entries: [DockPreferenceKey: Any]) throws -> DockSnapshot {
        var values: [String: Data] = [:]
        for (key, value) in entries { values[key.rawValue] = try encoded(value) }
        return try DockSnapshot(values: values,
                                absentKeys: DockPreferenceKey.allCases.map(\.rawValue)
                                    .filter { values[$0] == nil })
    }

    func testPreviewListsOnlyChangedKeys() throws {
        let current = try snapshot([
            .apps: [["tile-data": ["file-label": "Mail"]]],
            .folders: [], .orientation: "bottom", .autohide: false
        ])
        let proposed = try snapshot([
            .apps: [["tile-data": ["file-label": "Notes"]]],
            .folders: [], .orientation: "bottom", .autohide: true
        ])

        XCTAssertEqual(proposed.changes(from: current), [.apps, .autohide])
        XCTAssertEqual(current.displayValue(for: .apps), "Mail")
        XCTAssertEqual(proposed.displayValue(for: .apps), "Notes")
        XCTAssertEqual(proposed.displayValue(for: .autohide), "On")
    }

    func testMissingPreferenceIsAChangeAndSurvivesSerialization() throws {
        let previous = try snapshot([.folders: []])
        let preset = DockPreset(name: "Work", snapshot: try snapshot([.folders: [], .tileSize: 48]))
        let decoded = try JSONDecoder().decode(DockPreset.self, from: JSONEncoder().encode(preset))

        XCTAssertEqual(decoded, preset)
        XCTAssertEqual(decoded.snapshot.changes(from: previous), [.tileSize])
        XCTAssertEqual(previous.displayValue(for: .tileSize), "System default")
    }

    func testRejectsIncompleteAndWrongTypeSnapshots() throws {
        XCTAssertThrowsError(try DockSnapshot(values: [:], absentKeys: []))
        XCTAssertThrowsError(try snapshot([.apps: "not tiles"]))
        XCTAssertThrowsError(try snapshot([.orientation: 1]))
    }

    func testEquivalentPropertyListsIgnoreEncodingFormat() throws {
        let raw: [[String: Any]] = [["tile-data": ["file-label": "Calendar"]]]
        let binary = try encoded(raw)
        let xml = try PropertyListSerialization.data(fromPropertyList: raw, format: .xml, options: 0)
        let absent = DockPreferenceKey.allCases.map(\.rawValue).filter { $0 != DockPreferenceKey.apps.rawValue }
        let lhs = try DockSnapshot(values: [DockPreferenceKey.apps.rawValue: binary], absentKeys: absent)
        let rhs = try DockSnapshot(values: [DockPreferenceKey.apps.rawValue: xml], absentKeys: absent)

        XCTAssertTrue(lhs.isEquivalent(to: rhs))
        XCTAssertTrue(lhs.changes(from: rhs).isEmpty)
    }
}
