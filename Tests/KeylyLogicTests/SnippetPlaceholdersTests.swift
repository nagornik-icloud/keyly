import Testing
import Foundation
@testable import KeylyLogic

/// Placeholders in snippet text.
@Suite struct SnippetPlaceholdersTests {

    private var moment: Date {
        var components = DateComponents()
        components.year = 2026; components.month = 7; components.day = 26
        components.hour = 14; components.minute = 5
        return Calendar(identifier: .gregorian).date(from: components)!
    }

    @Test func буферПодставляется() {
        let out = SnippetPlaceholders.expand("Ссылка: {буфер}", now: moment, clipboard: "https://a.b")
        #expect(out.text == "Ссылка: https://a.b")
    }

    /// An empty clipboard gives an empty spot, not the token: a raw clipboard token in the middle of a pasted email
    /// reads to the user as a product bug.
    @Test func пустойБуферНеОставляетТокен() {
        let out = SnippetPlaceholders.expand("Ссылка: {буфер}", now: moment, clipboard: nil)
        #expect(out.text == "Ссылка: ")
        #expect(!out.text.contains("{буфер}"))
    }

    @Test func кареткаЗадаётСмещениеИИсчезаетИзТекста() {
        let out = SnippetPlaceholders.expand("Привет, {курсор}!", now: moment, clipboard: nil)
        #expect(out.text == "Привет, !")
        #expect(out.caretOffset == 8)
    }

    /// The offset is computed AFTER the other substitutions: otherwise it would be off by
    /// the length of the inserted date or clipboard text.
    @Test func смещениеУчитываетПодставленноеРанее() {
        let out = SnippetPlaceholders.expand("{буфер}{курсор}конец", now: moment, clipboard: "12345")
        #expect(out.text == "12345конец")
        #expect(out.caretOffset == 5)
    }

    @Test func безКареткиСмещенияНет() {
        let out = SnippetPlaceholders.expand("просто текст", now: moment, clipboard: nil)
        #expect(out.caretOffset == nil)
    }

    /// A second caret marker has nowhere to go: it simply disappears instead of staying as a token.
    @Test func второйМаркерКареткиУдаляется() {
        let out = SnippetPlaceholders.expand("a{курсор}b{курсор}c", now: moment, clipboard: nil)
        #expect(out.text == "abc")
        #expect(out.caretOffset == 1)
    }

    @Test func датаИВремяРазныеТокены() {
        let ru = Locale(identifier: "ru_RU")
        let out = SnippetPlaceholders.expand("{дата} {время}", now: moment,
                                             clipboard: nil,
                                             calendar: Calendar(identifier: .gregorian),
                                             locale: ru)
        #expect(!out.text.contains("{дата}"))
        #expect(!out.text.contains("{время}"))
        #expect(out.text.contains("2026"))
    }

    @Test func признакНаличияПодстановок() {
        #expect(SnippetPlaceholders.containsPlaceholders("текст {дата}"))
        #expect(!SnippetPlaceholders.containsPlaceholders("текст без них"))
    }
}

/// Latin spellings of the tokens.
///
/// The Cyrillic date token cannot be typed by someone on an English layout without
/// switching mid-snippet, exactly what Keyly saves you from. Both
/// spellings are equal; the canonical one (what the chips insert) stays Cyrillic so that
/// already saved snippets do not turn into plain text.
@Suite("Токены сниппетов на латинице")
struct SnippetPlaceholderLatinTests {

    private let moment = Date(timeIntervalSince1970: 1_700_000_000)

    @Test func латинскийБуферРазворачивается() {
        let r = SnippetPlaceholders.expand("тел: {clipboard}", now: moment, clipboard: "+7 900")
        #expect(r.text == "тел: +7 900")
    }

    @Test func обаНаписанияВОдномТекстеРаботаютВместе() {
        let r = SnippetPlaceholders.expand("{буфер} и {clipboard}", now: moment, clipboard: "X")
        #expect(r.text == "X и X")
    }

    @Test func латинскийКурсорЗадаётСмещениеИИсчезает() {
        let r = SnippetPlaceholders.expand("Привет, {cursor}!", now: moment, clipboard: nil)
        #expect(r.text == "Привет, !")
        #expect(r.caretOffset == 8)
    }

    @Test func кареткаБерётсяПоПЕРВОМУМаркеруВЛюбомНаписании() {
        // The Latin cursor token comes before the Cyrillic one, so it wins, not the iteration order.
        let r = SnippetPlaceholders.expand("ab{cursor}cd{курсор}", now: moment, clipboard: nil)
        #expect(r.text == "abcd")
        #expect(r.caretOffset == 2)
    }

    @Test func латинскийТокенОпознаётсяКакПодстановка() {
        #expect(SnippetPlaceholders.containsPlaceholders("что-то {date}"))
        #expect(SnippetPlaceholders.containsPlaceholders("что-то {дата}"))
        #expect(!SnippetPlaceholders.containsPlaceholders("просто текст"))
    }

    @Test func латинскаяДатаИВремяПодставляются() {
        let r = SnippetPlaceholders.expand("{date} {time}", now: moment, clipboard: nil,
                                           calendar: Calendar(identifier: .gregorian),
                                           locale: Locale(identifier: "ru_RU"))
        #expect(!r.text.contains("{date}"))
        #expect(!r.text.contains("{time}"))
    }
}

/// Which spelling a chip button puts into the text.
@Suite("Написание, которое вставляет чип")
struct SnippetPlaceholderPreferredTests {

    @Test func русскийИнтерфейсПолучаетКанон() {
        #expect(SnippetPlaceholders.Token.preferred(.date, language: "ru") == "{дата}")
        #expect(SnippetPlaceholders.Token.preferred(.caret, language: "ru-RU") == "{курсор}")
    }

    @Test func английскийИнтерфейсПолучаетЛатиницу() {
        // Cyrillic text for an English-speaking user is characters they cannot type by hand.
        #expect(SnippetPlaceholders.Token.preferred(.date, language: "en") == "{date}")
        #expect(SnippetPlaceholders.Token.preferred(.caret, language: "en-US") == "{cursor}")
    }

    @Test func любойДругойЯзыкТожеПолучаетЛатиницу() {
        // Latin is the safe default: it can be typed on any layout except Cyrillic,
        // and Cyrillic is served by an explicit branch.
        #expect(SnippetPlaceholders.Token.preferred(.time, language: "de") == "{time}")
    }

    @Test func обаНаписанияЧипаРазворачиваютсяОдинаково() {
        let moment = Date(timeIntervalSince1970: 1_700_000_000)
        for lang in ["ru", "en"] {
            let spelling = SnippetPlaceholders.Token.preferred(.clipboard, language: lang)
            let r = SnippetPlaceholders.expand(spelling, now: moment, clipboard: "Z")
            #expect(r.text == "Z", "написание \(spelling) не развернулось")
        }
    }
}

/// The palette height is computed from the library, not fixed.
@Suite("Высота палитры сниппетов")
struct SnippetPaletteHeightTests {

    /// Duplicates the controller's formula: the type itself pulls in AppKit and is not in the test package.
    /// The rule is checked here so the floor, ceiling and row step do not silently drift apart.
    private func height(for n: Int) -> CGFloat {
        let rows = min(max(n, 1), 8)
        return min(max(48 + CGFloat(rows) * 44 + 34, 220), 400)
    }

    @Test func пустаяБиблиотекаНеРаспахиваетПанельНаВесьЭкран() {
        // It used to be 400pt of black plate for a single "no snippets yet" line.
        #expect(height(for: 0) == 220)
    }

    @Test func четыреСниппетаЗанимаютМеньшеПрежнихЧетырёхСот() {
        #expect(height(for: 4) == 258)
    }

    @Test func большаяБиблиотекаУпираетсяВПотолок() {
        // Eight rows or more give the same height: beyond that the list scrolls.
        #expect(height(for: 8) == 400)
        #expect(height(for: 41) == 400)
    }

    @Test func высотаМонотонноРастёт() {
        // For no library size may the palette SHRINK when a snippet is added.
        for n in 0..<40 {
            #expect(height(for: n) <= height(for: n + 1), "сжалась на \(n) → \(n + 1)")
        }
    }
}

/// Model prices: a label must be either correct or absent.
@Suite("Ориентировочная цена модели")
struct ModelPricingTests {

    @Test func дешёваяМодельНеПоказываетсяКакБесплатная() {
        // With two decimals gpt-4o-mini would show "$0.00", i.e. falsely claim
        // the call costs nothing. Variable precision exists for exactly this case.
        let label = ModelPricing.perCall(for: "gpt-4o-mini")
        #expect(label != nil)
        #expect(label != "$0.00", "получили «\(label ?? "")»")
    }

    @Test func дорогаяИДешёваяРазличаются() {
        let cheap = ModelPricing.perCall(for: "gpt-4o-mini")
        let pricey = ModelPricing.perCall(for: "gpt-4o")
        #expect(cheap != pricey, "разница между ними больше чем в десять раз")
    }

    @Test func неизвестнаяЦенаНеВыдумывается() {
        // A made-up number is worse than nothing: the user makes money decisions based on it.
        #expect(ModelPricing.perCall(for: "gpt-5.5") == nil)
        #expect(ModelPricing.perCall(for: "gemini-flash-latest") == nil)
        #expect(ModelPricing.perMinute(for: "какая-то-новая") == nil)
    }

    @Test func распознаваниеСчитаетсяЗаМинуту() {
        #expect(ModelPricing.perMinute(for: "gpt-4o-mini-transcribe") != nil)
        // And it has NO per-call price: audio is billed, not tokens.
        #expect(ModelPricing.perCall(for: "gpt-4o-mini-transcribe") == nil)
    }

    @Test func форматНеТеряетЗначащихЦифр() {
        #expect(ModelPricing.format(0.00037) == "$0.0004")
        #expect(ModelPricing.format(0.006) == "$0.006")
        #expect(ModelPricing.format(0.25) == "$0.25")
    }
}
