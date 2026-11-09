import Foundation

/// The pair of system RU↔EN layouts the feature switches between.
///
/// Why not "switch to the next one in the cycle": with a third layout installed (Ukrainian,
/// emoji, a second English variant) cycling lands in the wrong place — the text is converted,
/// but the system layout moves to an unrelated source. The pair is stored EXPLICITLY.
///
/// Only pure logic here (picking the pair from a list of ids, telling which side an id is) —
/// TIS calls live in `KeyboardLayoutService`. That way pair selection is unit-tested.
struct KeyboardLayoutPair: Equatable, Codable {
    let enSourceID: String
    let ruSourceID: String

    /// A pair of TWO DIFFERENT layouts. `nil` if both sides match: then `layout(for:)` would
    /// always answer `.en` (the matching `case` is checked first), and `opposite(of:)` would
    /// return the same layout — switching would silently stop working, with no error in the UI.
    init?(enSourceID: String, ruSourceID: String) {
        guard enSourceID != ruSourceID, !enSourceID.isEmpty, !ruSourceID.isEmpty else { return nil }
        self.enSourceID = enSourceID
        self.ruSourceID = ruSourceID
    }

    // MARK: - Auto-detection on first launch

    /// Canonical ids — preferred when installed.
    private static let preferredEN = "com.apple.keylayout.US"
    private static let preferredRU = "com.apple.keylayout.Russian"

    /// Latin layout markers. `ABC` and `US` are the most common; the rest cover users with
    /// British/Canadian/Dvorak etc. instead of US.
    private static let enMarkers = [
        "US", "ABC", "British", "Australian", "Canadian", "Irish",
        "Dvorak", "Colemak", "USExtended", "USInternational"
    ]
    /// Cyrillic variants: besides "Russian" there's RussianWin (typewriter) and others.
    private static let ruMarkers = ["Russian", "RussianWin", "Russian-Phonetic", "Byelorussian"]

    /// Picks the pair from the ids of installed layouts.
    /// `nil` if either side is missing — then the feature makes no sense and must stay silent
    /// rather than switch at random.
    static func autoDetect(from availableIDs: [String]) -> KeyboardLayoutPair? {
        guard let en = pick(preferred: preferredEN, markers: enMarkers, from: availableIDs),
              let ru = pick(preferred: preferredRU, markers: ruMarkers, from: availableIDs)
        else { return nil }
        // en and ru come from different marker sets, but just in case: init rejects a match.
        return KeyboardLayoutPair(enSourceID: en, ruSourceID: ru)
    }

    private static func pick(preferred: String, markers: [String], from ids: [String]) -> String? {
        if ids.contains(preferred) { return preferred }
        // Compare ONLY the last component of the id, not a substring of the whole id.
        // Caught by a test: "Russian" contains "us" ("r-US-sian"), and a loose
        // case-insensitive search for the "US" marker identified the Russian layout as English —
        // conversion direction would be inverted for everyone without a US layout.
        let components = ids.map { (id: $0, name: $0.split(separator: ".").last.map(String.init) ?? $0) }
        // Marker order sets priority; within a marker — system list order, so the choice is
        // deterministic (otherwise the pair would "jump" between launches).
        for marker in markers {
            if let hit = components.first(where: { $0.name.caseInsensitiveCompare(marker) == .orderedSame }) {
                return hit.id
            }
        }
        // Variants like USExtended / Russian-Phonetic — a prefix of the component, not an arbitrary substring.
        for marker in markers {
            if let hit = components.first(where: { $0.name.lowercased().hasPrefix(marker.lowercased()) }) {
                return hit.id
            }
        }
        return nil
    }

    // MARK: - Side detection

    /// Which side of the pair the id is. `nil` — the id isn't in our pair (a third layout is
    /// active): converting by guesswork is not allowed.
    func layout(for sourceID: String) -> LayoutMapper.Layout? {
        switch sourceID {
        case enSourceID: return .en
        case ruSourceID: return .ru
        default: return nil
        }
    }

    /// The other side of the pair — where to switch the system after conversion.
    func opposite(of layout: LayoutMapper.Layout) -> String {
        layout == .en ? ruSourceID : enSourceID
    }
}
