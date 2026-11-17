import Foundation
import XCTest
@testable import SnapboardCore

final class AutomationTests: XCTestCase {
    func testSavedActionAndRulesSurviveSettingsRoundTrip() throws {
        let workspaceID = UUID()
        let itemID = UUID()
        let action = SavedAction(name: "Research setup", steps: [
            AutomationStep(kind: .activateWorkspace, target: workspaceID.uuidString),
            AutomationStep(kind: .openLibraryItem, target: itemID.uuidString),
            AutomationStep(kind: .openURL, target: "https://example.org/notes"),
            AutomationStep(kind: .snapLeft)
        ], workspaceIDs: [workspaceID])
        let rule = AutomationRule(name: "Research shortcut", actionID: action.id,
                                  shortcut: KeyboardShortcut(keyCode: 40,
                                                             modifiers: ShortcutModifiers.command | ShortcutModifiers.option))
        var state = SavedState()
        state.savedActions = [action]
        state.automationRules = [rule]

        let data = try JSONEncoder().encode(state)
        let restored = try JSONDecoder().decode(SavedState.self, from: data)
        XCTAssertEqual(restored.savedActions, [action])
        XCTAssertEqual(restored.automationRules, [rule])
        XCTAssertEqual(restored, state)
    }

    func testWorkspaceAssociationRestrictsAvailability() {
        let research = UUID()
        let personal = UUID()
        let scoped = SavedAction(name: "Research", workspaceIDs: [research])
        XCTAssertTrue(scoped.isAvailable(in: research))
        XCTAssertFalse(scoped.isAvailable(in: personal))
        XCTAssertFalse(scoped.isAvailable(in: nil))
        XCTAssertTrue(SavedAction(name: "Anywhere").isAvailable(in: nil))
    }

    func testConflictDetectionIgnoresDisabledRulesAndFindsReservedKeys() {
        let actionID = UUID()
        let common = KeyboardShortcut(keyCode: 40, modifiers: ShortcutModifiers.command | ShortcutModifiers.option)
        let fixed = KeyboardShortcut(keyCode: 123, modifiers: ShortcutModifiers.control | ShortcutModifiers.option)
        let first = AutomationRule(name: "One", actionID: actionID, shortcut: common)
        let second = AutomationRule(name: "Two", actionID: actionID, shortcut: common)
        let disabled = AutomationRule(name: "Off", actionID: actionID, shortcut: common, enabled: false)
        let reserved = AutomationRule(name: "Fixed", actionID: actionID, shortcut: fixed)
        let conflicts = AutomationValidation.conflictingRuleIDs([first, second, disabled, reserved], reserved: [fixed])
        XCTAssertEqual(conflicts, [first.id, second.id, reserved.id])
        XCTAssertTrue(AutomationValidation.conflictingRuleIDs([first, disabled], reserved: []).isEmpty)
    }

    func testInvalidTargetsAndUnsafeModifiersAreRejected() {
        XCTAssertFalse(AutomationStep(kind: .openLibraryItem, target: "missing").hasValidTarget)
        XCTAssertFalse(AutomationStep(kind: .activateWorkspace, target: "").hasValidTarget)
        XCTAssertFalse(AutomationStep(kind: .openURL, target: "file:///tmp/x").hasValidTarget)
        XCTAssertFalse(AutomationStep(kind: .openURL, target: "javascript:alert(1)").hasValidTarget)
        XCTAssertTrue(AutomationStep(kind: .openURL, target: "https://example.org/").hasValidTarget)
        XCTAssertTrue(AutomationStep(kind: .snapFull).hasValidTarget)

        let invalid = SavedAction(name: " ", steps: [AutomationStep(kind: .openURL, target: "bad")])
        XCTAssertEqual(AutomationValidation.invalidActionIDs([invalid]), [invalid.id])
        let singleModifier = AutomationRule(name: "Bad", actionID: invalid.id,
            shortcut: KeyboardShortcut(keyCode: 40, modifiers: ShortcutModifiers.command))
        XCTAssertEqual(AutomationValidation.invalidRuleIDs([singleModifier]), [singleModifier.id])
    }
}
