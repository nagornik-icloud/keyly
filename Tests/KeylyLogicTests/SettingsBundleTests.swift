import Foundation
import Testing
@testable import KeylyLogic

/// Settings export file.
///
/// Import REPLACES everything and is irreversible, so the rules are checked by tests rather than by moving
/// settings on a real machine.
struct SettingsBundleTests {

    private func bundle(schema: Int = SettingsBundle.currentSchema) -> SettingsBundle {
        SettingsBundle(schemaVersion: schema, appVersion: "2.0", exportedAt: Date(timeIntervalSince1970: 0),
                       snippets: [], customModules: [], appLaunchShortcuts: [], defaults: [:])
    }

    @Test("Файл своей схемы принимается")
    func currentSchemaAccepted() {
        #expect(SettingsBundle.refusal(forSchema: SettingsBundle.currentSchema) == nil)
    }

    @Test("Файл более НОВОЙ схемы отклоняется — иначе непонятые поля молча потеряются")
    func newerSchemaRefused() {
        let refusal = SettingsBundle.refusal(forSchema: SettingsBundle.currentSchema + 1)
        #expect(refusal == .schemaTooNew(fileSchema: SettingsBundle.currentSchema + 1,
                                         supported: SettingsBundle.currentSchema))
    }

    @Test("Файл без внятной схемы отклоняется")
    func brokenSchemaRefused() {
        #expect(SettingsBundle.refusal(forSchema: 0) == .schemaUnknown(fileSchema: 0))
        #expect(SettingsBundle.refusal(forSchema: -3) == .schemaUnknown(fileSchema: -3))
    }

    /// The MAIN test of this file: API keys are not in the export and must never be.
    /// The file gets put in the cloud and sent by email, and a key is a payment instrument.
    @Test("В экспорте нет ни одного поля, похожего на ключ API")
    func neverExportsAPIKeys() throws {
        let data = try JSONEncoder().encode(bundle())
        let json = String(data: data, encoding: .utf8) ?? ""
        for forbidden in ["apiKey", "api_key", "keys", "sk-", "AIza", "value"] {
            #expect(!json.contains(forbidden), "в экспорте встретилось «\(forbidden)»")
        }
    }

    @Test("Список экспортируемых настроек не содержит ключей от хранилища ключей")
    func exportedKeysAreSafe() {
        for key in SettingsBundle.exportedDefaultKeys {
            #expect(!key.lowercased().contains("apikey"), "\(key) — похоже на хранилище ключей")
            #expect(!key.lowercased().contains("apiselection"), "\(key) — привязка модуля к ключу")
        }
    }

    @Test("Список экспортируемых настроек не пуст и без дублей")
    func exportedKeysAreSane() {
        let keys = SettingsBundle.exportedDefaultKeys
        #expect(!keys.isEmpty)
        #expect(Set(keys).count == keys.count, "в списке есть дубли")
    }

    @Test("Файл переживает круг кодирования")
    func roundTrips() throws {
        let original = bundle()
        let decoded = try JSONDecoder().decode(SettingsBundle.self,
                                               from: JSONEncoder().encode(original))
        #expect(decoded == original)
    }
}

/// The export file stores every setting as text; the import must give each one back with
/// the type the app reads. Before this, a switch came back as the text "1" and read as
/// "not set", so importing reset every switch to its default.
@Suite("Settings bundle: typed values")
struct SettingsBundleValueTests {

    @Test("Switches round-trip as switches, including the old '1'/'0' files")
    func bools() {
        let key = SettingsKeys.showDockIcon
        #expect(SettingsBundle.encodeValue(false as NSNumber, forKey: key) == "false")
        #expect(SettingsBundle.decodeValue("false", forKey: key) as? Bool == false)
        #expect(SettingsBundle.decodeValue("true", forKey: key) as? Bool == true)
        #expect(SettingsBundle.decodeValue("0", forKey: key) as? Bool == false)
        #expect(SettingsBundle.decodeValue("1", forKey: key) as? Bool == true)
    }

    @Test("Hotkeys and the layout pair come back as Data")
    func data() {
        let json = #"{"keyCode":50}"#
        for key in [SettingsKeys.layoutHotKey, SettingsBundle.layoutPairKey] {
            let encoded = SettingsBundle.encodeValue(Data(json.utf8), forKey: key)
            #expect(encoded == json)
            #expect(SettingsBundle.decodeValue(json, forKey: key) as? Data == Data(json.utf8))
        }
    }

    @Test("Text settings stay text")
    func strings() {
        let key = SettingsKeys.voiceEngine
        #expect(SettingsBundle.encodeValue("local", forKey: key) == "local")
        #expect(SettingsBundle.decodeValue("local", forKey: key) as? String == "local")
    }

    @Test("Every exported key has a known type")
    func everyKeyTyped() {
        for key in SettingsBundle.exportedDefaultKeys {
            #expect(SettingsBundle.kind(forKey: key) != nil, "untyped: \(key)")
        }
    }

    @Test("Voice, language and layout pair are exported; machine-specific mic is not")
    func coverage() {
        let keys = Set(SettingsBundle.exportedDefaultKeys)
        for key in [SettingsKeys.voiceEngine, SettingsKeys.voiceTranscriptionModel,
                    SettingsKeys.voiceFormatParagraphs, SettingsKeys.voiceRealtimeMode,
                    SettingsKeys.voicePolishCorrections, SettingsBundle.interfaceLanguageKey,
                    SettingsBundle.layoutPairKey] {
            #expect(keys.contains(key), "not exported: \(key)")
        }
        #expect(!keys.contains(SettingsKeys.voiceInputDeviceUID))
    }
}
