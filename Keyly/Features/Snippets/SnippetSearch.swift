import Foundation

/// Snippet search for the global palette — PURE logic, no UI.
///
/// Why separate and tested: ranking fails silently. A wrong order doesn't crash — it just puts
/// the wanted snippet second, the user hits Enter without looking and inserts the wrong text.
/// That's worse than an empty list.
enum SnippetSearch {

    /// A result with a score — callers don't need the score, but sorting uses it and tests check it.
    struct Match: Equatable {
        let snippet: Snippet
        let score: Int
    }

    /// Ranked list. Empty query → all enabled snippets in original order: the palette opens with
    /// an empty query, and the user should immediately see what they have.
    static func rank(_ snippets: [Snippet], query: String) -> [Snippet] {
        let cleaned = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let enabled = snippets.filter { $0.isEnabled }
        guard !cleaned.isEmpty else { return enabled }

        return enabled
            .compactMap { snippet -> Match? in
                guard let score = score(snippet, query: cleaned) else { return nil }
                return Match(snippet: snippet, score: score)
            }
            // Stable sort: equal scores keep the original order — otherwise equally relevant
            // snippets would jump around between keystrokes.
            .enumerated()
            .sorted { lhs, rhs in
                lhs.element.score == rhs.element.score
                    ? lhs.offset < rhs.offset
                    : lhs.element.score > rhs.element.score
            }
            .map(\.element.snippet)
    }

    /// `nil` — no match. Higher = more relevant.
    ///
    /// Weights are deliberately coarse with big gaps: an exact trigger match must beat ANY
    /// occurrence in the text, otherwise a long snippet that happens to contain the query would
    /// push out the one the user called by its trigger.
    static func score(_ snippet: Snippet, query: String) -> Int? {
        let triggers = snippet.triggers.map { $0.lowercased() }
        let name = (snippet.name ?? "").lowercased()
        let content = snippet.content.lowercased()

        if triggers.contains(query) { return 1000 }
        if triggers.contains(where: { $0.hasPrefix(query) }) { return 800 }
        if !name.isEmpty, name == query { return 700 }
        if !name.isEmpty, name.hasPrefix(query) { return 600 }
        if !name.isEmpty, name.contains(query) { return 400 }
        if triggers.contains(where: { $0.contains(query) }) { return 300 }
        if content.contains(query) { return 100 }
        return nil
    }

    // MARK: - Trigger validator

    /// Trigger conflict: an exact duplicate OR a prefix overlap.
    ///
    /// Overlap matters more than duplicates: `addr` overlaps `address` — typing the long trigger,
    /// the user never gets there, because the short one fires first and eats the input. Such a
    /// conflict isn't visible in the list and shows up only as "the snippet doesn't work".
    struct TriggerConflict: Equatable {
        let trigger: String
        let conflictsWith: String
        let isExactDuplicate: Bool
    }

    static func triggerConflicts(in snippets: [Snippet]) -> [TriggerConflict] {
        var seen: [(trigger: String, owner: UUID)] = []
        var conflicts: [TriggerConflict] = []

        for snippet in snippets where snippet.isEnabled {
            for raw in snippet.triggers {
                let trigger = raw.lowercased()
                guard !trigger.isEmpty else { continue }
                for other in seen where other.owner != snippet.id {
                    if other.trigger == trigger {
                        conflicts.append(TriggerConflict(trigger: raw, conflictsWith: other.trigger,
                                                         isExactDuplicate: true))
                    } else if trigger.hasPrefix(other.trigger) || other.trigger.hasPrefix(trigger) {
                        // The shorter one will grab the input; report exactly this pair.
                        conflicts.append(TriggerConflict(trigger: raw, conflictsWith: other.trigger,
                                                         isExactDuplicate: false))
                    }
                }
                seen.append((trigger: trigger, owner: snippet.id))
            }
        }
        return conflicts
    }

    /// Which snippet fires for the typed tail — the **LONGEST** matching trigger.
    /// List order doesn't matter: otherwise drag-reordering would silently change behavior.
    static func matchByLongestTrigger(typed: String, in snippets: [Snippet]) -> (Snippet, String)? {
        var best: (snippet: Snippet, trigger: String)?
        for snippet in snippets where snippet.isEnabled {
            for trigger in snippet.triggers where !trigger.isEmpty && typed.hasSuffix(trigger) {
                if best == nil || trigger.count > best!.trigger.count {
                    best = (snippet, trigger)
                }
            }
        }
        return best.map { ($0.snippet, $0.trigger) }
    }

    /// Match that respects the trigger MODE.
    ///
    /// The two groups are matched separately because they look at different things:
    /// "immediate" at the typed tail, "after separator" at the word BEFORE the separator just
    /// typed. A shared tail match would never work for the second group: at the moment of the
    /// separator the tail ends with a space, not the trigger.
    ///
    /// `justTyped` is the character the user just typed. `nil` — insertion not from typing
    /// (e.g. by hotkey), so the mode doesn't apply.
    static func match(typed: String, justTyped: Character?,
                      in snippets: [Snippet]) -> (snippet: Snippet, trigger: String, separator: Character?)? {
        // Separator: search the "after separator" group by the word BEFORE it.
        if let justTyped, Snippet.TriggerMode.separators.contains(justTyped) {
            let beforeSeparator = String(typed.dropLast())
            let cohort = snippets.filter { $0.triggerMode == .afterSeparator }
            if let hit = matchByLongestTrigger(typed: beforeSeparator, in: cohort) {
                return (hit.0, hit.1, justTyped)
            }
            return nil
        }
        // Regular character: search the "immediate" group by the typed tail.
        let cohort = snippets.filter { $0.triggerMode == .immediate }
        if let hit = matchByLongestTrigger(typed: typed, in: cohort) {
            return (hit.0, hit.1, nil)
        }
        return nil
    }

    /// Whether such a trigger may be CREATED (overlapping triggers are forbidden).
    ///
    /// An overlap used to be only flagged with a warning and handled by a waiting window: while
    /// the user might still finish typing the long trigger, the short one didn't fire. In
    /// practice that produced confusing behavior — "the short one doesn't fire after a space",
    /// "type the long one slowly and the short one fires first". Forbidding at entry removes the
    /// cause, not the symptom.
    ///
    /// BOTH directions are checked: the new trigger starts with an existing one AND an existing
    /// one starts with the new one.
    static func triggerIsAllowed(_ trigger: String, existing: [Snippet],
                                 excluding snippetId: UUID?) -> Bool {
        let candidate = trigger.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard candidate.count >= 2 else { return true }   // short ones are filtered by a separate rule

        for snippet in existing where snippet.id != snippetId {
            for other in snippet.triggers {
                let existingTrigger = other.lowercased()
                guard !existingTrigger.isEmpty else { continue }
                if candidate == existingTrigger { return false }
                if candidate.hasPrefix(existingTrigger) || existingTrigger.hasPrefix(candidate) {
                    return false
                }
            }
        }
        return true
    }

    /// Could the typed trigger be the START of another, longer one?
    ///
    /// Without this the "longest wins" rule physically can't work. Matching runs on every
    /// keystroke, and by the time the user has typed "addr" of "address", the short trigger has
    /// already matched in full — it fired, and the long one NEVER got its turn. Sorting by length
    /// can't help: the long one isn't in the buffer yet.
    ///
    /// So an ambiguous match doesn't fire right away but waits — the user may keep typing.
    /// Case-insensitive, just like trigger matching.
    static func hasLongerTriggerStarting(with trigger: String, in snippets: [Snippet]) -> Bool {
        let lowered = trigger.lowercased()
        for snippet in snippets where snippet.isEnabled {
            for other in snippet.triggers where other.count > trigger.count {
                if other.lowercased().hasPrefix(lowered) { return true }
            }
        }
        return false
    }
}
