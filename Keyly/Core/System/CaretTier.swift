import Foundation

/// Deciding "which confidence tier" — a PURE function over already collected signals.
///
/// Why separate from `CaretProbe`. The probe crawls the Accessibility API: it can't be called
/// from a test or wired into the test package — it would drag half the app along. And it's the
/// DECISION that goes wrong here, silently: the product either refuses to work in a real field
/// or — more costly — treats plain web page text as a field and selects all of it.
/// A real run caught exactly the second case.
///
/// The file has no AppKit/ApplicationServices import: only `Foundation`.
enum CaretTier {

    /// Confidence level. Ordered from strong to weak.
    enum Confidence: Equatable {
        /// Editability proven AND the caret position is known.
        case caret
        /// Editability proven, but no caret rect obtained (Electron, secure).
        case editable
        /// AX is silent: a guess by app name and recent typing. NOT proof.
        case ambiguous
        /// Clearly not a text field.
        case none
    }

    /// AX's answer to "can text be written here".
    enum Editability: Equatable {
        /// `AXEditable` = true or `AXValue` is settable.
        case proven
        /// AX explicitly said "no" (read-only NSTextView: Mail's reading pane, Xcode console).
        case denied
        /// AX didn't answer.
        case unknown
    }

    /// Signals collected by the probe. Not a single AppKit type — that's the whole point.
    struct Signals: Equatable {
        /// The element's role is rejected by the veto list (AXWebArea, AXButton, etc.).
        var roleVetoed: Bool = false
        var editability: Editability = .unknown
        /// Whether a plausible caret rectangle was obtained.
        var hasCaretRect: Bool = false
        /// The hit test at the last click returned a PROVEN editable element.
        var hitTestFoundEditable: Bool = false
        /// The tree walk found an editable element.
        var scanFoundEditable: Bool = false
        /// The app is in the list of known text apps.
        var appInAllowlist: Bool = false
        /// The user typed in the last few seconds.
        var recentlyTyped: Bool = false
    }

    /// Verdict from the signals.
    ///
    /// The order of checks is a law, not style:
    ///  1. direct focus with PROVEN editability;
    ///  2. hit test at the click (Chrome/Electron, where focus is unreliable);
    ///  3. tree walk — only if the focus isn't vetoed by role and not explicitly rejected,
    ///     otherwise a walk from the document area finds some other search field on the page;
    ///  4. fallback by app name — and it may NOT override an explicit AX refusal.
    static func resolve(_ s: Signals) -> Confidence {
        // 1. Direct focus. The caret only REFINES the tier here: by itself it proves nothing —
        //    a click on plain page text in Safari also returns a rect.
        if !s.roleVetoed, s.editability == .proven {
            return s.hasCaretRect ? .caret : .editable
        }

        // 2. The hit test returns only a proven editable element.
        if s.hitTestFoundEditable {
            return s.hasCaretRect ? .caret : .editable
        }

        // 3. Tree walk — under the same two restrictions.
        if !s.roleVetoed, s.editability != .denied, s.scanFoundEditable {
            return s.hasCaretRect ? .caret : .editable
        }

        // 4. An explicit AX refusal is evidence AGAINST, and a guess by app name doesn't override
        //    it: otherwise Mail and Xcode from the list would cancel out the refusal.
        if s.editability == .denied {
            return .none
        }
        if s.appInAllowlist || s.recentlyTyped {
            return .ambiguous
        }
        return .none
    }

    /// Whether editability is proven. Separate from the tier because this answer decides whether
    /// the destructive `Cmd+A` may be sent: for `.ambiguous` — no.
    static func isEditable(_ confidence: Confidence) -> Bool {
        confidence == .caret || confidence == .editable
    }
}
