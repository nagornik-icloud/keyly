import Foundation

/// Settings export file — a PURE model with no access to stores.
///
/// A separate type because a mistake here is irreversible: import REPLACES everything. "What
/// goes into the file" and "what import accepts" must be checked by tests, not by moving
/// settings on a real machine.
///
/// **There are no API keys here, and there must never be.** Not an oversight or "not done
/// yet": people put this file in the cloud and email it to themselves, and a key is a payment
/// instrument. The absence of the field is covered by a test, because adding it will one day
/// seem convenient.
struct SettingsBundle: Codable, Equatable {

    /// File SCHEMA version. Bumped on any incompatible change to the set of fields.
    static let currentSchema = 1

    var schemaVersion: Int
    /// Version of the app that made the file. Diagnostics only — it doesn't affect accept vs.
    /// reject: an older app may open a newer file if the schema is the same.
    var appVersion: String
    var exportedAt: Date

    var snippets: [Snippet]
    var customModules: [CustomAIModule]
    var appLaunchShortcuts: [AppLaunchShortcut]
    /// Flat settings from `UserDefaults`: module hotkeys, modes, toggles.
    /// A dictionary, not a typed struct: the set of keys changes all the time, and a rigid
    /// schema would force a `schemaVersion` bump for every new setting.
    var defaults: [String: String]

    enum ImportRefusal: Equatable {
        /// Schema is newer than this app knows.
        case schemaTooNew(fileSchema: Int, supported: Int)
        /// Unknown schema (e.g. 0 or negative) — not our file, or corrupted.
        case schemaUnknown(fileSchema: Int)
    }

    /// Whether the file can be accepted. `nil` means yes.
    ///
    /// A NEWER schema is always rejected: fields we don't understand would be silently lost,
    /// and import is irreversible by definition — there would be nowhere to recover them from.
    static func refusal(forSchema schema: Int) -> ImportRefusal? {
        guard schema >= 1 else { return .schemaUnknown(fileSchema: schema) }
        guard schema <= currentSchema else {
            return .schemaTooNew(fileSchema: schema, supported: currentSchema)
        }
        return nil
    }

    /// `UserDefaults` keys that go into the file. The list is explicit: a blind dump would grab
    /// internal state and — most importantly — API key values, should they ever end up there.
    static let exportedDefaultKeys: [String] = [
        SettingsKeys.layoutHotKey,
        SettingsKeys.errorFixHotKey,
        SettingsKeys.voiceHotKey,
        SettingsKeys.undoHotKey,
        SettingsKeys.snippetPaletteHotKey,
        SettingsKeys.cheatsheetHotKey,
        SettingsKeys.errorFixLevel,
        SettingsKeys.textPolishLevel,
        SettingsKeys.voiceRecognitionMode,
        SettingsKeys.voiceLanguage,
        SettingsKeys.voiceIndicatorPlacement,
        SettingsKeys.voiceIndicatorShowTimer,
        SettingsKeys.launchAtLogin,
        SettingsKeys.showMenuBarIcon,
        SettingsKeys.showDockIcon,
        SettingsKeys.showOnboarding,
        SettingsKeys.layoutEnabled,
        SettingsKeys.errorFixEnabled,
        SettingsKeys.voiceEnabled,
        SettingsKeys.appLauncherEnabled,
        SettingsKeys.voiceEngine,
        SettingsKeys.voiceTranscriptionModel,
        SettingsKeys.voiceFormatParagraphs,
        SettingsKeys.voiceRealtimeMode,
        SettingsKeys.voicePolishCorrections,
        SettingsKeys.voiceKeepInClipboard,
        interfaceLanguageKey,
        layoutPairKey,
        // voiceInputDeviceUID is deliberately absent: a microphone id only exists on this Mac.
    ]

    static let interfaceLanguageKey = "interfaceLanguage"
    static let layoutPairKey = "layoutSwitchPair"

    // MARK: - Typed values

    /// How a setting is stored in UserDefaults. The file keeps everything as text, so the
    /// type has to be known per key to give the app back what it reads.
    enum ValueKind { case bool, data, string }

    static func kind(forKey key: String) -> ValueKind? {
        switch key {
        case SettingsKeys.layoutHotKey, SettingsKeys.errorFixHotKey, SettingsKeys.voiceHotKey,
             SettingsKeys.undoHotKey, SettingsKeys.snippetPaletteHotKey, SettingsKeys.cheatsheetHotKey,
             layoutPairKey:
            return .data
        case SettingsKeys.voiceIndicatorShowTimer, SettingsKeys.launchAtLogin, SettingsKeys.showMenuBarIcon,
             SettingsKeys.showDockIcon, SettingsKeys.showOnboarding, SettingsKeys.layoutEnabled,
             SettingsKeys.errorFixEnabled, SettingsKeys.voiceEnabled, SettingsKeys.appLauncherEnabled,
             SettingsKeys.voiceFormatParagraphs, SettingsKeys.voiceRealtimeMode, SettingsKeys.voicePolishCorrections,
             SettingsKeys.voiceKeepInClipboard:
            return .bool
        case SettingsKeys.errorFixLevel, SettingsKeys.textPolishLevel, SettingsKeys.voiceRecognitionMode,
             SettingsKeys.voiceLanguage, SettingsKeys.voiceIndicatorPlacement, SettingsKeys.voiceEngine,
             SettingsKeys.voiceTranscriptionModel, interfaceLanguageKey:
            return .string
        default:
            return nil
        }
    }

    static func encodeValue(_ value: Any, forKey key: String) -> String? {
        switch kind(forKey: key) {
        case .data: return (value as? Data).flatMap { String(data: $0, encoding: .utf8) }
        case .bool: return (value as? Bool).map { $0 ? "true" : "false" }
        case .string: return value as? String
        case nil: return nil
        }
    }

    /// Accepts the old export format too: switches written as "1"/"0".
    static func decodeValue(_ text: String, forKey key: String) -> Any? {
        switch kind(forKey: key) {
        case .data: return Data(text.utf8)
        case .bool:
            switch text {
            case "true", "1": return true
            case "false", "0": return false
            default: return nil
            }
        case .string: return text
        case nil: return nil
        }
    }
}
