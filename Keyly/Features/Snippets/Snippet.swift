import Foundation

struct Snippet: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    /// The name is OPTIONAL. An optional type, not an empty string: an empty string is a value
    /// you must remember to check everywhere, and it already leaked into the UI as `""` in the
    /// list. The model had no notion of "no name", so there was no way to tell it from a name
    /// made of two quotes.
    var name: String?
    var content: String
    var hotKey: KeyCombo?
    var triggers: [String] = []
    var isEnabled: Bool = true
    /// When the trigger fires. Set PER snippet: "@@email" naturally fires right away, while
    /// "addr" should fire only once the word is complete — otherwise it fires inside "address".
    var triggerMode: TriggerMode = .afterSeparator

    enum TriggerMode: String, Codable, CaseIterable {
        /// Waits for a separator (space, tab, Enter). Default: safer — never fires inside a word.
        case afterSeparator
        /// Fires right on the trigger's last character.
        case immediate

        static let separators: Set<Character> = [" ", "\t", "\n", "\r"]
    }

    enum CodingKeys: String, CodingKey {
        case id, name, content, hotKey, triggers, isEnabled, triggerMode
    }

    /// What to show in the list and the palette: the name if set, otherwise the start of the
    /// text. It lives in ONE function because this fallback used to be spread across two views
    /// and wasn't applied in the snippet list at all — hence `""` showing up on screen.
    /// Catalog key for a snippet with neither name nor text.
    static let emptyTitleKey = "snippets.untitled"

    var displayTitle: String {
        if let name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return name
        }
        // Collapse ALL whitespace runs, not just newlines.
        //
        // Only `\n` used to be replaced, and text like "LeadsForm\t\tCreate best…" showed up in
        // the list with a hole mid-line — it read as a second column or as two entries glued
        // together. Both parts had the same brightness (measured 111/111), so to the eye it's not
        // "a different style" but a gap in the wrong place.
        let flat = content
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // A catalog key, not a ready string: this type is in the test package, where
        // `LanguageManager` isn't available. Views pass the result through `.loc` — a no-op for a
        // normal title (no such key in the catalog, so `.loc` returns the string itself), and a
        // translation for the fallback. The fallback still lives only here.
        if flat.isEmpty { return Self.emptyTitleKey }
        return flat.count <= 48 ? flat : String(flat.prefix(48)) + "…"
    }

    init(id: UUID = UUID(),
         name: String? = nil,
         content: String,
         hotKey: KeyCombo? = nil,
         triggers: [String] = [],
         isEnabled: Bool = true,
         triggerMode: TriggerMode = .afterSeparator) {
        self.id = id
        self.name = name
        self.content = content
        self.hotKey = hotKey
        self.triggers = triggers
        self.isEnabled = isEnabled
        self.triggerMode = triggerMode
    }

    // Custom decoder: migration from the old format (single triggerSequence) and default
    // isEnabled=true for snippets saved before the flag existed.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        // decodeIfPresent, NOT decode: otherwise a record without a name fails decoding of the
        // WHOLE array, and the old store returned [] on any error and wiped the data on the next
        // save. An empty string from the old format becomes nil — there is exactly one "no name".
        let rawName = try c.decodeIfPresent(String.self, forKey: .name)
        self.name = (rawName?.isEmpty ?? true) ? nil : rawName
        self.content = try c.decode(String.self, forKey: .content)
        self.hotKey = try c.decodeIfPresent(KeyCombo.self, forKey: .hotKey)
        self.isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        // Records made before the mode existed fired IMMEDIATELY — keep that behavior for them,
        // otherwise the moment of insertion would silently change for the user.
        self.triggerMode = try c.decodeIfPresent(TriggerMode.self, forKey: .triggerMode) ?? .immediate

        if let arr = try c.decodeIfPresent([String].self, forKey: .triggers) {
            self.triggers = arr
        } else {
            // The old `triggerSequence: String?` field is no longer in CodingKeys —
            // read it with a dynamic key for migration.
            struct LegacyKey: CodingKey {
                var stringValue: String
                var intValue: Int? { nil }
                init?(stringValue: String) { self.stringValue = stringValue }
                init?(intValue: Int) { return nil }
            }
            if let legacy = try? decoder.container(keyedBy: LegacyKey.self),
               let key = LegacyKey(stringValue: "triggerSequence"),
               let value = try? legacy.decode(String.self, forKey: key),
               !value.isEmpty {
                self.triggers = [value]
            } else {
                self.triggers = []
            }
        }
    }
}
