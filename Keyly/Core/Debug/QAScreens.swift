#if DEBUG
import Foundation

/// Registry of capturable screens — the ONE home for the "env key → app screen" mapping.
///
/// This list used to live in a private `switch` inside the exporter, and adding a screen
/// required edits in two places: the code and the shell script. A mismatch between them
/// would mean "the screen silently isn't captured", i.e. a blind spot in acceptance — exactly
/// the class this whole capture setup exists to prevent.
///
/// The list must match `docs/qa/visual-inventory.md`: a frame without an inventory entry and
/// an entry without a frame are equally a defect.
@MainActor
enum QAScreens {

    /// Keys in the order `scripts/qa-capture.sh` runs them.
    static let keys = ["overview", "layout", "errorfix", "voice",
                       "applauncher", "snippets", "settings", "custom"]

    /// Three DIFFERENT outcomes instead of `nil` for everything. With them merged, the harness
    /// printed "unknown screen" where the key was right but there was no data — and people went
    /// looking for a typo instead of creating a custom module.
    enum Resolution {
        case ok(id: String, nav: NavItem)
        case noData(why: String)
        case unknownKey
    }

    static func resolve(_ key: String) -> Resolution {
        switch key {
        case "overview":    return .ok(id: "screen-01-overview", nav: .overview)
        // Bottom of the dashboard: the "Global" section and the cheatsheet tail are below the fold.
        case "overview-bottom": return .ok(id: "screen-01b-overview-bottom", nav: .overview)
        // "Readiness" with Input Monitoring not granted: the developer machine has the permission,
        // so this row would never get into any frame.
        case "overview-no-input-monitoring":
            return .ok(id: "screen-01c-overview-no-input-monitoring", nav: .overview)
        // All three permissions missing at once — how the app looks right after installation,
        // and no frame showed it.
        case "overview-no-permissions":
            return .ok(id: "screen-01d-overview-no-permissions", nav: .overview)
        case "layout":      return .ok(id: "screen-02-layout", nav: .module(.layoutSwitch))
        case "errorfix":    return .ok(id: "screen-03-errorfix", nav: .module(.errorFix))
        // Two states of the hotkey FIELD on the same screen. Both come only from user actions and
        // so never got into any frame: recording — from clicking the field, conflict — from
        // pressing an already taken combo.
        case "errorfix-recording": return .ok(id: "screen-03b-errorfix-recording", nav: .module(.errorFix))
        case "errorfix-conflict":  return .ok(id: "screen-03c-errorfix-conflict", nav: .module(.errorFix))
        case "voice":       return .ok(id: "screen-04-voice", nav: .module(.voiceToText))
        // The voice screen is a matrix of three axes (mode × processing level × model state), yet
        // it was captured in exactly one cell: the one set on the author's machine. Because of that
        // two NEW branches of a change went unseen — in "As spoken" the key block with the price
        // stayed live although it affected nothing.
        //
        // The level is overridden by a launch ARGUMENT (`-text.polishLevel verbatim`), not
        // `defaults write`: while a working copy of Keyly is running it holds the domain, and the
        // harness doesn't see a terminal write — all frames come out byte-identical.
        case "voice-verbatim": return .ok(id: "screen-04b-voice-verbatim", nav: .module(.voiceToText))
        // Bottom of the screen: the collapsed "Microphone, pill, language" section is below the
        // fold and never got captured — so the entry to microphone settings was never checked.
        case "voice-bottom": return .ok(id: "screen-04c-voice-bottom", nav: .module(.voiceToText))
        // Expanded "Microphone, pill, language": input selection and the level meter. The
        // collapsed section never showed them, so verdicts about them were made blind.
        case "voice-advanced": return .ok(id: "screen-04d-voice-advanced", nav: .module(.voiceToText))
        case "applauncher": return .ok(id: "screen-05-applauncher", nav: .module(.appLauncher))
        case "snippets":    return .ok(id: "screen-06-snippets", nav: .snippets)
        case "settings":    return .ok(id: "screen-07-settings", nav: .settings)
        // The same screen with "Advanced" EXPANDED: the collapsed section hid the global hotkey
        // fields, backup, reset and wizard replay from capture.
        case "settings-advanced": return .ok(id: "screen-07b-settings-advanced", nav: .settings)
        case "custom":
            // The custom module screen exists only if there is at least one module.
            // Silently skipping is not allowed: that would be an uncovered surface nobody learns about.
            guard let first = CustomModuleStore.load().first else {
                return .noData(why: "в хранилище нет ни одного кастомного модуля")
            }
            return .ok(id: "screen-08-custom", nav: .custom(first.id))
        default:
            return .unknownKey
        }
    }
}
#endif
