import AppKit
import Carbon.HIToolbox
import CoreGraphics
@MainActor
final class SnippetService {
    static let shared = SnippetService()

    weak var badgePresenter: BadgePresenting?

    private init() {}

    /// Expands placeholders and puts the cursor where the cursor token was.
    ///
    /// The clipboard is read BEFORE the paste starts: the paste itself puts the snippet text on
    /// the clipboard, and reading it afterwards would return the snippet instead of what the
    /// user had copied.
    private func prepared(_ snippet: Snippet) -> SnippetPlaceholders.Expansion {
        guard SnippetPlaceholders.containsPlaceholders(snippet.content) else {
            return .init(text: snippet.content, caretOffset: nil)
        }
        return SnippetPlaceholders.expand(snippet.content,
                                          now: Date(),
                                          clipboard: NSPasteboard.general.string(forType: .string))
    }

    /// Moves the cursor from the end of the inserted text back to where the cursor token was.
    /// With left arrows, not by setting the position via Accessibility: the field may be
    /// non-editable per AX (web editors, Electron), where setting it silently fails, while
    /// arrows work anywhere typing works.
    private func moveCaretBack(by steps: Int) async {
        guard steps > 0 else { return }
        for _ in 0..<steps {
            await TextInjector.sendKey(CGKeyCode(kVK_LeftArrow), source: .combinedSession,
                                       hold: 0.004, after: 0.004)
        }
    }

    /// Insertion by hotkey/menu. Returns immediately — the clipboard restore catches up on its own
    /// (as before), so the signature stays synchronous and callers don't change.
    func insert(_ snippet: Snippet) {
        guard snippet.isEnabled, allowsInsertion(snippet) else { return }
        // The lock is needed here too, even though insertion is quick: it goes through the
        // clipboard, and overlapping with an in-flight LLM request overwrites that request's
        // snapshot. The token moves into the Task and lives exactly until the insertion ends.
        guard let token = OperationGate.begin(.snippet) else { return }
        Task {
            defer { token.release() }
            let expansion = prepared(snippet)
            // NOWHERE to insert — put it on the clipboard and say so. Otherwise Cmd+V goes to an
            // app with no input field: there it either does nothing or fires as some other
            // shortcut, and the user thinks the snippet is broken.
            guard CaretProbe.resolve(context: "snippet").isField else {
                ClipboardManager.write(expansion.text)
                Log.warn(.snippets, "Сниппет не вставлен: нет поля ввода — текст в буфере")
                badgePresenter?.showBadge(BadgeText.noFieldBuffered, kind: .warning)
                return
            }
            await TextInjector.paste(expansion.text, source: .combinedSession,
                                     clipboard: .restoringDetached, context: "snippet")
            if let offset = expansion.caretOffset {
                await moveCaretBack(by: expansion.text.count - offset)
            }
            UsageStatsStore.shared.record(.snippetsInserted)
        }
    }

    /// Insertion by trigger: first erase the typed trigger, then insert the text.
    /// 10 ms throttle per character — without it fast apps lose some of the deletions.
    /// `separator` is the separator that fired the trigger in "after separator" mode. We
    /// swallowed it, so WE must put it back: the user typed "addr␣", and text without the
    /// space would glue onto the next word.
    func insertWithTriggerDelete(snippet: Snippet, triggerLength: Int,
                                 separator: Character? = nil,
                                 holding heldToken: OperationGate.Token? = nil) async {
        guard let token = heldToken ?? OperationGate.begin(.snippet) else { return }
        defer { token.release() }
        guard snippet.isEnabled, allowsInsertion(snippet) else { return }
        await TextInjector.deleteBackward(triggerLength, source: .combinedSession, perKeyDelay: 0.010)
        let expansion = prepared(snippet)
        await TextInjector.paste(expansion.text, source: .combinedSession,
                                 clipboard: .restoringDetached, context: "snippet:trigger")
        // The separator goes AFTER the paste and BEFORE input suppression is lifted: otherwise
        // it either lands before the text or gets mixed into live typing.
        if let separator {
            TextInjector.type(String(separator), source: .combinedSession)
        }
        // Caret AFTER the separator: otherwise the separator would land at the cursor position,
        // i.e. in the middle of the text just inserted.
        if let offset = expansion.caretOffset {
            await moveCaretBack(by: expansion.text.count - offset + (separator == nil ? 0 : 1))
        }
        UsageStatsStore.shared.record(.snippetsInserted)
    }

    /// In secure input **all** text features are no-ops. Triggers won't fire in a secure field
    /// anyway (the OS silences the event tap), but hotkey insertion goes through Carbon and would.
    ///
    /// The "no input field" check (`.none`) is DELIBERATELY not applied here: menu bar insertion
    /// happens while our app is frontmost, so the probe would describe us rather than the target
    /// — the risk of breaking a working path outweighs the gain. Needs separate manual testing.
    private func allowsInsertion(_ snippet: Snippet) -> Bool {
        guard CaretProbe.isSecureNow() else { return true }
        Log.warn(.snippets, "Сниппет не вставлен: защищённое поле")
        badgePresenter?.showBadge(CaretProbe.secureInputLooksStuck() ? BadgeText.secureStuck : BadgeText.secureField, kind: .warning)
        return false
    }
}
