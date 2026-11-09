import Testing
@testable import KeylyLogic

/// The sanitizer is the last line of defense before the system log. If it lets a key through, the key ends up
/// in Console and in sysdiagnose, where it can no longer be recalled.
struct LogSanitizerTests {

    private func assertNoSecret(_ sanitized: String, _ secret: String, _ what: String) {
        #expect(!sanitized.contains(secret), "\(what): секрет остался в строке → «\(sanitized)»")
    }

    @Test("Ключ Gemini из URL вырезается — главный транзитный путь утечки")
    func stripsGeminiKeyFromURL() {
        // This is exactly how a key gets into the log: URLSession puts the full URL into NSError.
        let raw = "Error Domain=NSURLErrorDomain Code=-1009 NSErrorFailingURLKey=https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=AIzaSyC7xREAL_KEY_MATERIAL_9f"
        let out = LogSanitizer.sanitize(raw)
        assertNoSecret(out, "AIzaSyC7xREAL_KEY_MATERIAL_9f", "ключ Gemini в URL")
        #expect(out.contains("key=\(LogSanitizer.redacted)"))
        // The diagnostic part must survive, otherwise the log is useless.
        #expect(out.contains("NSURLErrorDomain"))
        #expect(out.contains("gemini-2.0-flash"))
    }

    @Test("Bearer-токен в заголовке вырезается, название заголовка остаётся")
    func stripsBearerToken() {
        let out = LogSanitizer.sanitize("Authorization: Bearer sk-proj-AbCdEf0123456789xyz")
        assertNoSecret(out, "sk-proj-AbCdEf0123456789xyz", "Bearer-токен")
        #expect(out.lowercased().contains("authorization"))
    }

    @Test("Ключ узнаётся по форме даже без заголовка — например, в теле ответа")
    func stripsBareKeysByShape() {
        let openai = LogSanitizer.sanitize("{\"error\":\"invalid key sk-abcdefgh12345678\"}")
        assertNoSecret(openai, "sk-abcdefgh12345678", "голый ключ OpenAI")

        let gemini = LogSanitizer.sanitize("provided key AIzaSyABCDEFGHIJ1234567890 is invalid")
        assertNoSecret(gemini, "AIzaSyABCDEFGHIJ1234567890", "голый ключ Gemini")
    }

    @Test("Несколько секретов в одной строке вырезаются все")
    func stripsMultipleSecrets() {
        let out = LogSanitizer.sanitize("url=...?key=AIzaSyQQQQQQQQQQQQ header=Bearer sk-zzzzzzzzzzzz")
        assertNoSecret(out, "AIzaSyQQQQQQQQQQQQ", "первый секрет")
        assertNoSecret(out, "sk-zzzzzzzzzzzz", "второй секрет")
    }

    @Test("Обычный текст не искажается — санитайзер не должен мешать чтению логов")
    func leavesOrdinaryTextAlone() {
        let samples = [
            "TextSelector: конвертация раскладки отменена",
            "HotKeyManager: EventTap установлен",
            "статус 429, повтор через 2с",
            "",
        ]
        for s in samples {
            #expect(LogSanitizer.sanitize(s) == s, "строка изменена без причины: «\(s)»")
        }
    }

    @Test("Отпечаток ключа не позволяет восстановить ключ")
    func fingerprintHidesSecret() {
        let secret = "sk-proj-VERYSECRETVALUE123456"
        let fp = LogSanitizer.fingerprint(secret)
        assertNoSecret(fp, secret, "отпечаток")
        #expect(!fp.contains("VERYSECRET"))
        // But it stays useful: the start and the length are visible ("was the right key used").
        #expect(fp.hasPrefix("sk-p"))
        #expect(fp.contains("\(secret.count)"))
        #expect(LogSanitizer.fingerprint("") == "‹пусто›")
    }
}
