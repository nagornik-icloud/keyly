import Foundation

/// Placeholders in snippet text.
///
/// Chip buttons in the editor insert these tokens, and the snippet expands them on insertion.
/// The logic is pure and tested: it runs when the user has already typed the trigger and is
/// looking at another app — a bug here shows only as wrong text that's already been inserted.
enum SnippetPlaceholders {

    enum Token: String, CaseIterable {
        case date = "{дата}"
        case time = "{время}"
        case clipboard = "{буфер}"
        case caret = "{курсор}"

        /// Latin spelling of the same token.
        ///
        /// A Cyrillic token is physically out of reach for someone on an English layout: to type
        /// the Cyrillic date token they'd have to switch layouts mid-snippet — exactly what Keyly
        /// is meant to spare them. The app is multilingual, and half the feature was unavailable
        /// to half the audience.
        ///
        /// Renaming wasn't possible: people already have saved snippets with Cyrillic tokens, and
        /// changing the spelling would turn them into literal token text in the middle of an
        /// email. So both spellings are EQUAL: the canonical one stays Cyrillic (`rawValue`, chips
        /// insert it), and the Latin one is accepted on expansion just the same.
        var latin: String {
            switch self {
            case .date:      return "{date}"
            case .time:      return "{time}"
            case .clipboard: return "{clipboard}"
            case .caret:     return "{cursor}"
            }
        }

        /// All spellings of the token — these are what we search for in the text.
        var spellings: [String] { [rawValue, latin] }

        /// The spelling a chip INSERTS — depends on the interface language.
        ///
        /// Both spellings expand the same way, but for someone with an English interface the
        /// chip must not put Cyrillic into the text: they couldn't read it or retype it by hand.
        /// The Russian interface keeps getting the canonical spelling, so existing snippets
        /// don't change.
        static func preferred(_ token: Token, language: String) -> String {
            language.hasPrefix("ru") ? token.rawValue : token.latin
        }

        var titleKey: String {
            switch self {
            case .date:      return "snippets.placeholder.date"
            case .time:      return "snippets.placeholder.time"
            case .clipboard: return "snippets.placeholder.clipboard"
            case .caret:     return "snippets.placeholder.caret"
            }
        }

        var icon: String {
            switch self {
            case .date:      return "calendar"
            case .time:      return "clock"
            case .clipboard: return "doc.on.clipboard"
            case .caret:     return "text.cursor"
            }
        }
    }

    /// Expansion result. The caret position is separate: the cursor token leaves nothing in
    /// the text but determines where the cursor lands after insertion.
    struct Expansion: Equatable {
        let text: String
        /// Caret offset from the START of the inserted text; `nil` — cursor at the end.
        let caretOffset: Int?
    }

    static func expand(_ content: String,
                       now: Date,
                       clipboard: String?,
                       calendar: Calendar = .current,
                       locale: Locale = .current) -> Expansion {
        var text = content

        let dateFormatter = DateFormatter()
        dateFormatter.locale = locale
        dateFormatter.calendar = calendar
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .none
        text = replace(Token.date, in: text, with: dateFormatter.string(from: now))

        let timeFormatter = DateFormatter()
        timeFormatter.locale = locale
        timeFormatter.calendar = calendar
        timeFormatter.dateStyle = .none
        timeFormatter.timeStyle = .short
        text = replace(Token.time, in: text, with: timeFormatter.string(from: now))

        // An empty clipboard is substituted with an EMPTY string rather than leaving the token:
        // a raw clipboard token in the middle of a pasted email looks like a bug, while an
        // empty spot the user can fill in themselves.
        text = replace(Token.clipboard, in: text, with: clipboard ?? "")

        // Caret goes LAST: the substitutions above change the text length, and a position
        // computed before them would point to the wrong place.
        // The first caret marker in ANY spelling: if the text has both the Cyrillic and the
        // Latin cursor token, the earlier one wins — otherwise the position would depend on the
        // order spellings are checked, not on the text.
        let ranges = Token.caret.spellings.compactMap { text.range(of: $0) }
        guard let range = ranges.min(by: { $0.lowerBound < $1.lowerBound }) else {
            return Expansion(text: text, caretOffset: nil)
        }
        let offset = text.distance(from: text.startIndex, to: range.lowerBound)
        // Only the FIRST caret marker: there's nowhere to put a second cursor, and leaving it as
        // a token in the text is not allowed — see above.
        var result = text.replacingCharacters(in: range, with: "")
        for spelling in Token.caret.spellings {
            result = result.replacingOccurrences(of: spelling, with: "")
        }
        return Expansion(text: result, caretOffset: offset)
    }

    /// Replaces ALL spellings of the token with one value.
    private static func replace(_ token: Token, in text: String, with value: String) -> String {
        token.spellings.reduce(text) { $0.replacingOccurrences(of: $1, with: value) }
    }

    /// Whether the text has any placeholder — decides whether clipboard access and caret
    /// recalculation are needed.
    static func containsPlaceholders(_ content: String) -> Bool {
        Token.allCases.contains { token in token.spellings.contains { content.contains($0) } }
    }
}
