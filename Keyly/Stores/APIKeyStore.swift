import Foundation
import SwiftUI
import Combine

enum APIProvider: String, Codable, CaseIterable {
    case openai
    case gemini
    
    var title: String {
        switch self {
        case .openai: return "OpenAI"
        case .gemini: return "Gemini"
        }
    }
    
    /// Default model for a NEW key.
    ///
    /// It used to be `gpt-4o-mini`. In real use, only one of five typo fixes was correct — the model
    /// either found no errors at all or fixed one of two. Switching the model manually gave a
    /// correct result, so the prompt wasn't the problem. The default must give a working product
    /// out of the box, not the impression that "typo fixing doesn't work"; the price difference on
    /// texts of this size is fractions of a cent per call.
    var defaultModel: String {
        switch self {
        case .openai:
            return "gpt-4.1-mini"
        case .gemini:
            // A `-latest` alias, not a pinned version: a pinned model once returned 404
            // "gemini-2.5-flash is no longer available to new users" — the default model failed
            // on a fresh key. The alias points to whatever the provider currently serves.
            return "gemini-flash-latest"
        }
    }
}

struct APIKeyEntry: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var value: String
    var provider: APIProvider
    var isBuiltin: Bool
    var model: String?
}

struct APIKeySelection: Codable, Equatable {
    var provider: APIProvider
    var keyId: UUID
    var model: String?
}

enum APIKeyContext: Codable, Equatable {
    case errorFix
    case voiceToText
    case customModule(UUID)
    
    private enum CodingKeys: String, CodingKey { case type, id }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .errorFix:
            try container.encode("errorFix", forKey: .type)
        case .voiceToText:
            try container.encode("voiceToText", forKey: .type)
        case .customModule(let id):
            try container.encode("customModule", forKey: .type)
            try container.encode(id, forKey: .id)
        }
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "errorFix": self = .errorFix
        case "voiceToText": self = .voiceToText
        case "customModule":
            let id = try container.decode(UUID.self, forKey: .id)
            self = .customModule(id)
        default:
            self = .errorFix
        }
    }
}

enum APIKeyError: Error {
    case missingKey
}

@MainActor
final class APIKeyStore: ObservableObject {
    
    static let shared = APIKeyStore()
    
    @Published private(set) var keys: [APIKeyEntry] = []
    @Published var selectedErrorFix: APIKeySelection
    @Published var selectedVoiceToText: APIKeySelection
    @Published private var customSelections: [UUID: APIKeySelection]

    /// Sentinel for "no key selected". BYOK only: there is no shared built-in key anymore;
    /// until the user adds their own, AI modules show "no key".
    static let noKeyId = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!

    private let defaults = UserDefaults.standard
    private let keyVault = APIKeyVault()
    private let selectedErrorFixStorage = "apiKeys.selected.errorFix"
    private let selectedVoiceStorage = "apiKeys.selected.voiceToText"
    private let customSelectionsStorage = "apiKeys.selected.customModules"

    private static func emptySelection() -> APIKeySelection {
        APIKeySelection(provider: .openai, keyId: noKeyId, model: APIProvider.openai.defaultModel)
    }

    private init() {
        let defaultSelection = APIKeyStore.emptySelection()
        let loadedKeys = keyVault.load()
        let loadedErrorSel = APIKeyStore.loadSelection(defaults: defaults, key: selectedErrorFixStorage) ?? defaultSelection
        let loadedVoiceSel = APIKeyStore.loadSelection(defaults: defaults, key: selectedVoiceStorage) ?? defaultSelection
        let loadedCustomSelections = APIKeyStore.loadCustomSelections(defaults: defaults, key: customSelectionsStorage)

        self.keys = loadedKeys
        self.selectedErrorFix = loadedErrorSel
        self.selectedVoiceToText = loadedVoiceSel
        self.customSelections = loadedCustomSelections

        ensureSelectionsValid()
    }

    var hasAnyKey: Bool { !keys.isEmpty }

    func availableKeys(for provider: APIProvider) -> [APIKeyEntry] {
        keys.filter { $0.provider == provider }
    }
    
    func addKey(provider: APIProvider, name: String, value: String, model: String?) -> APIKeyEntry {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanModel = model?.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalModel = (cleanModel?.isEmpty == false) ? cleanModel : nil
        let entry = APIKeyEntry(
            id: UUID(),
            name: cleanName.isEmpty ? "\(provider.title) Key" : cleanName,
            value: cleanValue,
            provider: provider,
            isBuiltin: false,
            model: finalModel
        )
        keys = keys + [entry]
        saveKeys()
        // BYOK UX: if the context has no valid key yet, select the new one right away
        // so AI modules work without an extra "choose a key" step.
        let newSelection = APIKeySelection(provider: provider, keyId: entry.id, model: entry.model ?? provider.defaultModel)
        if self.entry(for: selectedErrorFix) == nil {
            selectedErrorFix = newSelection
            saveSelection(newSelection, key: selectedErrorFixStorage)
        }
        if self.entry(for: selectedVoiceToText) == nil {
            selectedVoiceToText = newSelection
            saveSelection(newSelection, key: selectedVoiceStorage)
        }
        return entry
    }
    
    func updateKey(id: UUID, name: String, value: String, model: String? = nil) {
        guard let idx = keys.firstIndex(where: { $0.id == id }) else { return }
        var updated = keys
        updated[idx].name = name
        updated[idx].value = value
        if let model = model {
            let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
            updated[idx].model = trimmed.isEmpty ? nil : trimmed
        }
        keys = updated
        saveKeys()
    }
    
    func deleteKey(id: UUID) {
        if let idx = keys.firstIndex(where: { $0.id == id }) {
            var updated = keys
            updated.remove(at: idx)
            keys = updated
            saveKeys()
        }
        // Reset the selection if it pointed to the deleted key.
        if selectedErrorFix.keyId == id {
            selectedErrorFix = APIKeyStore.emptySelection()
            saveSelection(selectedErrorFix, key: selectedErrorFixStorage)
        }
        if selectedVoiceToText.keyId == id {
            selectedVoiceToText = APIKeyStore.emptySelection()
            saveSelection(selectedVoiceToText, key: selectedVoiceStorage)
        }
        if customSelections.values.contains(where: { $0.keyId == id }) {
            customSelections = customSelections.mapValues { sel in
                if sel.keyId == id {
                    return APIKeyStore.emptySelection()
                }
                return sel
            }
            saveCustomSelections()
        }
    }
    
    func select(context: APIKeyContext, selection: APIKeySelection) {
        let normalized = normalize(selection: selection)
        switch context {
        case .errorFix:
            selectedErrorFix = normalized
            saveSelection(normalized, key: selectedErrorFixStorage)
        case .voiceToText:
            selectedVoiceToText = normalized
            saveSelection(normalized, key: selectedVoiceStorage)
        case .customModule(let id):
            customSelections[id] = normalized
            saveCustomSelections()
        }
    }
    
    func currentSelection(for context: APIKeyContext) -> APIKeySelection {
        switch context {
        case .errorFix: return normalize(selection: selectedErrorFix)
        case .voiceToText: return normalize(selection: selectedVoiceToText)
        case .customModule(let id):
            // A new module gets the DEFAULT key — the first one added. It used to start with an
            // empty selection, and even with the product already set up the user had to assign
            // a key to every new module by hand.
            let sel = customSelections[id] ?? defaultSelection()
            return normalize(selection: sel)
        }
    }
    
    /// The default key is the FIRST one added. Not "any": the order of adding reflects intent,
    /// and the user expects a new module to take the key they set up first, not a random one
    /// from the list.
    func defaultSelection() -> APIKeySelection {
        guard let first = keys.first else { return APIKeyStore.emptySelection() }
        return APIKeySelection(provider: first.provider,
                               keyId: first.id,
                               model: first.model ?? first.provider.defaultModel)
    }

    func model(for context: APIKeyContext) -> String {
        let selection = currentSelection(for: context)
        if let model = selection.model, !model.isEmpty {
            return model
        }
        if let entry = entry(for: selection) {
            return entry.model ?? entry.provider.defaultModel
        }
        return selection.provider.defaultModel
    }
    
    func updateModel(for context: APIKeyContext, model: String) {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        switch context {
        case .errorFix:
            var sel = selectedErrorFix
            sel.model = trimmed
            selectedErrorFix = sel
            saveSelection(sel, key: selectedErrorFixStorage)
        case .voiceToText:
            var sel = selectedVoiceToText
            sel.model = trimmed
            selectedVoiceToText = sel
            saveSelection(sel, key: selectedVoiceStorage)
        case .customModule(let id):
            var sel = customSelections[id] ?? APIKeyStore.emptySelection()
            sel.model = trimmed
            customSelections[id] = sel
            saveCustomSelections()
        }
    }
    
    func entry(for selection: APIKeySelection) -> APIKeyEntry? {
        keys.first(where: { $0.id == selection.keyId && $0.provider == selection.provider })
    }


    /// Open settings and highlight that a key is needed.
    func presentMissingKeyAlert() {
        let alert = NSAlert()
        alert.messageText = "apiKeys.missing.title".loc
        alert.informativeText = "apiKeys.missing.message".loc
        alert.addButton(withTitle: "apiKeys.missing.open".loc)
        alert.addButton(withTitle: "common.close".loc)
        if alert.runModal() == .alertFirstButtonReturn {
            (NSApp.delegate as? AppDelegate)?.showOnboarding(openSettings: true)
        }
    }

    private func ensureSelectionsValid() {
        // Keys unreadable ≠ keys deleted: resetting here would wipe every module's key
        // choice in the user's real settings (it did, during screenshot runs).
        guard !keyVault.keysUnknown else { return }
        if entry(for: selectedErrorFix) == nil {
            selectedErrorFix = APIKeyStore.emptySelection()
            saveSelection(selectedErrorFix, key: selectedErrorFixStorage)
        }
        if entry(for: selectedVoiceToText) == nil {
            selectedVoiceToText = APIKeyStore.emptySelection()
            saveSelection(selectedVoiceToText, key: selectedVoiceStorage)
        }
        for (id, sel) in customSelections {
            if entry(for: sel) == nil {
                customSelections[id] = APIKeyStore.emptySelection()
            }
        }
        saveCustomSelections()
    }
    
    private func normalize(selection: APIKeySelection) -> APIKeySelection {
        var sel = selection
        if sel.model == nil || sel.model?.isEmpty == true {
            if let entry = entry(for: sel) {
                sel.model = entry.model ?? entry.provider.defaultModel
            } else {
                sel.model = sel.provider.defaultModel
            }
        }
        return sel
    }
    
    /// Where an item of the "used in" list leads.
    enum Consumer: Equatable {
        case module(ModuleKind)
        case custom(UUID)
    }

    /// Key consumers WITH THE ADDRESS of each. Only names used to be returned: the list said
    /// what would break on deletion, but there was no way to get from it to the module.
    func consumerTargets(of keyId: UUID) -> [Consumer] {
        var out: [Consumer] = []
        if currentSelection(for: .errorFix).keyId == keyId { out.append(.module(.errorFix)) }
        if currentSelection(for: .voiceToText).keyId == keyId { out.append(.module(.voiceToText)) }
        for (moduleId, sel) in customSelections where sel.keyId == keyId {
            out.append(.custom(moduleId))
        }
        return out
    }

    /// Who uses the key. Returns consumer NAMES — the same ones the deletion warning shows:
    /// the list of what will break must be specific, otherwise the user can't judge the cost
    /// of the action.
    func consumers(of keyId: UUID, customModuleNames: [UUID: String]) -> [String] {
        var out: [String] = []
        // Names come from the string catalog: the list is shown on screen, not in the log, and
        // the localization gate didn't look here before — an English window showed Russian
        // module names under the key.
        if currentSelection(for: .errorFix).keyId == keyId { out.append("module.errorFix.title".loc) }
        if currentSelection(for: .voiceToText).keyId == keyId { out.append("module.voiceToText.title".loc) }
        for (moduleId, sel) in customSelections where sel.keyId == keyId {
            out.append(customModuleNames[moduleId] ?? "modules.custom.new.name".loc)
        }
        return out
    }

    /// Clears ALL module-to-key bindings.
    ///
    /// Needed by import: the export file has no keys and can't have them, and a saved binding
    /// would point to a key from ANOTHER machine — the module would look configured and silently
    /// not work. The keys already set up on this computer are left untouched.
    func clearAllSelections() {
        selectedErrorFix = APIKeyStore.emptySelection()
        saveSelection(selectedErrorFix, key: selectedErrorFixStorage)
        selectedVoiceToText = APIKeyStore.emptySelection()
        saveSelection(selectedVoiceToText, key: selectedVoiceStorage)
        customSelections = [:]
        saveCustomSelections()
        Log.info(.app, "Привязки модулей к ключам обнулены (импорт настроек)")
    }

    private func saveKeys() {
        guard !keyVault.save(keys) else { return }
        // Without this the key lives only in memory and silently vanishes on restart.
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "apiKeys.saveFailed.title".loc
        alert.informativeText = "apiKeys.saveFailed.message".loc
        alert.runModal()
    }
    
    private static func loadSelection(defaults: UserDefaults, key: String) -> APIKeySelection? {
        guard let data = defaults.data(forKey: key),
              let selection = try? JSONDecoder().decode(APIKeySelection.self, from: data) else { return nil }
        return selection
    }
    
    private static func loadCustomSelections(defaults: UserDefaults, key: String) -> [UUID: APIKeySelection] {
        guard let data = defaults.data(forKey: key),
              let selection = try? JSONDecoder().decode([UUID: APIKeySelection].self, from: data) else { return [:] }
        return selection
    }
    
    private func saveSelection(_ selection: APIKeySelection, key: String) {
        if let data = try? JSONEncoder().encode(selection) {
            defaults.set(data, forKey: key)
        }
    }
    
    private func saveCustomSelections() {
        if let data = try? JSONEncoder().encode(customSelections) {
            defaults.set(data, forKey: customSelectionsStorage)
        }
    }
}
