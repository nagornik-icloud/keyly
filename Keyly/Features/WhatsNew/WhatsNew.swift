import Foundation

/// "What's new" after an update — PURE logic for deciding whether to show it.
///
/// A mistake here is silent either way: not showing it — the user never learns about the features
/// they got with the update; showing it again — the card comes back after every launch and turns
/// into an ad that can't be dismissed. So the rule is separate and covered by tests.
enum WhatsNew {

    /// Whether to show the card.
    ///
    /// Not shown on the FIRST launch (`seenVersion == nil`): the user hasn't seen the product
    /// yet and has nothing to compare "what's new" against — the setup wizard greets them there.
    static func shouldShow(currentVersion: String, seenVersion: String?) -> Bool {
        guard !currentVersion.isEmpty else { return false }
        guard let seenVersion, !seenVersion.isEmpty else { return false }
        return seenVersion != currentVersion
    }

    /// What to store after the card is closed. We store the CURRENT version, not a "shown" flag:
    /// a boolean flag would have to be reset by hand on every release, and one day that would be forgotten.
    static func versionToRemember(currentVersion: String) -> String { currentVersion }

    /// What to remember on the first launch so the card doesn't pop up right after the wizard.
    static func initialSeenVersion(currentVersion: String) -> String { currentVersion }
}
