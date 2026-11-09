import Testing
@testable import KeylyLogic

/// Parsing the last word for the terminal strategy.
struct TerminalTargetsTests {

    @Test("Последнее слово — хвост после пробела")
    func lastWordAfterSpace() {
        #expect(TerminalTargets.lastTypedWord(in: "git commit ghbdtn") == "ghbdtn")
    }

    @Test("Пути и точки словом не разрываются — их конвертировать целиком")
    func pathStaysWhole() {
        #expect(TerminalTargets.lastTypedWord(in: "cd ~/dev-apps/gjhn") == "~/dev-apps/gjhn")
    }

    @Test("Перевод строки и таб — тоже граница слова")
    func newlineIsBoundary() {
        #expect(TerminalTargets.lastTypedWord(in: "ls\nghbdtn") == "ghbdtn")
        #expect(TerminalTargets.lastTypedWord(in: "ls\tghbdtn") == "ghbdtn")
    }

    @Test("Пустой буфер и хвост из пробелов слова не дают — стирать нечего")
    func emptyGivesNil() {
        #expect(TerminalTargets.lastTypedWord(in: "") == nil)
        #expect(TerminalTargets.lastTypedWord(in: "   ") == nil)
    }
}
