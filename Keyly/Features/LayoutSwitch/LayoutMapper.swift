import Foundation

/// Character tables and RU↔EN layout conversion.
enum LayoutMapper {
    static let layout1: [Character] = Array("`1234567890-=qwertyuiop[]\\asdfghjkl;'zxcvbnm,./~!@#$%^&*()_+QWERTYUIOP{}|ASDFGHJKL:\"ZXCVBNM<>?")
    static let layout2: [Character] = Array("]1234567890-=йцукенгшщзхъёфывапролджэячсмитьбю/[!\"№%:,.;()_+ЙЦУКЕНГШЩЗХЪЁФЫВАПРОЛДЖЭЯЧСМИТЬБЮ?")

    private static let map1to2: [Character: Character] = {
        var d = [Character: Character]()
        for (c1, c2) in zip(layout1, layout2) { d[c1] = c2 }
        return d
    }()

    private static let map2to1: [Character: Character] = {
        var d = [Character: Character]()
        for (c1, c2) in zip(layout1, layout2) { d[c2] = c1 }
        return d
    }()

    /// The layout the text was TYPED in.
    enum Layout {
        case en   // Latin (layout1)
        case ru   // Cyrillic (layout2)
    }

    /// Detects the layout from THE TEXT ITSELF: Cyrillic letters = typed in RU, Latin = in EN.
    ///
    /// Why not from the current system layout (the first implementation did exactly that): the
    /// user notices the mistake, switches the layout themselves FIRST, and only then presses the
    /// hotkey. By then the "current" layout is already the opposite of the one the text was
    /// typed in, and the direction flips: the word stays wrong, and the manual switch gets
    /// undone. The text, on the other hand, never lies about where it came from.
    ///
    /// `nil` — the text has no letters (only punctuation) or an equal count: direction unknown.
    static func detectLayout(of text: String) -> Layout? {
        var latin = 0, cyrillic = 0
        for ch in text.unicodeScalars {
            switch ch.value {
            case 0x0410...0x044F, 0x0401, 0x0451:   // Cyrillic A–Ya, plus Yo/yo
                cyrillic += 1
            case 0x41...0x5A, 0x61...0x7A:          // A-Z, a-z
                latin += 1
            default:
                break
            }
        }
        if cyrillic > latin { return .ru }
        if latin > cyrillic { return .en }
        return nil
    }

    /// Converts text KNOWING the source layout — the preferred path.
    ///
    /// Direction matters for correctness: without it we can't know what the user meant. A
    /// character like `"` exists in BOTH tables, and per-character guessing (`convert(_:)`
    /// below) always resolves it one way — so pressing the hotkey again doesn't undo the result
    /// but mangles it further. The directed pass uses EXACTLY ONE dictionary, so conversion is
    /// exactly reversible.
    static func convert(_ str: String, from layout: Layout) -> String {
        let table = layout == .en ? map1to2 : map2to1
        var result = String()
        result.reserveCapacity(str.count)
        for ch in str {
            result.append(table[ch] ?? ch)
        }
        return result
    }

    /// Converts by GUESSING the layout per character. Fallback for when the current layout
    /// couldn't be determined (TIS unavailable).
    ///
    /// ⚠️ Ambiguous: characters present in both tables are always treated as Latin, so for
    /// eight of them (`` ` ~ @ $ % ^ & * ``) converting again does NOT return the original.
    /// Prefer `convert(_:from:)`.
    static func convert(_ str: String) -> String {
        var result = String()
        result.reserveCapacity(str.count)
        for ch in str {
            if let mapped = map1to2[ch] { result.append(mapped) }
            else if let mapped = map2to1[ch] { result.append(mapped) }
            else { result.append(ch) }
        }
        return result
    }
}
