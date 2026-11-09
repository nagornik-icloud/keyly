import AppKit
import Carbon.HIToolbox
import OSLog

/// The single primitive for synthetic text INPUT. Merges six diverged implementations from
/// LayoutSwitch / ErrorFix / CustomModules / Snippets / UndoAction / VoiceToText.
///
/// Scope of responsibility:
/// - **Does NOT decide whether inserting is allowed** — that's the secure gate
///   `CaretProbe.isSecureNow()` in the caller (the check must sit next to sending keys, not
///   inside the primitive: features make a network request between "allowed" and "sending");
/// - **Does NOT extract text** (Cmd+A/Cmd+C) — that's the features' own concern;
/// - **Does NOT protect against event tap re-entrancy** — the flags (`isInsertingSnippet`) and
///   `InputMonitor.suspend` live in `HotKeyManager`, because this is a property of the event
///   STREAM, not of a single insertion.
///
/// The default transport is **paste** ("always paste, one path"). `type(_:)` is kept solely
/// for live dictation: there text is appended character by character as it's recognized, and
/// a paste per delta would flood clipboard managers' history with dozens of entries per phrase.
///
/// ⚠️ Differences between the old implementations are KEPT as explicit parameters, not
/// averaged out. They encode hard-won knowledge (see the docs on `Source` and `PasteStyle`),
/// and a change can only be verified in real use — so each caller still passes what it used
/// historically.
/// Clipboard policy: the clipboard here is a TRANSPORT, not storage, so it is given back.
///
/// The type is top-level and its ready-made policies are marked `nonisolated`: the module is
/// isolated to the main actor by default (Swift 6), and default arguments
/// (`clipboard: .restoring`) are evaluated outside the actor — otherwise there'd be a
/// concurrency warning on every call.
struct ClipboardPolicy {
    /// Restore the previous contents after pasting.
    var restore: Bool
    /// Pause before restoring — the target app must have time to process Cmd+V.
    /// Old implementations used anything from 0 (a race: restore overtook the paste) to 0.6 s.
    var settleDelay: TimeInterval
    /// Don't overwrite the clipboard if someone else wrote to it after us (`changeCount`).
    /// Only the voice implementation had this protection — it's correct, so it's the default.
    var guardAgainstForeignWrite: Bool
    /// Wait for the restore in a DETACHED task, returning control right after sending Cmd+V.
    ///
    /// Needed where the caller SWALLOWS user input while it works: while
    /// `HotKeyManager.isInsertingSnippet` is raised, the event tap destroys live keystrokes (they
    /// are not buffered). Holding the flag another 0.6 s just to give the clipboard back = losing
    /// characters from someone who kept typing. `settleDelay` is about the clipboard, not about
    /// the user's right to type — the two must not be glued into one wait.
    var detachRestore: Bool = false

    /// Default based on the best old implementation (voice): a generous window + foreign-write guard.
    nonisolated static let restoring = ClipboardPolicy(restore: true, settleDelay: 0.6, guardAgainstForeignWrite: true)
    /// Same, but doesn't hold up the caller (snippets: the input blocker is lifted right after).
    nonisolated static let restoringDetached = ClipboardPolicy(restore: true, settleDelay: 0.6,
                                                   guardAgainstForeignWrite: true, detachRestore: true)
    /// The result intentionally stays on the clipboard (module with "copy result").
    nonisolated static let keepResult = ClipboardPolicy(restore: false, settleDelay: 0, guardAgainstForeignWrite: false)
}

@MainActor
enum TextInjector {


    // MARK: - Parameters that encode knowledge

    /// Event source. Old implementations split exactly in half, and the difference is NOT cosmetic:
    /// `.combinedSessionState` inherits the session's real modifier state — if the user is still
    /// holding the hotkey modifiers, they can leak into the synthetic keystroke and turn Cmd+V
    /// into another combo. `.hidSystemState` is further from that.
    /// Unifying them is a separate task with a run across a matrix of apps, not done blind.
    enum Source {
        case hidSystem          // LayoutSwitch, ErrorFix, CustomModules
        case combinedSession    // Snippets, UndoAction, VoiceToText

        var cgSource: CGEventSource? {
            CGEventSource(stateID: self == .hidSystem ? .hidSystemState : .combinedSessionState)
        }
    }

    /// How Cmd is pressed when pasting.
    /// `.physicalCommandKey` sends a real Cmd key press around V — voice does this, and it's a
    /// more "honest" emulation: some apps (Electron, terminals) react only to it.
    /// `.commandFlag` only sets the flag on the V event — shorter and enough for native fields.
    enum PasteStyle {
        case commandFlag
        case physicalCommandKey
    }


    // MARK: - Paste

    /// Puts text on the clipboard, sends Cmd+V and (per policy) restores the previous clipboard contents.
    @discardableResult
    static func paste(_ text: String,
                      source: Source,
                      style: PasteStyle = .commandFlag,
                      clipboard: ClipboardPolicy = .restoring,
                      settleBeforeSend: TimeInterval = 0,
                      context: String) async -> Bool {
        guard !text.isEmpty else { return false }
        let pb = NSPasteboard.general
        let snapshot = clipboard.restore ? ClipboardManager.snapshot() : nil

        ClipboardManager.write(text, transient: clipboard.restore)
        let changeAfterWrite = pb.changeCount
        if settleBeforeSend > 0 {
            try? await Task.sleep(nanoseconds: UInt64(settleBeforeSend * 1_000_000_000))
        }

        await postPaste(source: source, style: style)
        Log.info(.input, "paste[\(context)]: \(text.count) симв., style=\(style)")

        guard let snapshot else { return true }
        if clipboard.detachRestore {
            // Return control immediately — the caller lifts its input blocker without waiting for the clipboard.
            Task { await settleAndRestore(snapshot, expecting: changeAfterWrite, policy: clipboard, context: context) }
        } else {
            await settleAndRestore(snapshot, expecting: changeAfterWrite, policy: clipboard, context: context)
        }
        return true
    }

    private static func settleAndRestore(_ snapshot: PasteboardSnapshot,
                                         expecting changeAfterWrite: Int,
                                         policy: ClipboardPolicy,
                                         context: String) async {
        if policy.settleDelay > 0 {
            try? await Task.sleep(nanoseconds: UInt64(policy.settleDelay * 1_000_000_000))
        }
        // The clipboard is no longer ours → someone (the user, a clipboard manager) wrote theirs.
        // Overwriting it is not allowed: our "restore the previous" would turn into losing their data.
        if policy.guardAgainstForeignWrite && NSPasteboard.general.changeCount != changeAfterWrite {
            Log.warn(.input, "paste[\(context)]: буфер перезаписан извне — восстановление пропущено")
        } else {
            ClipboardManager.restore(snapshot)
        }
    }

    private static func postPaste(source: Source, style: PasteStyle) async {
        let src = source.cgSource
        let v = CGKeyCode(kVK_ANSI_V)
        switch style {
        case .commandFlag:
            await sendKey(v, flags: .maskCommand, source: source)
        case .physicalCommandKey:
            let cmd = CGKeyCode(kVK_Command)
            CGEvent(keyboardEventSource: src, virtualKey: cmd, keyDown: true)?.post(tap: .cghidEventTap)
            let down = CGEvent(keyboardEventSource: src, virtualKey: v, keyDown: true)
            down?.flags = .maskCommand
            down?.post(tap: .cghidEventTap)
            let up = CGEvent(keyboardEventSource: src, virtualKey: v, keyDown: false)
            up?.flags = .maskCommand
            up?.post(tap: .cghidEventTap)
            CGEvent(keyboardEventSource: src, virtualKey: cmd, keyDown: false)?.post(tap: .cghidEventTap)
        }
    }

    // MARK: - Keys

    /// One key press. `hold` is the pause between down and up: native fields are fine with zero,
    /// but some apps drop instant presses, so the historical 12 ms default is kept.
    static func sendKey(_ key: CGKeyCode,
                        flags: CGEventFlags = [],
                        source: Source,
                        hold: TimeInterval = 0.012,
                        after: TimeInterval = 0.006) async {
        let src = source.cgSource
        if let down = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: true) {
            down.flags = flags
            down.post(tap: .cghidEventTap)
        }
        if hold > 0 { try? await Task.sleep(nanoseconds: UInt64(hold * 1_000_000_000)) }
        if let up = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: false) {
            up.flags = flags
            up.post(tap: .cghidEventTap)
        }
        if after > 0 { try? await Task.sleep(nanoseconds: UInt64(after * 1_000_000_000)) }
    }

    // MARK: - Backspace

    /// Deletes `count` characters left of the caret.
    /// - `perKeyDelay` — throttling between presses (snippets used 10 ms);
    /// - `settle` — a total pause AFTER the burst: events go through one FIFO queue, but slow
    ///   apps need headroom to apply all deletions BEFORE the next insertion.
    static func deleteBackward(_ count: Int,
                               source: Source,
                               perKeyDelay: TimeInterval = 0,
                               settle: TimeInterval = 0) async {
        guard count > 0 else { return }
        let src = source.cgSource
        let key = CGKeyCode(kVK_Delete)
        for _ in 0..<count {
            CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: true)?.post(tap: .cghidEventTap)
            CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: false)?.post(tap: .cghidEventTap)
            if perKeyDelay > 0 { try? await Task.sleep(nanoseconds: UInt64(perKeyDelay * 1_000_000_000)) }
        }
        if settle > 0 { try? await Task.sleep(nanoseconds: UInt64(settle * 1_000_000_000)) }
    }

    // MARK: - Unicode typing (live dictation only)

    /// Types text as Unicode events WITHOUT touching the clipboard.
    ///
    /// ⚠️ Not a general-purpose transport ("always paste"). The reason for the restriction was
    /// learned the hard way with voice: a synthetic newline in terminal fields (Claude Code etc.)
    /// means "send", so typing text with `\n` there broke off at the first newline. Paste goes
    /// through bracketed paste and inserts newlines literally. So typing is acceptable only for
    /// flat text without `\n` — which is exactly what live dictation deltas are.
    static func type(_ text: String, source: Source) {
        guard !text.isEmpty else { return }
        // Not an assert: user text can legitimately arrive here (converting a selected paragraph),
        // and crashing the app over a broken contract is worse than degrading.
        if text.contains("\n") {
            Log.warn(.input, "type(): текст с переносами — в терминал-полях они сработают как «отправить»; нужен paste")
        }
        let src = source.cgSource
        // keyboardSetUnicodeString reliably carries ~16 characters per event — long text is split into chunks.
        for chunk in Array(text.utf16).chunked(into: 16) {
            guard let down = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: true),
                  let up = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: false) else { continue }
            chunk.withUnsafeBufferPointer { buf in
                guard let base = buf.baseAddress else { return }
                down.flags = []
                up.flags = []
                down.keyboardSetUnicodeString(stringLength: buf.count, unicodeString: base)
                up.keyboardSetUnicodeString(stringLength: buf.count, unicodeString: base)
            }
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
        }
    }
}

private extension Array {
    /// Splits the array into chunks of `size` elements (the last one may be shorter).
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}
