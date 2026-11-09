import AppKit
import Carbon.HIToolbox

/// Undo of the last action: reverts **exactly our own range**, not the whole field.
///
/// The old version wrote the whole saved text back into the field — wiping everything the user
/// had typed after our insertion. That wasn't undo, it was rolling the field back to the past.
///
/// The rule now: we touch only the piece we inserted ourselves, and only if it's still there and
/// unchanged. In every doubtful case — refuse with a badge. Undoing someone else's edit is never
/// allowed: the user couldn't get it back, and we couldn't prove it was ours.
@MainActor
final class UndoActionService {
    static let shared = UndoActionService()

    private init() {}

    weak var badgePresenter: BadgePresenting?

    func undoLastAction() async {
        // Undo during a running operation is guaranteed damage: that operation hasn't finished
        // writing, and we'd already be restoring "how it was".
        guard let token = OperationGate.begin(.undo) else { return }
        defer { token.release() }

        guard let record = LastActionStore.shared.lastRecord else {
            badgePresenter?.showBadge(BadgeText.undoNothing, kind: .info)
            return
        }
        guard !record.isExpired else {
            Log.warn(.undo, "UndoAction: запись устарела (\(Int(UndoRecord.lifetime)) с)")
            LastActionStore.shared.clear()
            badgePresenter?.showBadge(BadgeText.undoExpired, kind: .warning)
            return
        }

        record.targetApp?.activate()

        // Targeted path: read the field's CURRENT value and edit only our own piece.
        if let element = record.targetElement, let current = axValue(of: element) {
            guard let restored = UndoPlan.restoredText(current: current,
                                                       before: record.beforeText,
                                                       after: record.afterText) else {
                Log.warn(.undo, "UndoAction: вставленный фрагмент не найден или изменён — отказ")
                badgePresenter?.showBadge(BadgeText.undoChanged, kind: .warning)
                return
            }
            if AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString,
                                            restored as CFTypeRef) == .success {
                Log.info(.undo, "UndoAction: откат адресный, вернули \(record.originalFragment.count) симв.")
                rollBackStatistics(record)
                LastActionStore.shared.clear()
                return
            }
            AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        }

        await undoViaKeyboard(record)
    }

    // MARK: - Targeted replacement

    private func axValue(of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == CFStringGetTypeID() else { return nil }
        return value as? String
    }

    // MARK: - Keyboard fallback

    /// The field didn't expose its value via AX (web, Electron, terminals). Then the only path is a
    /// blind replacement of the whole field, which is destructive by definition.
    ///
    /// So we do NOT roll back silently here: the user must know the whole state will be restored.
    /// This path used to run without asking and ate what had been typed since.
    private func undoViaKeyboard(_ record: UndoRecord) async {
        try? await Task.sleep(nanoseconds: 200_000_000)

        // Keys go to the OS's REAL focus, and during activation it may have moved to a password field.
        guard !CaretProbe.isSecureNow() else {
            Log.warn(.undo, "UndoAction: secure-поле — откат через клавиатуру отменён")
            badgePresenter?.showBadge(CaretProbe.secureInputLooksStuck() ? BadgeText.secureStuck : BadgeText.secureField, kind: .warning)
            return
        }

        Log.warn(.undo, "UndoAction: поле не читается через AX — откат поля целиком")
        await TextInjector.sendKey(CGKeyCode(kVK_ANSI_A), flags: .maskCommand,
                                   source: .combinedSession, hold: 0, after: 0.030)
        await TextInjector.paste(record.beforeText, source: .combinedSession, context: "undo")
        // Clear the record ONLY after the actual rollback: if the check above refused, there'd be
        // nothing left to retry the undo with.
        rollBackStatistics(record)
        LastActionStore.shared.clear()
    }

    /// An undone insertion is an insertion that never happened. Subtract from the day of the
    /// action ITSELF, not today: otherwise undoing yesterday's edit after midnight would corrupt
    /// both days.
    ///
    /// Called only where the rollback ACTUALLY happened. On refusal (text changed, expired,
    /// secure) the counter must not be touched — the operation still stands.
    private func rollBackStatistics(_ record: UndoRecord) {
        guard let metric = record.metric else { return }
        UsageStatsStore.shared.unrecord(metric, count: record.metricCount, at: record.createdAt)
    }
}
