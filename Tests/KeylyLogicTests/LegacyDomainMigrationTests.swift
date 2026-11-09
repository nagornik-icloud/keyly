import Testing
import Foundation
@testable import KeylyLogic

/// Renaming the bundle id moves settings to a new UserDefaults domain. Everything the user
/// configured under the old id must arrive intact — checked against a committed snapshot of
/// the previous version's domain (41 keys, fake values), not against data this build wrote.
@Suite("Legacy domain migration")
struct LegacyDomainMigrationTests {

    private func fixture() throws -> [String: Any] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/legacy-domain-v3.plist")
        let data = try Data(contentsOf: url)
        return try PropertyListSerialization.propertyList(from: data, format: nil) as! [String: Any]
    }

    @Test("Fixture has the full previous-version domain")
    func fixtureIsComplete() throws {
        #expect(try fixture().count == 41)
    }

    @Test("Every user setting is copied with its value and type")
    func copiesUserSettings() throws {
        let legacy = try fixture()
        let plan = LegacyDomainMigration.entriesToCopy(from: legacy)
        for key in ["snippets", "customAIModules", "appLaunchShortcuts", "customHotKey",
                    "customHotKeyUndo", "launchAtLogin", "interfaceLanguage", "usageStats",
                    "voiceToText.engine", "apiKeys.selected.errorFix", "wizardCompleted",
                    "app.starterContentSeeded", "hotkeyDefaults.seeded.v2"] {
            let original = try #require(legacy[key] as? NSObject, "missing \(key)")
            let copied = try #require(plan[key] as? NSObject, "not copied: \(key)")
            #expect(copied.isEqual(original), "changed: \(key)")
        }
    }

    @Test("System window/panel state is not copied")
    func skipsSystemKeys() throws {
        let plan = LegacyDomainMigration.entriesToCopy(from: try fixture())
        #expect(plan.keys.allSatisfy { !$0.hasPrefix("NS") && !$0.hasPrefix("Apple") })
    }

    @Test("API keys never land in the new domain — they go to Keychain")
    func skipsSecrets() throws {
        let plan = LegacyDomainMigration.entriesToCopy(from: try fixture())
        #expect(plan["apiKeys.storage"] == nil)
    }

    @Test("Copied = everything except system keys and secrets")
    func copiesAllTheRest() throws {
        let legacy = try fixture()
        let plan = LegacyDomainMigration.entriesToCopy(from: legacy)
        #expect(plan.count == 41 - 3 - 1)
    }

    @Test("Running under the legacy id itself does nothing")
    func noSelfMigration() {
        #expect(!LegacyDomainMigration.shouldRun(currentBundleID: AppIdentity.legacyBundleID, alreadyDone: false))
        #expect(!LegacyDomainMigration.shouldRun(currentBundleID: AppIdentity.bundleID, alreadyDone: true))
        #expect(LegacyDomainMigration.shouldRun(currentBundleID: AppIdentity.bundleID, alreadyDone: false))
    }
}
