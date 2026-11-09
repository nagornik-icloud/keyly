import Foundation

/// Badge texts — in ONE place and without UI dependencies, so the "short line" contract
/// is checked by a unit test, not only by a runtime log.
///
/// Why it matters: a badge physically fits one line, and a copy edit or localization
/// (RU→DE adds 20–30 %) silently eats the tail — and the status turns into a stub cut mid-word.
/// The contract is checked against the SHIPPED catalog (`StringCatalogTests.badgeStringsFitInEveryLanguage`)
/// — for all languages at once, not against the constants here.
enum BadgeText {

    /// Length ceiling. Matched to the plate width: ~7.8 pt per character against a 320 pt ceiling.
    static let maxCharacters = 34

    // Refusals
    static var noTextField: String { "badge.noTextField".loc }
    static var noFieldBuffered: String { "badge.noFieldBuffered".loc }
    static var secureField: String { "badge.secureField".loc }
    static var secureBuffered: String { "badge.secureBuffered".loc }
    static var secureTyping: String { "badge.secureTyping".loc }
    /// A STUCK system mode, not a real password field. A separate text is required: a silent
    /// refusal in this case reads as "Keyly is broken", and the user won't guess that the fix
    /// is restarting the browser, not the app.
    static var secureStuck: String { "badge.secureStuck".loc }
    static var readFailed: String { "badge.readFailed".loc }
    /// Text post-processing didn't happen. "No key" and "failed" are separate: the first is fixed
    /// on screen, the second by the network or a mode change, and the user needs to know where to go.
    static var polishNeedsKey: String { "badge.polishNeedsKey".loc }
    static var polishFailed: String { "badge.polishFailed".loc }
    /// The model returned an ANSWER to the text instead of the text itself, and `TextPolishGuard`
    /// blocked it. A separate wording rather than a generic "failed": the cause is different and
    /// is fixed differently — it's not the network or the key. An indistinguishable message
    /// wouldn't let the user see that the product worked correctly and protected their text.
    static var polishAnswered: String { "badge.polishAnswered".loc }
    /// The module's result went to the clipboard, not into the field. Saying so is mandatory:
    /// the user expects text on screen and, not finding it, thinks the module didn't work.
    static var resultCopied: String { "badge.resultCopied".loc }
    static var resultBuffered: String { "badge.resultBuffered".loc }
    /// The "selection" source has nothing to take. A separate text from "no field": the cause is
    /// different and so is the fix — select text, not place the cursor.
    static var nothingToProcess: String { "badge.nothingToProcess".loc }

    // Recording refusals. They used to go only to the log — from outside they looked like "nothing
    // happened", and there was no way to tell "broke" from "didn't catch that".
    //
    // Rule for these strings: the badge can't be clicked and lives 5 seconds, so the text is the ONLY
    // carrier of the next step. Claim only what the code actually knows: `record()` doesn't
    // distinguish "busy" from "disconnected", so the text doesn't name a cause either.
    static var micDenied: String { "badge.micDenied".loc }
    static var micUnavailable: String { "badge.micUnavailable".loc }
    static var recordFailed: String { "badge.recordFailed".loc }
    static var nothingHeard: String { "badge.nothingHeard".loc }

    /// Local recognition refusal. Separate strings, not a generic "failed": "not downloaded" is
    /// fixed by a button on the voice screen, "failed" by a mode change, and the user needs to
    /// know where to go. Silently going to the cloud instead of refusing is forbidden: it changes
    /// the data route without consent.
    static var localModelMissing: String { "badge.localModelMissing".loc }
    static var localModelFailed: String { "badge.localModelFailed".loc }
    /// Neither model nor key: BOTH ways out are closed, and the user must be told about both.
    static var localModelOrKey: String { "badge.localModelOrKey".loc }
    /// Cloud mode without a key. Refuse before recording, not after.
    static var voiceNeedsKey: String { "badge.voiceNeedsKey".loc }
    /// Typo fixing without a key. Refuse before touching the clipboard.
    static var errorFixNeedsKey: String { "badge.errorFixNeedsKey".loc }
    /// The selected input stopped delivering a signal. Say so instead of stopping silently:
    /// otherwise the recording cut-off looks like a random product failure.
    static var inputLost: String { "badge.inputLost".loc }
    /// Microphone permission is there but there is no stream: macOS answered `.authorized` and
    /// didn't let us access the device. The text leads to Privacy settings instead of talking about the headset.
    static var micNoSignal: String { "badge.micNoSignal".loc }
    /// No network. A separate text from "failed": nothing in the product fixes it, and the user
    /// needs to know it's not about the key or the settings.
    static var offline: String { "badge.offline".loc }
    /// The launcher target didn't open. Success stays silent — it is self-evident, but a refusal
    /// without a message is indistinguishable from a hotkey that didn't fire.
    static var launchFailed: String { "badge.launchFailed".loc }

    // Undo. A refusal must name the REASON: "didn't work" without an explanation reads as
    // a breakage, while here the app is precisely protecting the user's text.
    static var undoNothing: String { "badge.undoNothing".loc }
    static var undoExpired: String { "badge.undoExpired".loc }
    static var undoChanged: String { "badge.undoChanged".loc }

    // Operation lock.
    static var alreadyBusy: String { "badge.alreadyBusy".loc }
    static var cancelled: String { "badge.cancelled".loc }

    // Progress
    static var fixing: String { "badge.fixing".loc }
    static var noErrorsFound: String { "badge.noErrorsFound".loc }

}
