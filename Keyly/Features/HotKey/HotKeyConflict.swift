import Foundation

/// Who already holds the shortcut.
///
/// A conflict used to come back as a READY STRING — enough only to show a "taken" alert and
/// stop. The user then had to find the previous holder by hand among six places where
/// shortcuts are assigned and remove it there. Knowing who the holder is lets us offer
/// "Reassign" and do it for them.
///
/// The type does NOT localize: it carries a catalog key and an argument, and the UI layer
/// builds the text — like `BareKeyWarning`. That keeps it testable without a running app.
enum HotKeyConflictOwner: Equatable {

    /// Built-in modules get their OWN type, not `ModuleKind` from the UI layer: that one pulls
    /// in SwiftUI and the theme, and the conflict type would no longer be testable without a
    /// running app.
    enum Builtin: String, Equatable {
        case layoutSwitch
        case errorFix
        case voiceToText
    }

    enum Global: String, Equatable {
        case undo
        case snippetPalette
        case cheatsheet
    }

    case system
    case module(Builtin)
    /// Shortcuts that belong to no module: undo, snippet palette, cheatsheet.
    ///
    /// They used to be missing from the registry — and protection worked ONE WAY: a module's
    /// shortcut couldn't be taken, but anyone could take the palette's, including the
    /// neighboring field in the same section. And not silently: the second Carbon registration
    /// failed, and the loser was shown "Shortcut is taken by ANOTHER APP" — a false reason that
    /// sent the user hunting for a culprit outside, while Keyly itself held the shortcut one row
    /// above.
    case global(Global)
    case app(id: UUID, name: String)
    case customModule(id: UUID, name: String)
    case snippet(id: UUID, title: String)

    var messageKey: String {
        switch self {
        case .system:                return "hotkey.conflict.system"
        case .module(.layoutSwitch): return "hotkey.conflict.layout"
        case .module(.errorFix):     return "hotkey.conflict.errorFix"
        case .module(.voiceToText):  return "hotkey.conflict.voice"
        case .app:                   return "hotkey.conflict.app"
        case .customModule:          return "hotkey.conflict.module"
        case .snippet:               return "hotkey.conflict.snippet"
        case .global:                return "hotkey.conflict.global"
        }
    }

    /// Name of the holding feature, for the message argument. Built-in modules are named right
    /// in the message text — nothing to insert for them.
    var argument: String? {
        switch self {
        case .system, .module:                return nil
        case .app(_, let name):               return name
        case .customModule(_, let name):      return name
        case .snippet(_, let title):          return title
        // Names of the three global shortcuts are catalog keys, resolved by the UI layer like
        // the other arguments. Dedicated strings, not the menu ones: in a conflict the user
        // needs to recognize the FEATURE they are taking the keys from.
        case .global(.undo):                  return "menu.undo"
        case .global(.snippetPalette):        return "cheatsheet.palette"
        case .global(.cheatsheet):            return "settings.globalHotkeys.cheatsheet"
        }
    }

    /// Whether the shortcut can be taken from its holder. Not from the system: there is nothing
    /// to free, and a "Reassign" button next to "⌘Q is taken by the system" would be a lie.
    var isReleasable: Bool {
        if case .system = self { return false }
        return true
    }
}

/// A live conflict on screen: WHERE to show it, WHO holds the shortcut, and what "Reassign" does.
///
/// Deliberately not `Equatable` — it carries a closure. There's no need to compare: there is
/// always only one conflict, the user assigns one shortcut at a time.
struct HotKeyConflict {
    let fieldID: String
    let owner: HotKeyConflictOwner
    /// Free the previous holder and assign the shortcut here.
    let apply: () -> Void
}
