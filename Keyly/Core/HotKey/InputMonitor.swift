import AppKit
import Carbon.HIToolbox

/// Tracks recent keystrokes to understand the context before a hotkey.
final class InputMonitor {
    static let shared = InputMonitor()

    enum EventKind {
        case selection
        case character
    }

    struct RecordedEvent {
        let kind: EventKind
        let timestamp: Date
        let keyCode: UInt16
        let modifiers: NSEvent.ModifierFlags
        let characters: String?
    }

    private let queue = DispatchQueue(label: "InputMonitor.queue")
    private var events: [RecordedEvent] = []
    private let maxEvents = 20
    private var suspendedUntil: Date = .distantPast

    func record(cgEvent: CGEvent) {
        guard let event = NSEvent(cgEvent: cgEvent), event.type == .keyDown else { return }

        let now = Date()
        // `return` inside the queue.sync closure exits the closure, not the function — so events
        // used to be recorded even while suspended. Compute the flag and exit explicitly.
        let isSuspended = queue.sync { now < suspendedUntil }
        if isSuspended { return }

        let mods = normalizedModifiers(event.modifierFlags)
        let keyCode = event.keyCode

        // Backspace REMOVES a character from the typed buffer. Without this, erasing a typo left
        // the letter in the buffer, and trigger matching ran on text no longer on screen.
        //
        // A match is NOT evaluated on backspace itself — insertion happens only on ADDING a
        // character: otherwise, erasing a word backwards, the user would pass through other
        // triggers and get an insertion while just fixing a typo.
        if keyCode == 51, mods.isEmpty {
            queue.sync {
                if !events.isEmpty { events.removeLast() }
            }
            return
        }

        let kind: EventKind?
        if isSelection(keyCode: keyCode, modifiers: mods) {
            kind = .selection
        } else if isCharacter(event: event, modifiers: mods) {
            kind = .character
        } else {
            kind = nil
        }

        guard let kind else { return }

        let record = RecordedEvent(kind: kind,
                                   timestamp: Date(),
                                   keyCode: keyCode,
                                   modifiers: mods,
                                   characters: event.charactersIgnoringModifiers)
        queue.sync {
            events.append(record)
            if events.count > maxEvents {
                events.removeFirst(events.count - maxEvents)
            }
        }
    }

    func suspend(for interval: TimeInterval) {
        queue.sync {
            suspendedUntil = Date().addingTimeInterval(interval)
        }
    }

    func lastRelevantEvent(before reference: Date) -> RecordedEvent? {
        queue.sync { events.last(where: { $0.timestamp <= reference }) }
    }

    func lastRelevantEvent() -> RecordedEvent? {
        queue.sync { events.last }
    }

    func lastNTypedCharacters(count: Int) -> String {
        queue.sync {
            events
                .filter { $0.kind == .character }
                .suffix(count)
                .compactMap { $0.characters }
                .joined()
        }
    }

    /// Characters typed CONSECUTIVELY — without long pauses between keystrokes.
    ///
    /// Plain `lastNTypedCharacters` returns the whole ring buffer, which lives across Enter,
    /// app switches and pauses: Enter isn't recorded at all (it's not a "character"), so the
    /// previous command's text got glued to the fresh word. In a terminal this meant "erase
    /// 11 characters" where the user had typed six.
    ///
    /// A pause longer than `maxGap` counts as a boundary: people think between two commands,
    /// not inside a word.
    func recentlyTypedCharacters(count: Int, maxGap: TimeInterval) -> String {
        queue.sync {
            let characters = events.filter { $0.kind == .character }.suffix(count)
            var tail: [String] = []
            var nextTimestamp: Date?
            for record in characters.reversed() {
                if let next = nextTimestamp, next.timeIntervalSince(record.timestamp) > maxGap {
                    break
                }
                guard let text = record.characters else { break }
                tail.append(text)
                nextTimestamp = record.timestamp
            }
            return tail.reversed().joined()
        }
    }

    /// Replace the typed buffer with the given text.
    ///
    /// Needed after WE rewrote a word in another app's field: the buffer must reflect what is
    /// now on screen, otherwise pressing the hotkey again finds no data and the operation
    /// becomes irreversible (it must be reversible).
    func seedTypedCharacters(_ text: String) {
        let now = Date()
        let records = text.map { character in
            RecordedEvent(kind: .character, timestamp: now, keyCode: 0,
                          modifiers: [], characters: String(character))
        }
        queue.sync {
            events = Array(records.suffix(maxEvents))
        }
    }

    /// Forget the last recorded event.
    ///
    /// Needed where we SWALLOW the event: recording into the buffer happens BEFORE the decision
    /// to swallow, so the hotkey press gets into "typed text". For features reading the buffer
    /// that means an extra character glued to the word — in a terminal, word conversion returned
    /// the word with an extra leading letter because the hotkey was the "]" key.
    func dropLastRecorded() {
        queue.sync {
            guard !events.isEmpty else { return }
            events.removeLast()
        }
    }

    func clearBuffer() {
        queue.sync { events.removeAll() }
    }

    func referenceDate(from cgEvent: CGEvent) -> Date? {
        guard NSEvent(cgEvent: cgEvent) != nil else { return nil }
        return Date()
    }

    private func isSelection(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> Bool {
        if modifiers.contains(.shift) && arrowKeyCodes.contains(keyCode) {
            return true
        }
        if modifiers.contains(.command) && keyCode == UInt16(kVK_ANSI_A) {
            return true
        }
        return false
    }

    private func isCharacter(event: NSEvent, modifiers: NSEvent.ModifierFlags) -> Bool {
        if modifiers.contains(.command) || modifiers.contains(.control) { return false }
        guard let chars = event.charactersIgnoringModifiers, !chars.isEmpty else { return false }
        if chars.count > 1 { return false }
        guard let scalar = chars.unicodeScalars.first else { return false }

        if CharacterSet.controlCharacters.contains(scalar) { return false }
        if CharacterSet.newlines.contains(scalar) { return false }
        // Ignore special characters (arrows/function keys) that live in the private-use range.
        if (0xF700...0xF8FF).contains(scalar.value) { return false }

        return true
    }

    private func normalizedModifiers(_ flags: NSEvent.ModifierFlags) -> NSEvent.ModifierFlags {
        flags.intersection([.command, .option, .shift, .control])
    }

    private let arrowKeyCodes: Set<UInt16> = [
        UInt16(kVK_LeftArrow),
        UInt16(kVK_RightArrow),
        UInt16(kVK_UpArrow),
        UInt16(kVK_DownArrow)
    ]
}
