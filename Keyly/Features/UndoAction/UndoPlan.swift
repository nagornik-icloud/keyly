import Foundation

/// Pure undo logic: what exactly we inserted and whether it can be safely reverted.
///
/// Extracted from `UndoActionService` with zero AppKit/AX dependencies, because this is where
/// the "touch the user's text or not" decision lives. A bug here doesn't crash or log — it
/// silently destroys what the user typed by hand, so every branch is tested.
enum UndoPlan {

    /// Common prefix and suffix are dropped — exactly the changed stretch remains.
    ///
    /// Compared by `Character`, not UTF-16: emoji and composed characters (é as e + acute) span
    /// several code units, and cutting through them gives a broken "original" that we'd then
    /// write into the user's field.
    static func diff(before: String, after: String) -> (old: String, new: String) {
        let b = Array(before), a = Array(after)
        var head = 0
        while head < b.count, head < a.count, b[head] == a[head] { head += 1 }
        var tail = 0
        while tail < b.count - head, tail < a.count - head,
              b[b.count - 1 - tail] == a[a.count - 1 - tail] { tail += 1 }
        return (old: String(b[head..<(b.count - tail)]),
                new: String(a[head..<(a.count - tail)]))
    }

    /// What the field text should become after undo. `nil` — can't undo, refuse with a badge.
    ///
    /// The inserted fragment is searched in the CURRENT text, not by a saved offset: the user may
    /// have typed something above our insertion, and a numeric range would then point elsewhere.
    /// "Exactly one occurrence" protects against short fragments (a word fixed by layout switching
    /// easily appears twice in a field): ambiguity is resolved by refusing, not guessing.
    static func restoredText(current: String, before: String, after: String) -> String? {
        // Field untouched since us — return the whole snapshot, that's guaranteed exact.
        if current == after { return before }

        let (old, new) = diff(before: before, after: after)
        // An empty insertion means we only deleted: there's nowhere to put the deleted text back —
        // the position is known only by offset, which is no longer reliable.
        guard !new.isEmpty else { return nil }

        var found: Range<String.Index>?
        var search = current.startIndex..<current.endIndex
        while let range = current.range(of: new, range: search) {
            if found != nil { return nil }   // second occurrence — ambiguous
            found = range
            guard range.upperBound < current.endIndex else { break }
            search = range.upperBound..<current.endIndex
        }
        guard let range = found else { return nil }
        return current.replacingCharacters(in: range, with: old)
    }
}
