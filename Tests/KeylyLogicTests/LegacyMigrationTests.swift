import Testing
import Foundation
@testable import KeylyLogic

/// Data from the previous version migrates 1:1.
///
/// The fixture lives IN THE REPOSITORY and is frozen: recreating it after a format change
/// would test the new format against itself. Migration breaks silently: the user
/// opens the product and sees an empty list instead of their snippets.
@Suite struct LegacyMigrationTests {

    private func fixture() throws -> [String: Any] {
        // Path relative to the test file: the package has no SwiftPM resources, and adding them for one
        // JSON costs more than referencing it directly.
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // KeylyLogicTests
            .deletingLastPathComponent()   // Tests
            .appendingPathComponent("Fixtures/legacy-defaults-v1.json")
        let data = try Data(contentsOf: url)
        return try JSONSerialization.jsonObject(with: data) as! [String: Any]
    }

    @Test func сниппетыПрошлойВерсииДекодируются() throws {
        let raw = try fixture()
        let data = try JSONSerialization.data(withJSONObject: raw["snippets"]!)
        let snippets = try JSONDecoder().decode([Snippet].self, from: data)

        #expect(snippets.count == 2)
        #expect(snippets[0].name == "Почта")
        #expect(snippets[0].triggers.contains("@@"))
        // The name is optional: the second entry has none, and its absence must not break decoding.
        #expect(snippets[1].name == nil)
        #expect(snippets[1].isEnabled == false)
    }

    /// Fields added AFTER release must have a default: otherwise entries from the previous version
    /// do not decode at all, and the user loses everything at once.
    @Test func новыеПоляПолучаютДефолт() throws {
        let raw = try fixture()
        let data = try JSONSerialization.data(withJSONObject: raw["snippets"]!)
        let snippets = try JSONDecoder().decode([Snippet].self, from: data)
        // `triggerMode` appeared later: old entries do not have it in JSON.
        #expect(snippets[0].triggerMode == .immediate)
    }

    @Test func кастомныеМодулиПрошлойВерсииДекодируются() throws {
        let raw = try fixture()
        let data = try JSONSerialization.data(withJSONObject: raw["customModules"]!)
        let modules = try JSONDecoder().decode([CustomAIModule].self, from: data)
        #expect(modules.count == 1)
        #expect(modules[0].name == "Перевод")
        #expect(modules[0].textSource == .selected)
        #expect(modules[0].output == .insert)
    }

    @Test func целиЛаунчераПрошлойВерсииДекодируются() throws {
        let raw = try fixture()
        let data = try JSONSerialization.data(withJSONObject: raw["appLaunchShortcuts"]!)
        let shortcuts = try JSONDecoder().decode([AppLaunchShortcut].self, from: data)
        #expect(shortcuts.count == 1)
        #expect(shortcuts[0].displayName == "Safari")
        // The old entry has no hotkey: the field is optional, and its absence is not an error.
        #expect(shortcuts[0].keyCombo == nil)
    }
}
