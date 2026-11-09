import AppKit
import Carbon.HIToolbox

/// Fixes spelling and punctuation errors via an LLM.
@MainActor
final class ErrorFixer {
    static let shared = ErrorFixer()
    weak var statusAnimator: MenuBarAnimating?
    weak var errorPresenter: ErrorToastPresenting?
    weak var badgePresenter: BadgePresenting?

    /// The prompt is BUILT from the selected strictness level, not hard-coded. There used to be
    /// two fixed strings here, and the switch on the typo screen affected nothing — a phantom
    /// setting that, on top of that, silently changed voice behavior via a shared key.
    private static func systemPrompt(isFragment: Bool) -> String {
        ErrorFixLevel.current.systemPrompt(isFragment: isFragment)
    }

    private init() {}

    /// The model replied to the text instead of returning the fixed text. A separate type, not a
    /// generic error: the user must see the REASON ("the model answered"), otherwise they can't
    /// tell it from a network failure and will hit the same problem again without knowing why.
    enum ErrorFixFailure: Error { case modelAnswered }

    func run() async {
        // One text operation at a time. The lock is held by a TOKEN in defer: the LLM request
        // takes seconds, the hotkey gets pressed again meanwhile, and both operations share one
        // clipboard — the second overwrites the first one's snapshot, and its result is lost.
        guard let token = OperationGate.begin(.errorFix) else { return }
        defer { token.release() }
        await runClipboardPipeline()
    }

    /// Threshold for "long" text, in characters.
    private static let longTextThreshold = 2000

    /// Ask before processing long text. `true` means proceed.
    ///
    /// "Cancel" comes FIRST and is therefore the default: Enter pressed out of habit must not
    /// trigger rewriting a whole email.
    private func confirmLongText(_ characters: Int) -> Bool {
        let alert = NSAlert()
        alert.messageText = "errorfix.longText.title".loc
        alert.informativeText = "errorfix.longText.body".loc(characters)
        alert.addButton(withTitle: "common.cancel".loc)
        alert.addButton(withTitle: "errorfix.longText.proceed".loc)
        return alert.runModal() == .alertSecondButtonReturn
    }

    // MARK: - Pipeline

    private func runClipboardPipeline() async {
        // Secure field (password): nothing may be extracted — the text would go to the LLM over the network.
        guard !CaretProbe.isSecureNow() else {
            Log.warn(.errorFix, "ErrorFixer: secure-поле — исправление отменено, текст не извлекаем")
            badgePresenter?.showBadge(CaretProbe.secureInputLooksStuck() ? BadgeText.secureStuck : BadgeText.secureField, kind: .warning)
            return
        }

        // No key — refuse BEFORE touching the clipboard or showing progress. The check used to
        // sit inside the model call: the app would copy the text, show "Fixing…", and only
        // then say it had nothing to fix with. From outside that reads as a breakage, not as
        // an unconfigured module.
        guard APIKeyStore.shared.entry(for: APIKeyStore.shared.currentSelection(for: .errorFix)) != nil else {
            Log.warn(.errorFix, "ErrorFixer: ключа нет — исправление не начато")
            badgePresenter?.showBadge(BadgeText.errorFixNeedsKey, kind: .warning)
            return
        }

        // No network — say so immediately instead of waiting for the 60 s timeout: a minute of
        // "Fixing…" with no result reads as a frozen app.
        guard !NetworkReachability.shared.isDefinitelyOffline else {
            Log.warn(.errorFix, "ErrorFixer: сети нет — исправление не начато")
            badgePresenter?.showBadge(BadgeText.offline, kind: .warning)
            return
        }

        let snapshot = ClipboardManager.snapshot()
        // Normally the clipboard is just transport and gets restored. Exception: when pasting
        // failed and the result was deliberately HANDED to the user via the clipboard — then
        // restoring would wipe it.
        var keepClipboardResult = false
        defer { if !keepClipboardResult { ClipboardManager.restore(snapshot) } }

        let focusedApp = NSWorkspace.shared.frontmostApplication
        let focusedElement = captureFocusedElement()

        let original: String
        let isFragment: Bool
        switch await selectAllAndCopyText() {
        case .fragment(let text):
            original = text; isFragment = true
        case .wholeField(let text):
            original = text; isFragment = false
        case .notEditable:
            // A specific reason that hints what to do — "couldn't read" would be a lie here:
            // there was NOTHING to read from, there is no field.
            Log.warn(.errorFix, "ErrorFixer: поля нет — исправлять нечего")
            badgePresenter?.showBadge(BadgeText.noTextField, kind: .warning)
            return
        case .failed:
            Log.error(.errorFix, "ErrorFixer: не удалось скопировать текст")
            badgePresenter?.showBadge(BadgeText.readFailed, kind: .warning)
            return
        }

        // Long text is confirmed BEFORE sending. The reason isn't money but irreversibility: a
        // hotkey pressed in a long email rewrites all of it, and the user finds out only after
        // everything has been replaced.
        if original.count > Self.longTextThreshold, !confirmLongText(original.count) {
            Log.info(.errorFix, "ErrorFixer: длинный текст (\(original.count)) — человек отказался")
            return
        }

        statusAnimator?.beginMenuAnimation()
        badgePresenter?.showBadge(BadgeText.fixing, kind: .progress)
        defer {
            statusAnimator?.endMenuAnimation()
            // ONLY the progress badge: "Fixing… → No errors found" happens synchronously, and an
            // unconditional hide would kill the message shown just below in the same frame.
            badgePresenter?.hideBadge(onlyIf: .progress)
        }

        guard let fixed = await produceFixedText(original, isFragment: isFragment) else {
            Log.warn(.errorFix, "ErrorFixer: не получили исправленный текст")
            return
        }

        // Cancel by Esc is NON-DESTRUCTIVE. The flag is checked here because this is where the
        // seconds pass — between sending to the model and its answer. `cancelledNow()` used to be
        // called from NOWHERE: Esc showed "Cancelled", the operation finished anyway and replaced
        // the text. That's worse than having no cancel at all — the app promised one thing and
        // did another.
        //
        // Bail out BEFORE any synthetic keystroke: once posted, events are in the OS queue and
        // can't be recalled, so the only honest point to refuse is before sending.
        guard !OperationGate.cancelledNow() else {
            Log.info(.errorFix, "ErrorFixer: отменено по Esc до вставки — текст не тронут")
            return
        }

        // A before/after pair: undo uses it to find ITS piece and revert only that, without
        // touching what the user types later.
        LastActionStore.shared.record(before: original, after: fixed,
                                      element: focusedElement, app: focusedApp,
                                      metric: .errorsFixed)
        // A network LLM request (seconds) happened between the entry check and this paste — focus
        // may have moved to a password field. Pasting the model's answer there = overwriting
        // the password being typed.
        guard !CaretProbe.isSecureNow() else {
            Log.warn(.errorFix, "ErrorFixer: secure-поле — вставка отменена, результат отдан в буфер")
            // Put the result on the clipboard FIRST, then exit: otherwise the outer defer rolls
            // the clipboard back, and the model's answer (real money and seconds of waiting)
            // vanishes without a trace — the log used to claim otherwise while the text was gone.
            ClipboardManager.write(fixed)
            keepClipboardResult = true
            badgePresenter?.showBadge(BadgeText.secureBuffered, kind: .warning)
            return
        }
        // The defer above restores the clipboard (its snapshot was taken BEFORE extraction and
        // holds the user's real clipboard), so paste does not restore here — otherwise it would
        // bring back the intermediate content grabbed by Cmd+C.
        await TextInjector.paste(fixed, source: .hidSystem, clipboard: .keepResult,
                                 settleBeforeSend: 0.030, context: "errorFix")
        // Pause BEFORE exiting: otherwise the deferred restore races ahead of the target app
        // handling Cmd+V, and the old clipboard content gets pasted instead of the fixed text.
        try? await Task.sleep(nanoseconds: 600_000_000)
        // Count AFTER the actual paste: "got the model's answer" and "text fixed for the user"
        // are different events, and stats must reflect the latter.
        UsageStatsStore.shared.record(.errorsFixed)
        Log.info(.errorFix, "ErrorFixer: текст исправлен")
    }

    private func captureFocusedElement() -> AXUIElement? {
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
        return unsafeBitCast(focused, to: AXUIElement.self)
    }

    /// Reads the selection WITHOUT destroying it: `kAXSelectedText` is a pure read, no keys.
    /// Works in native fields; in Electron and the web the attribute is often empty, so this is
    /// only the first, cheapest attempt.
    private func selectionViaAX() -> String? {
        guard let element = captureFocusedElement() else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &value) == .success,
              let text = value as? String else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : text
    }

    /// Tries to copy the CURRENT selection with a single Cmd+C, no Cmd+A.
    /// No selection → the clipboard doesn't change, which `changeCount` shows; a selection →
    /// it stays active, and the following paste replaces exactly it.
    private func copyExistingSelection() async -> String? {
        guard !CaretProbe.isSecureNow() else { return nil }
        let pb = NSPasteboard.general
        let initial = ClipboardManager.read()
        let startCount = pb.changeCount
        await TextInjector.sendKey(CGKeyCode(kVK_ANSI_C), flags: .maskCommand, source: .hidSystem)
        let copied = await ClipboardManager.waitForNewText(startCount: startCount,
                                                           initialText: initial,
                                                           timeout: 0.35,
                                                           pollInterval: 0.03,
                                                           resendInterval: 0,
                                                           resend: {})
        guard let copied, !copied.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return copied
    }

    /// Takes text while RESPECTING the user's selection.
    ///
    /// Cmd+A used to be sent unconditionally: the selection wasn't just ignored — it was
    /// destroyed, and fixing one word in an email turned into rewriting the whole email.
    /// Attempts go from non-destructive to destructive:
    ///   1. `kAXSelectedText` — a read with no synthetic keys at all;
    ///   2. a single Cmd+C — where AX doesn't expose the selection (Electron, web);
    ///   3. only then Cmd+A + Cmd+C — "no selection, take the whole field".
    ///
    /// Also returns the FRAGMENT flag: the prompt depends on it. A selected piece inside a
    /// sentence can't be polished as standalone text — the model would capitalize it and add
    /// a final period.
    private func selectAllAndCopyText() async -> TextSource {
        if let selected = selectionViaAX() {
            Log.info(.errorFix, "ErrorFixer: взято выделение через AX, длина \(selected.count), промпт=фрагмент")
            return .fragment(selected)
        }
        if let selected = await copyExistingSelection() {
            Log.info(.errorFix, "ErrorFixer: взято выделение через Cmd+C, длина \(selected.count), промпт=фрагмент")
            return .fragment(selected)
        }
        // Cmd+A is DESTRUCTIVE: in plain web page text it selects the whole page (seen in
        // Safari: click into article text → the entire page got selected).
        // So "take the whole field" is allowed only when editability is PROVEN — tiers
        // .caret/.editable. Tier .ambiguous (AX is silent, the app is merely on the list of text
        // apps) is not proof: that's exactly the tier behind a browser page.
        //
        // A caret is not editability, and the cost of error is asymmetric here — a refusal
        // costs one more key press, a false positive wipes someone's text.
        let probe = CaretProbe.resolve(context: "errorFix.selectAll")
        guard probe.isEditable else {
            Log.warn(.errorFix, "ErrorFixer: Cmd+A запрещён — редактируемость не доказана (\(probe.confidence))")
            return .notEditable
        }
        Log.info(.errorFix, "ErrorFixer: выделения нет — берём всё поле (Cmd+A), промпт=всё поле")
        guard let whole = await selectWholeFieldAndCopy() else { return .failed }
        return .wholeField(whole)
    }

    /// Where the text came from. A separate type, not `String?`, for two reasons: the prompt
    /// depends on the source (a fragment can't be polished as a standalone sentence), and the
    /// failures differ — "no field" and "couldn't read" need different badges.
    private enum TextSource {
        case fragment(String)
        case wholeField(String)
        case notEditable
        case failed
    }

    private func selectWholeFieldAndCopy() async -> String? {
        let pb = NSPasteboard.general
        let initial = ClipboardManager.read()

        for attempt in 1...2 {
            // Retries span almost 2 s — focus may have moved to a password field AFTER the entry check.
            guard !CaretProbe.isSecureNow() else {
                Log.warn(.errorFix, "ErrorFixer: secure-поле на попытке \(attempt) — копирование прервано")
                return nil
            }
            // Cancel is checked INSIDE the retry loop, not just on entry: the loop spans almost
            // 2 seconds, and Esc pressed in the middle must stop sending keys immediately, not
            // after the last attempt.
            guard !OperationGate.cancelledNow() else {
                Log.info(.errorFix, "ErrorFixer: отменено по Esc на попытке \(attempt)")
                return nil
            }
            Log.warn(.errorFix, "ErrorFixer: Cmd+A / Cmd+C, попытка \(attempt)")
            await TextInjector.sendKey(CGKeyCode(kVK_ANSI_A), flags: .maskCommand, source: .hidSystem)
            try? await Task.sleep(nanoseconds: 60_000_000)

            let startCount = pb.changeCount
            await TextInjector.sendKey(CGKeyCode(kVK_ANSI_C), flags: .maskCommand, source: .hidSystem)
            try? await Task.sleep(nanoseconds: 80_000_000)

            if let copied = await ClipboardManager.waitForNewText(
                startCount: startCount,
                initialText: initial,
                timeout: 0.9,
                pollInterval: 0.03,
                resendInterval: 0.2,
                resend: {
                    guard !CaretProbe.isSecureNow() else { return }
                    await TextInjector.sendKey(CGKeyCode(kVK_ANSI_C), flags: .maskCommand, source: .hidSystem)
                }
            ), !copied.isEmpty {
                return copied
            }
        }
        return nil
    }

    private func produceFixedText(_ original: String, isFragment: Bool) async -> String? {
        do {
            let fixed = try await fixTextViaLLM(original, isFragment: isFragment)
            guard fixed != original else {
                Log.info(.errorFix, "ErrorFixer: текст не изменился, пропускаем вставку")
                badgePresenter?.showBadge(BadgeText.noErrorsFound, kind: .info)
                return nil
            }
            return fixed
        } catch ErrorFixFailure.modelAnswered {
            // The user's field stays untouched — that's the correct outcome: their text matters
            // more than a failed fix.
            badgePresenter?.showBadge(BadgeText.polishAnswered, kind: .warning)
            return nil
        } catch APIKeyError.missingKey {
            APIKeyStore.shared.presentMissingKeyAlert()
            return nil
        } catch {
            Log.error(.errorFix, "ErrorFixer: ошибка LLM: \(LogSanitizer.sanitize(String(describing: error)))")
            presentError(error)
            return nil
        }
    }

    private func presentError(_ error: Error) {
        let store = APIKeyStore.shared
        let selection = store.currentSelection(for: .errorFix)
        let message = LLMErrorPresenter.userMessage(
            for: error,
            provider: selection.provider,
            model: store.model(for: .errorFix)
        )
        errorPresenter?.showErrorToast(message: message)
    }

    // MARK: - LLM

    /// Runs the text WITHOUT applying it to another app's field.
    ///
    /// A separate entry point, not a flag on `run()`: that one holds the operation lock,
    /// touches the clipboard and sends synthetic keys — all unnecessary and risky for a
    /// try-out inside our own window. `nil` means it failed; the reason is already logged.
    func previewFix(_ text: String) async -> String? {
        do {
            // isFragment: true — try exactly what the user typed, without inventing a capital
            // letter and a final period.
            return try await fixTextViaLLM(text, isFragment: true)
        } catch {
            Log.warn(.errorFix, "Проба исправления не удалась: \(LogSanitizer.sanitize(error.localizedDescription))")
            return nil
        }
    }

    private func fixTextViaLLM(_ text: String, isFragment: Bool) async throws -> String {
        let store = APIKeyStore.shared
        let selection = store.currentSelection(for: .errorFix)
        guard let entry = store.entry(for: selection) else {
            throw APIKeyError.missingKey
        }
        let model = store.model(for: .errorFix)

        // The user's text goes WRAPPED and WITHOUT instructions in the `user` role: the
        // `userPromptPrefix` appendix used to go there, so we ourselves told the model that
        // channel carries commands — exactly what had to be forbidden. Its promises moved
        // verbatim into the system prompt (`ErrorFixPrompt.text`).
        let userText = PromptGuardrails.fenced(text)
        let system = Self.systemPrompt(isFragment: isFragment)
        let answer: String
        switch entry.provider {
        case .openai:
            answer = try await OpenAIClient.complete(systemPrompt: system,
                                                     userText: userText,
                                                     model: model,
                                                     apiKey: entry.value)
        case .gemini:
            answer = try await GeminiClient.complete(prompt: system + "\n" + userText,
                                                     model: model,
                                                     apiKey: entry.value)
        }

        // THE STAKES ARE HIGHER HERE THAN IN VOICE: the fixed text REPLACES what the user wrote,
        // right in their field. A model answer that gets this far overwrites what they typed.
        // Select the phrase "write me an email about my vacation", press the hotkey — and
        // instead of fixed spelling the field now holds an email. The guard checks the result
        // and stops such a substitution.
        // Fences are stripped BEFORE judging and BEFORE returning: the model repeats them even
        // though the prompt says not to (seen in practice). Doubly important here — the answer
        // goes straight into the user's field, and our service lines would end up in their text.
        let clean = PromptGuardrails.unfenced(answer)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // An empty or whitespace-only answer is a failure, not "the text disappeared". Next comes
        // a paste into the user's FIELD, and an empty string would wipe what they wrote. The
        // OpenAI client filters only a strictly empty `content`; whitespace passes through — so
        // it has to be cut off here.
        guard !clean.isEmpty else {
            Log.warn(.errorFix, "ErrorFixer: модель вернула пустой ответ — поле не трогаем")
            throw ErrorFixFailure.modelAnswered
        }

        // Strictness by level. "Style" is the only level ALLOWED to change wording ("lightly
        // polish the wording", `ErrorFixLevel.style`), and it can't be judged like "spelling
        // only": reordering words for smoothness looks the same as an insertion, and an honest
        // edit would be rejected with an alarming message.
        let strictness: TextPolishGuard.Strictness =
            ErrorFixLevel.current == .style ? .reworded : .spellingOnly
        if case .rejected(let reason) = TextPolishGuard.judge(input: text, output: clean,
                                                              strictness: strictness) {
            Log.warn(.errorFix, "ErrorFixer: модель \(reason.explanation) вместо исправления — "
                              + "поле человека не трогаем")
            throw ErrorFixFailure.modelAnswered
        }
        // Return EXACTLY what was judged: "judge one thing, paste another" is a needless gap.
        return clean
    }

    // MARK: - Key simulation

}

