import Foundation

/// What a screen remembers WITHIN A SESSION.
///
/// Leaving to another section and coming back must not wipe work: the user was searching
/// for a snippet, popped into settings for a key, came back — and found an empty search
/// and a collapsed editor. That is not a "minor inconvenience" but a lost action: they
/// don't remember what exactly they typed in the search.
///
/// Intentionally NOT kept between LAUNCHES: someone coming back tomorrow expects a clean
/// screen, not yesterday's long-forgotten filter.
struct ScreenSessionState: Equatable {
    /// Search query on the snippets screen.
    var snippetQuery: String = ""
    /// Expanded snippet card.
    var expandedSnippetId: UUID?
    /// Last opened section — so that "back" leads where we came from.
    var lastSelection: NavItem?
}
