import Testing
@testable import KeylyLogic

/// Key format check before any network call.
///
/// Motivated by a real run: pasting `sk-test` showed just
/// "Error" in the key row, with no hint of what was wrong or where to go.
struct APIKeyFormatTests {

    @Test("Обрезанный ключ OpenAI ловится по длине, а не по ответу сети")
    func shortOpenAIKey() {
        #expect(APIKeyFormat.check("sk-test", provider: .openai) == .tooShort)
    }

    @Test("Настоящий по виду ключ проходит")
    func plausibleKeysPass() {
        #expect(APIKeyFormat.check("sk-proj-" + String(repeating: "a", count: 40), provider: .openai) == .ok)
        #expect(APIKeyFormat.check("AIza" + String(repeating: "b", count: 35), provider: .gemini) == .ok)
    }

    @Test("Ключ чужого провайдера опознаётся по префиксу")
    func wrongProviderDetected() {
        #expect(APIKeyFormat.check("AIza" + String(repeating: "b", count: 35), provider: .openai)
                == .wrongPrefix(expected: "sk-"))
        #expect(APIKeyFormat.check("sk-" + String(repeating: "a", count: 40), provider: .gemini)
                == .wrongPrefix(expected: "AIza"))
    }

    @Test("Пустой ключ и пробелы — отдельный вердикт")
    func emptyDetected() {
        #expect(APIKeyFormat.check("", provider: .openai) == .empty)
        #expect(APIKeyFormat.check("   \n", provider: .gemini) == .empty)
    }

    @Test("Пробелы по краям не мешают настоящему ключу")
    func trimsWhitespace() {
        let key = "  sk-" + String(repeating: "a", count: 40) + "\n"
        #expect(APIKeyFormat.check(key, provider: .openai) == .ok)
    }

    @Test("Сетевую проверку отменяют только безнадёжные случаи")
    func onlyHopelessCasesBlockNetwork() {
        // A key with an unfamiliar prefix may still work: providers introduce new
        // formats. Declaring it invalid before the network call would deny the user the check.
        #expect(!APIKeyFormat.blocksNetworkCheck(.wrongPrefix(expected: "AIza")))
        #expect(!APIKeyFormat.blocksNetworkCheck(.ok))
        #expect(APIKeyFormat.blocksNetworkCheck(.empty))
        #expect(APIKeyFormat.blocksNetworkCheck(.tooShort))
    }

    @Test("У каждого отказа есть человеческое объяснение")
    func everyFailureExplains() {
        for verdict: APIKeyFormat.Verdict in [.empty, .wrongPrefix(expected: "sk-"), .tooShort] {
            #expect(APIKeyFormat.messageKey(for: verdict) != nil, "\(verdict) без объяснения")
        }
        #expect(APIKeyFormat.messageKey(for: .ok) == nil)
    }
}
