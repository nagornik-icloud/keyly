import Foundation

/// Why a module has a dot in the sidebar.
///
/// There used to be ONE dot meaning two different things: "module is off" and "module is on
/// but not fully set up". The label was the same too — "Needs setup". So the app alarmed about
/// something the user did ON PURPOSE, with no way to tell it from a real problem.
///
/// Now the states differ by color: off is red, incomplete is orange.
enum ModuleAttention: Equatable {
    /// Turned off by the master toggle. A deliberate user action, not a breakage.
    case disabled
    /// On, but can't work: no hotkey or no key.
    case incomplete
    /// All set — no dot.
    case none

    static func resolve(isEnabled: Bool, hasHotKey: Bool,
                        needsKey: Bool, hasKey: Bool) -> ModuleAttention {
        // "Off" is checked FIRST: for a disabled module a missing key means nothing, and
        // showing "incomplete" on top of "off" is noise.
        guard isEnabled else { return .disabled }
        if !hasHotKey { return .incomplete }
        if needsKey && !hasKey { return .incomplete }
        return .none
    }

    /// Catalog key for the label. The label must differ just like the color: otherwise the
    /// distinction lives only in color and is lost on anyone who can't tell colors apart.
    var labelKey: String? {
        switch self {
        case .disabled:   return "sidebar.moduleOff"
        case .incomplete: return "sidebar.needsSetup"
        case .none:       return nil
        }
    }
}
