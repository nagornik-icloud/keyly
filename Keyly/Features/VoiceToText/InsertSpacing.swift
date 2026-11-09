import Foundation

/// Whether a space is needed before the inserted text.
///
/// Dictated text is inserted at the caret as is, and if a letter or a period stands before it,
/// the text sticks to it: "…whether there will be paragraph breaks or not.This is a penalty".
/// The user dictates a continuation of the sentence and gets glued text that has to be fixed
/// by hand — exactly what dictation is supposed to spare them.
///
/// Pure logic: the rule is checked by a test, not by dictating into someone else's field.
enum InsertSpacing {

    /// Characters after which NO space is needed: line start, whitespace, opening brackets
    /// and quotes — a space there would look like a typo.
    private static let noSpaceAfter: Set<Character> = [
        " ", "\t", "\n", "\r", "(", "[", "{", "«", "“", "\"", "'", "-", "—", "/",
    ]

    /// Whether to put a space between `previous` and the inserted text.
    /// `previous` is the character left of the caret; `nil` means the caret is at the start of the field.
    static func needsLeadingSpace(previous: Character?, inserted: String) -> Bool {
        guard let previous else { return false }
        guard !noSpaceAfter.contains(previous) else { return false }
        // The first character of the insertion may itself be punctuation — then a space before it
        // is wrong: "hello ," instead of "hello,".
        guard let first = inserted.first else { return false }
        if first.isWhitespace { return false }
        if ",.!?;:)]}»".contains(first) { return false }
        return true
    }

    /// The insertion text with a leading space, if one is needed.
    static func prepared(_ text: String, previous: Character?) -> String {
        needsLeadingSpace(previous: previous, inserted: text) ? " " + text : text
    }
}
