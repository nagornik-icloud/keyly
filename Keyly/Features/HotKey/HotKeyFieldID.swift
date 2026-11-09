import Foundation

/// One naming scheme for hotkey fields.
///
/// The field id is needed by TWO layers at once: the screen shows a conflict and a "not
/// working" mark under the field, and `HotKeyManager` writes the registration result there.
/// Strings built in two places drift apart silently — the screen just stops showing anything
/// because the keys no longer match. So the names are built HERE, not at the call site.
enum HotKeyFieldID {
    static let layout = "module.layout"
    static let errorFix = "module.errorFix"
    static let voice = "module.voice"
    static let undo = "module.undo"
    static let snippetPalette = "module.snippetPalette"
    static let cheatsheet = "module.cheatsheet"

    static func app(_ id: UUID) -> String { "app.\(id)" }
    static func customModule(_ id: UUID) -> String { "custom.\(id)" }
    static func snippet(_ id: UUID) -> String { "snippet.\(id)" }
}
