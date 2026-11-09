import AppKit
import Carbon.HIToolbox

@MainActor
final class CustomModuleRunner {
    static let shared = CustomModuleRunner()
    weak var statusAnimator: MenuBarAnimating?
    weak var errorPresenter: ErrorToastPresenting?
    weak var badgePresenter: BadgePresenting?
    /// Floating popup for the "Show" output: the result touches neither the field nor the clipboard.
    weak var toastPresenter: VoiceErrorToastPresenting?

    private init() {}

    func run(module: CustomAIModule) async {
        guard module.isEnabled else { return }   // a switched-off module never runs
        // One text operation at a time — see the explanation in ErrorFixService.run().
        guard let token = OperationGate.begin(.module) else { return }
        defer { token.release() }
        // Field checks: the "only in a text field" flag used to exist in the UI but was ignored
        // at runtime, so a module could fire Cmd+A on the desktop or in Finder.
        // Sources that read from the field (select-all/copy) need the caret probe. The
        // clipboard source needs no focus, so the probe is skipped there — otherwise the
        // module would silently do nothing.
        if module.textSource != .clipboard {
            let caret = CaretProbe.resolve(context: "customModule:\(module.name)")
            // Secure field (password): text must NOT be extracted — it would leak to the
            // clipboard/LLM. This check is unconditional.
            guard !caret.blocksTextExtraction else {
                Log.warn(.modules, "CustomModule[\(module.name)]: secure-поле (пароль) — извлечение текста заблокировано")
                badgePresenter?.showBadge(BadgeText.secureField, kind: .warning, caretRect: caret.caretRect)
                return
            }
            // The "only in a text field" toggle is gone: users shouldn't have to know about
            // caret tiers, yet the setting required exactly that — off, the module silently
            // worked into nowhere; on, it refused in Electron fields where the tier is
            // unreachable anyway. Whether there is a field is detected automatically, and the
            // decision depends on the text SOURCE (below).
            // With the "selection" source and no field there is NOTHING to take, and no request
            // may be sent: the model would get empty input, return something, and the user
            // would pay for an answer to nothing. This check is SEPARATE from
            // `onlyInTextField`: that one is a user option, this one is a property of the source.
            if module.textSource == .selected, caret.isDefinitelyNotField {
                Log.warn(.modules, "CustomModule[\(module.name)]: источник «выделенное», поля нет — запрос не отправляем")
                badgePresenter?.showBadge(BadgeText.nothingToProcess, kind: .warning, caretRect: caret.caretRect)
                return
            }
        }

        let focusedApp = NSWorkspace.shared.frontmostApplication
        let focusedElement = captureFocusedElement()

        // Snapshot BEFORE capture: capturing copies the selection, so a snapshot taken later
        // would "restore" that selection instead of what the user had.
        let snapshot = ClipboardManager.snapshot()
        // Restored on every exit except when the result is deliberately left on the clipboard.
        var resultLeftInClipboard = false
        // Set after our own write; if the clipboard changed since, someone else wrote to it.
        var changeCountAfterOurWrite: Int?
        defer {
            let foreignWrite = changeCountAfterOurWrite.map { $0 != NSPasteboard.general.changeCount } ?? false
            if !resultLeftInClipboard, !foreignWrite { ClipboardManager.restore(snapshot) }
        }

        // Re-check BEFORE the synthetic Cmd+A/Cmd+C: they go to the OS's REAL keyboard focus, not
        // to the element the heuristic found above, and focus may have changed since resolve().
        if module.textSource != .clipboard, CaretProbe.isSecureNow() {
            Log.warn(.modules, "CustomModule[\(module.name)]: secure-контекст перед копированием — извлечение отменено")
            return
        }

        guard let original = await captureText(source: module.textSource) else {
            Log.error(.modules, "CustomModule[\(module.name)]: не удалось получить текст")
            // Cancelled by Esc or stopped at a password field — the user knows why; no badge.
            if !OperationGate.cancelledNow(), !CaretProbe.isSecureNow() {
                badgePresenter?.showBadge(BadgeText.nothingToProcess, kind: .warning)
            }
            return
        }

        let prompt = CustomAIModule.requestText(instruction: module.prompt, text: original)

        statusAnimator?.beginMenuAnimation()
        defer { statusAnimator?.endMenuAnimation() }

        do {
            let result = try await processText(prompt: prompt, moduleId: module.id)
            // Seconds pass between sending to the model and its answer — that's exactly when Esc
            // gets pressed "while it's thinking". Bail out BEFORE any synthetic keystroke: once
            // posted, events are in the OS queue and can't be recalled.
            guard !OperationGate.cancelledNow() else {
                Log.info(.modules, "CustomModule: отменено по Esc до применения — текст не тронут")
                return
            }
            // The undo record is made by `applyResult` — and ONLY if a paste actually happened.
            // It used to be written here, before applying: for a module with "to clipboard"
            // output, or when the secure check refused, history held an undo for an operation
            // that never happened, and ⌥⌘Z wiped a field we had never touched.
            resultLeftInClipboard = await applyResult(result, module: module, original: original,
                                                      element: focusedElement, app: focusedApp,
                                                      wrote: { changeCountAfterOurWrite = $0 })
        } catch APIKeyError.missingKey {
            APIKeyStore.shared.presentMissingKeyAlert()
        } catch {
            Log.error(.modules, "CustomModule[\(module.name)]: ошибка: \(LogSanitizer.sanitize(error.localizedDescription))")
            presentError(error, moduleId: module.id, moduleName: module.name)
        }
    }

    /// Try-out on SAMPLE text inside the Keyly window.
    ///
    /// Testing a prompt used to require switching to another app and risking real text: the
    /// module writes its result straight into the field, and a bad prompt ruined what was
    /// there. Nothing outside is touched here — neither focus nor clipboard.
    func preview(module: CustomAIModule, sample: String) async -> String? {
        let text = sample.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        do {
            return try await processText(prompt: CustomAIModule.requestText(instruction: module.prompt, text: text),
                                         moduleId: module.id)
        } catch {
            Log.warn(.modules, "CustomModule[\(module.name)]: проба не удалась — \(error.localizedDescription)")
            return nil
        }
    }

    private func presentError(_ error: Error, moduleId: UUID, moduleName: String) {
        let store = APIKeyStore.shared
        let selection = store.currentSelection(for: .customModule(moduleId))
        let detail = LLMErrorPresenter.userMessage(
            for: error,
            provider: selection.provider,
            model: store.model(for: .customModule(moduleId))
        )
        errorPresenter?.showErrorToast(message: "«\(moduleName)»: \(detail)")
    }

    private func captureFocusedElement() -> AXUIElement? {
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
        return unsafeBitCast(focused, to: AXUIElement.self)
    }

    // MARK: - Text capture

    private func captureText(source: CustomTextSource) async -> String? {
        let pb = NSPasteboard.general
        switch source {
        case .clipboard:
            let text = pb.string(forType: .string)
            return (text?.isEmpty == false) ? text : nil
        case .wholeWindow:
            return await selectAllAndCopy(pb: pb)
        case .selected:
            // No selection → Cmd+C leaves the clipboard untouched; returning it would send
            // the user's previous clipboard (maybe a password) to the AI. Wait for a real copy.
            let initial = pb.string(forType: .string)
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
    }

    private func selectAllAndCopy(pb: NSPasteboard) async -> String? {
        let initial = pb.string(forType: .string)
        for attempt in 1...2 {
            // The retry also sends keys to the CURRENT OS focus — re-check on every attempt.
            guard !CaretProbe.isSecureNow() else {
                Log.warn(.modules, "CustomModule: secure-поле на попытке \(attempt) — копирование прервано")
                return nil
            }
            // Cancel is checked on EVERY attempt, not just on entry: the loop takes time, and
            // Esc in the middle must stop sending keys immediately.
            guard !OperationGate.cancelledNow() else {
                Log.info(.modules, "CustomModule: отменено по Esc на попытке \(attempt)")
                return nil
            }
            await TextInjector.sendKey(CGKeyCode(kVK_ANSI_A), flags: .maskCommand, source: .hidSystem)
            try? await Task.sleep(nanoseconds: 60_000_000)
            let startCount = pb.changeCount
            await TextInjector.sendKey(CGKeyCode(kVK_ANSI_C), flags: .maskCommand, source: .hidSystem)
            try? await Task.sleep(nanoseconds: 80_000_000)
            if let copied = CopyDetection.freshText(pb.string(forType: .string),
                                                    startCount: startCount,
                                                    currentCount: pb.changeCount,
                                                    initialText: initial) {
                return copied
            }
            Log.warn(.modules, "CustomModule: попытка \(attempt) не дала текст")
        }
        return nil
    }

    // MARK: - Apply result

    /// Returns true when the result is deliberately left on the clipboard (the caller then
    /// must not restore the user's clipboard over it).
    private func applyResult(_ text: String, module: CustomAIModule, original: String,
                             element: AXUIElement?, app: NSRunningApplication?,
                             wrote: (Int) -> Void) async -> Bool {
        switch module.output {
        case .panel:
            toastPresenter?.showVoiceInfoToast(message: text)
            return false

        case .copy:
            ClipboardManager.write(text)
            badgePresenter?.showBadge(BadgeText.resultCopied, kind: .info)
            return true

        case .insert:
            // The LLM request takes seconds — focus may have moved to a password field. The
            // model's answer must not be pasted there: it would corrupt the password being typed
            // (and end up in the password manager as its value).
            guard !CaretProbe.isSecureNow() else {
                Log.warn(.modules, "CustomModule[\(module.name)]: secure-контекст — авто-вставка отменена, результат в буфере")
                ClipboardManager.write(text)
                badgePresenter?.showBadge(BadgeText.resultBuffered, kind: .warning)
                return true
            }
            // No field — nowhere to paste. The result stays on the clipboard, and we SAY so:
            // silently switching the destination means losing the result.
            guard CaretProbe.resolve(context: "module.insert").isEditable else {
                Log.info(.modules, "CustomModule[\(module.name)]: поля нет — результат в буфере")
                ClipboardManager.write(text)
                badgePresenter?.showBadge(BadgeText.resultBuffered, kind: .warning)
                return true
            }
            ClipboardManager.write(text, transient: true)   // restored right after the paste
            wrote(NSPasteboard.general.changeCount)
            await TextInjector.sendKey(CGKeyCode(kVK_ANSI_V), flags: .maskCommand, source: .hidSystem)
            LastActionStore.shared.record(before: original, after: text, element: element, app: app)
            // Let the target app read the paste before the clipboard is restored under it.
            try? await Task.sleep(nanoseconds: 600_000_000)
            return false
        }
    }

    // MARK: - LLM

    private func processText(prompt: String, moduleId: UUID) async throws -> String {
        let store = APIKeyStore.shared
        let selection = store.currentSelection(for: .customModule(moduleId))
        guard let entry = store.entry(for: selection) else {
            throw APIKeyError.missingKey
        }
        let model = store.model(for: .customModule(moduleId))

        let systemPrompt = CustomAIModule.systemPrompt
        switch entry.provider {
        case .openai:
            return try await OpenAIClient.complete(systemPrompt: systemPrompt,
                                                   userText: prompt,
                                                   model: model,
                                                   apiKey: entry.value)
        case .gemini:
            return try await GeminiClient.complete(prompt: systemPrompt + "\n" + prompt,
                                                   model: model,
                                                   apiKey: entry.value)
        }
    }

}
