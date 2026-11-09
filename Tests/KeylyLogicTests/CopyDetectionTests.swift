import Testing
@testable import KeylyLogic

/// A synthetic Cmd+C that copied nothing must not be mistaken for a copy:
/// otherwise whatever the user had in the clipboard (possibly a password) is sent to the AI.
@Suite("Copy detection: did Cmd+C really copy?")
struct CopyDetectionTests {

    @Test("Clipboard untouched after Cmd+C → nothing was copied")
    func untouchedClipboardIsNotACopy() {
        let result = CopyDetection.freshText("old secret", startCount: 7, currentCount: 7, initialText: "old secret")
        #expect(result == nil)
    }

    @Test("Change counter moved → copied text is taken, even if it equals the old one")
    func counterMovedSameText() {
        let result = CopyDetection.freshText("same", startCount: 7, currentCount: 8, initialText: "same")
        #expect(result == "same")
    }

    @Test("Text differs from the initial one → it is a copy")
    func differentText() {
        let result = CopyDetection.freshText("new", startCount: 7, currentCount: 8, initialText: "old")
        #expect(result == "new")
    }

    @Test("Empty or missing text is never a copy")
    func emptyText() {
        #expect(CopyDetection.freshText("", startCount: 1, currentCount: 2, initialText: nil) == nil)
        #expect(CopyDetection.freshText(nil, startCount: 1, currentCount: 2, initialText: nil) == nil)
    }

    @Test("Empty clipboard before, text after, counter moved → copy")
    func fromEmptyClipboard() {
        #expect(CopyDetection.freshText("hi", startCount: 3, currentCount: 4, initialText: nil) == "hi")
    }

    @Test("Counter unchanged but text differs from the pre-copy text → copy")
    func sameCounterDifferentText() {
        #expect(CopyDetection.freshText("new", startCount: 5, currentCount: 5, initialText: "old") == "new")
    }
}
