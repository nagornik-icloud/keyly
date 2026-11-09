import Foundation
import Combine

/// Which hotkey field received a bare key RIGHT NOW.
///
/// Why a separate object instead of `@State` inside the field. The warning is wider than the
/// field itself (up to 360pt vs. 160–200), and while it lived inside the field's column, the
/// column stretched to fit it: in the launcher the field slid 200pt left from under the cursor,
/// in the snippet editor footer the neighboring triggers field shrank by 120pt. Both numbers
/// were measured with `launcher-row-*` and `snippet-footer-*` snapshot pairs.
///
/// Alignment can't fix this: for the message not to affect layout, it must be placed by
/// WHOEVER owns the layout — and it can't while the state is locked inside the field view.
/// So the state is lifted here, following `HotKeyRegistrationStatus`: the field writes it,
/// and the message can be drawn either by the field (default) or by the outer layout.
///
/// Lives until the screen goes away — by design, users learn about it once: there is no
/// permanent yellow line under every field anymore; `forget(fieldID:)` is called on disappear.
@MainActor
final class BareKeyNoticeStatus: ObservableObject {
    static let shared = BareKeyNoticeStatus()

    /// Field → shortcut assigned in it during this screen's lifetime.
    @Published private(set) var justAssigned: [String: KeyCombo] = [:]

    private init() {}

    func report(fieldID: String, combo: KeyCombo?) {
        guard justAssigned[fieldID] != combo else { return }
        justAssigned[fieldID] = combo
    }

    func forget(fieldID: String) {
        guard justAssigned[fieldID] != nil else { return }
        justAssigned[fieldID] = nil
    }

    /// Ready warning text for the field, or `nil` if there is nothing to warn about.
    ///
    /// The freshness rule lives in `BareKeyWarning.fresh`; here we only resolve catalog keys to
    /// a string: the argument is the macOS action name, or the key's own name if the app doesn't
    /// know the action.
    func message(fieldID: String?, combo: KeyCombo?) -> String? {
        guard let fieldID, let combo,
              let reason = BareKeyWarning.fresh(current: combo,
                                                justAssigned: justAssigned[fieldID]) else { return nil }
        return reason.messageKey.loc(reason.actionKey?.loc ?? combo.description)
    }
}
