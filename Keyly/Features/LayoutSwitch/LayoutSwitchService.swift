import Cocoa
import Carbon.HIToolbox
import ApplicationServices

@MainActor
class TextSelector {
    /// Badge at the caret — the shared channel for short statuses. Set by `AppDelegate`.
    static weak var badgePresenter: BadgePresenting?

    static func selectWordToLeft(hotKeyEventTime: Date? = nil) {
        Task { @MainActor in
            await handleShortcut(hotKeyEventTime: hotKeyEventTime)
        }
    }

    // MARK: - Shortcut handling

    private static func handleShortcut(hotKeyEventTime: Date?) async {
        // One text operation at a time: layout switching retries the copy for up to ~3 s and
        // holds the clipboard the whole time — overlapping with any other operation ruins both.
        guard let token = OperationGate.begin(.layout) else { return }
        defer { token.release() }
        // Secure field (password): don't copy it to the clipboard — clipboard managers would pick
        // it up there. The OS already silences keyboard triggers in a secure context, but a
        // Carbon hotkey can still fire — so an explicit check is needed.
        guard !CaretProbe.isSecureNow() else {
            Log.warn(.layout, "TextSelector: secure-поле — конвертация раскладки отменена")
            badgePresenter?.showBadge(CaretProbe.secureInputLooksStuck() ? BadgeText.secureStuck : BadgeText.secureField, kind: .warning)
            return
        }

        let referenceDate = hotKeyEventTime ?? Date()
        let lookupDate = referenceDate.addingTimeInterval(-Timing.hotKeyGuardInterval)
        guard let lastEvent = InputMonitor.shared.lastRelevantEvent(before: lookupDate)
                              ?? InputMonitor.shared.lastRelevantEvent() else {
            Log.warn(.layout, "TextSelector: нет данных о последнем нажатии клавиш")
            return
        }

        InputMonitor.shared.suspend(for: Timing.monitorSuspendWindow)

        switch lastEvent.kind {
        case .selection:
            Log.info(.layout, "TextSelector: обнаружено выделение — конвертируем")
            await handleExistingSelection()
        case .character:
            let elapsed = Date().timeIntervalSince(lastEvent.timestamp)
            guard elapsed <= Timing.recentTypingWindow else {
                Log.warn(.layout, "TextSelector: символное нажатие было \(elapsed)s назад — пропускаем")
                return
            }
            Log.info(.layout, "TextSelector: конвертируем последнее слово")
            await handleLastWordRewrite()
        }
    }

    // MARK: - Scenario 1: existing selection

    private static func handleExistingSelection() async {
        // Via ClipboardManager, not `string(forType:)`: a hand-made snapshot takes ONLY text and
        // silently downgrades an image/RTF/file clipboard to a plain string.
        let snapshot = ClipboardManager.snapshot()
        guard let selected = await copySelection(), !selected.isEmpty else {
            Log.error(.layout, "TextSelector: не удалось получить выделенный текст")
            return
        }
        // Direction comes from the text ITSELF, not the current layout: the selection could have
        // been typed at any time in any layout (see detectLayout).
        let sourceLayout = resolveLayout(of: selected)
        let converted = convertKnowingLayout(selected, sourceLayout)
        await replaceSelection(with: converted)
        // Switch the system ONLY after a successful replacement: otherwise a failed copy would
        // leave the layout flipped and the text unfixed.
        switchLayout(from: sourceLayout)
        UsageStatsStore.shared.record(.layoutSwitches)
        ClipboardManager.restore(snapshot)
    }

    /// Conversion direction: from the text first (reliable), then from the current system
    /// layout (when the text has no letters — e.g. only punctuation).
    private static func resolveLayout(of text: String) -> LayoutMapper.Layout? {
        LayoutMapper.detectLayout(of: text) ?? KeyboardLayoutService.currentLayout()
    }

    /// Conversion with a known direction. Falls back to guessing only when a third layout is
    /// active or TIS returned nothing: then there's no way to know the direction.
    private static func convertKnowingLayout(_ text: String, _ layout: LayoutMapper.Layout?) -> String {
        guard let layout else {
            Log.warn(.layout, "Раскладка вне пары RU/EN — конвертируем угадыванием (обратимость не гарантирована)")
            return LayoutMapper.convert(text)
        }
        return LayoutMapper.convert(text, from: layout)
    }

    /// Switches the system to the other side of the pair. If the layout isn't in the pair,
    /// the system is left alone: the old "next in cycle" sent it to an unrelated source.
    private static func switchLayout(from layout: LayoutMapper.Layout?) {
        guard let layout else { return }
        KeyboardLayoutService.switchToOpposite(of: layout)
    }

    // MARK: - Scenario 2: rewrite last word

    /// Word replacement in a terminal: erase what was typed and paste the converted text.
    ///
    /// Selection is physically impossible here — `Cmd+Shift+Left` goes to the shell as an
    /// escape sequence and prints as garbage (";2D" in practice). So we act like a person:
    /// backspace to the start of the word, then paste.
    ///
    /// PASTE, not per-character typing. The first version typed keys and produced a doubled,
    /// garbled word: a per-character stream takes tens of milliseconds, and both the shell's
    /// echo and the app's own events manage to squeeze in. A paste is one event — nothing can
    /// get in between.
    /// The pause after which typed text counts as a "previous thought". Nobody pauses two
    /// seconds inside a word; between commands they do.
    private static let typingGap: TimeInterval = 2.0

    private static func rewriteLastWordByRetyping() async {
        // Only what was typed CONTINUOUSLY: the buffer survives Enter and command changes, and
        // Enter isn't recorded in it at all — the previous line's text got glued to the fresh
        // word, and we erased eleven characters where the user had typed six.
        let typed = InputMonitor.shared.recentlyTypedCharacters(count: 64, maxGap: Self.typingGap)
        guard let word = TerminalTargets.lastTypedWord(in: typed) else {
            Log.warn(.layout, "TextSelector: терминал — в буфере ввода нет слова, отказ")
            badgePresenter?.showBadge(BadgeText.readFailed, kind: .warning)
            return
        }

        let sourceLayout = resolveLayout(of: word)
        let converted = convertKnowingLayout(word, sourceLayout)
        guard converted != word else {
            Log.info(.layout, "TextSelector: терминал — слово не меняется, ничего не делаем")
            return
        }

        // Suspend the monitor for the WHOLE operation, not just its start: our own backspaces
        // and paste go through the same event tap, and without this the input buffer would fill
        // with what we typed ourselves — the next press would convert the previous result.
        InputMonitor.shared.suspend(for: Timing.monitorSuspendWindow)
        InputMonitor.shared.clearBuffer()

        Log.info(.layout, "TextSelector: терминал — стираем \(word.count) симв., вставляем конвертированное")
        await TextInjector.deleteBackward(word.count, source: .hidSystem)
        // A physical Cmd key, not a flag: some terminals react only to that.
        _ = await TextInjector.paste(converted, source: .hidSystem,
                                     style: .physicalCommandKey, context: "layout:terminal")
        // The buffer must now reflect what's ON SCREEN, not what the user typed by hand. There
        // used to be a clearBuffer() here — and the next hotkey press found no data: conversion
        // became irreversible, and nothing happened on screen. In the log it showed up as
        // "no data about the last key press" about fifteen times in a row.
        InputMonitor.shared.seedTypedCharacters(converted)
        switchLayout(from: sourceLayout)
    }

    private static func handleLastWordRewrite() async {
        // A terminal can't "select the word to the left": the combo goes to the shell as an
        // escape sequence and prints as garbage (";2D" in practice). It has its own path.
        if TerminalTargets.isFrontmostTerminal() {
            await rewriteLastWordByRetyping()
            return
        }
        let snapshot = ClipboardManager.snapshot()
        await TextInjector.sendKey(CGKeyCode(kVK_LeftArrow), flags: [.maskCommand, .maskShift], source: .hidSystem)
        await sleepMicroseconds(Timing.selectionPause)

        guard let selectedText = await copySelection(), !selectedText.isEmpty else {
            Log.error(.layout, "TextSelector: не удалось забрать текст после Cmd+Shift+Left")
            await TextInjector.sendKey(CGKeyCode(kVK_RightArrow), source: .hidSystem)
            return
        }

        ClipboardManager.restore(snapshot)

        let reversed = String(selectedText.reversed())
        let hadTrailingSpace = reversed.first == " "
        let trimmed = hadTrailingSpace ? String(reversed.dropFirst()) : reversed
        let lastWordReversed = trimmed
            .split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false)
            .first.map(String.init) ?? ""

        guard !lastWordReversed.isEmpty else {
            Log.info(.layout, "TextSelector: не нашли последнее слово")
            await TextInjector.sendKey(CGKeyCode(kVK_RightArrow), source: .hidSystem)
            return
        }

        let word = String(lastWordReversed.reversed())
        let sourceLayout = resolveLayout(of: word)
        let converted = convertKnowingLayout(word, sourceLayout)

        // Build the new selection content: original prefix + converted last word + (optional
        // trailing space). The selection is still active — replaceSelection replaces it in one
        // call.
        let wordWithSpaceLen = word.count + (hadTrailingSpace ? 1 : 0)
        guard selectedText.count >= wordWithSpaceLen else {
            await TextInjector.sendKey(CGKeyCode(kVK_RightArrow), source: .hidSystem)
            return
        }
        let prefixEnd = selectedText.index(selectedText.endIndex, offsetBy: -wordWithSpaceLen)
        let prefix = String(selectedText[..<prefixEnd])
        let newText = prefix + converted + (hadTrailingSpace ? " " : "")

        Log.info(.layout, "TextSelector: конвертировано слово, \(word.count) симв.")  // the text itself is NOT logged
        await replaceSelection(with: newText)
        // Only after a successful replacement (see scenario 1).
        switchLayout(from: sourceLayout)
        UsageStatsStore.shared.record(.layoutSwitches)
    }

    // MARK: - Selection helpers

    private static func replaceSelection(with text: String) async {
        // NOT via AX: AX replacement (kAXSelectedTextAttribute) in Electron/terminal fields
        // (Claude Code, Slack) returns .success but doesn't replace — the word stays selected.
        //
        // The newline branch is a lesson learned from voice: a synthetic newline keystroke in
        // terminal fields means "send", so typed multi-line text broke at the first `\n`. It
        // legitimately arrives here: converting an ALREADY SELECTED paragraph, and LayoutMapper
        // passes `\n` through. Bracketed paste inserts newlines literally.
        if text.contains("\n") {
            await TextInjector.paste(text, source: .combinedSession, context: "layout:multiline")
        } else {
            // Single line (the vast majority) — typed, clipboard untouched.
            // TODO: "always paste" would break the rule "layout switching never touches the
            // clipboard". Moving this path is a SEPARATE step, deliberately not combined with the
            // dedup: otherwise a regression of the main feature couldn't be told apart from
            // side effects of the consolidation.
            TextInjector.type(text, source: .combinedSession)
        }
    }


    private static func copySelection() async -> String? {
        if let ax = selectedTextViaAX() { return ax }

        let pb = NSPasteboard.general
        var baselineCount = pb.changeCount
        var initialString = pb.string(forType: .string) ?? ""

        for attempt in 1...Timing.copyAttempts {
            // The loop runs up to ~3 s — the widest window of all services. Focus may have moved
            // to a password field AFTER the entry check, and Cmd+C goes to the current OS focus.
            guard !CaretProbe.isSecureNow() else {
                Log.warn(.layout, "TextSelector: secure-поле на попытке \(attempt) — копирование прервано")
                return nil
            }
            // Esc cancel — checked on EVERY attempt. The window is widest here (~3 s), and this is
            // exactly where the user's Esc must stop sending keys, not take effect "after
            // everything has already happened".
            guard !OperationGate.cancelledNow() else {
                Log.info(.layout, "TextSelector: отменено по Esc на попытке \(attempt)")
                return nil
            }
            if attempt > 1 {
                baselineCount = pb.changeCount
                initialString = pb.string(forType: .string) ?? ""
            }
            await TextInjector.sendKey(CGKeyCode(kVK_ANSI_C), flags: .maskCommand, source: .hidSystem)
            await sleepMicroseconds(Timing.afterCopySend)

            let deadline = Date().addingTimeInterval(Timing.copyTimeout)
            while Date() < deadline {
                if let str = CopyDetection.freshText(pb.string(forType: .string),
                                                     startCount: baselineCount,
                                                     currentCount: pb.changeCount,
                                                     initialText: initialString) {
                    pb.clearContents()
                    return str
                }
                try? await Task.sleep(nanoseconds: UInt64(Timing.copyPollInterval * 1_000_000_000))
            }
        }
        return nil
    }

    // MARK: - AX helpers

    private static func selectedTextViaAX() -> String? {
        guard let element = focusedElement() else { return nil }
        if let direct = copyAXString(element: element, attribute: kAXSelectedTextAttribute as CFString) {
            return direct
        }
        guard let full = copyAXString(element: element, attribute: kAXValueAttribute as CFString),
              let range = copyAXSelectedRange(element: element),
              let swiftRange = Range(range, in: full) else { return nil }
        return String(full[swiftRange])
    }

    private static func focusedElement() -> AXUIElement? {
        let system = AXUIElementCreateSystemWide()
        var element: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &element) == .success,
              let element, CFGetTypeID(element) == AXUIElementGetTypeID() else { return nil }
        return unsafeBitCast(element, to: AXUIElement.self)
    }

    private static func copyAXString(element: AXUIElement, attribute: CFString) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else { return nil }
        return value as? String
    }

    private static func copyAXSelectedRange(element: AXUIElement) -> NSRange? {
        var value: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &value) == .success,
           let range = cfRangeToNSRange(value) { return range }
        var rangesValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextRangesAttribute as CFString, &rangesValue) == .success,
           let arr = rangesValue as? [Any] {
            for item in arr { if let r = cfRangeToNSRange(item as CFTypeRef) { return r } }
        }
        return nil
    }

    private static func cfRangeToNSRange(_ value: CFTypeRef?) -> NSRange? {
        guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let axVal = value as! AXValue
        guard AXValueGetType(axVal) == .cfRange else { return nil }
        var range = CFRange()
        guard AXValueGetValue(axVal, .cfRange, &range) else { return nil }
        return NSRange(location: range.location, length: range.length)
    }

    // MARK: - Keyboard layout switching


    // MARK: - Key simulation


    private static func sleepMicroseconds(_ value: useconds_t) async {
        try? await Task.sleep(nanoseconds: UInt64(value) * 1_000)
    }

    // MARK: - Timing constants

    private enum Timing {
        static let recentTypingWindow: TimeInterval = 7
        static let afterCopySend: useconds_t = 60_000
        static let copyTimeout: TimeInterval = 1
        static let copyPollInterval: TimeInterval = 0.05
        static let selectionPause: useconds_t = 80_000
        static let hotKeyGuardInterval: TimeInterval = 0.05
        static let monitorSuspendWindow: TimeInterval = 1.5
        static let copyAttempts: Int = 3
    }
}
