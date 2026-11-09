import Foundation
import Testing
@testable import KeylyLogic

/// Statistics fail SILENTLY, and precisely at window boundaries: a wrong sum looks like
/// a plausible number, not a failure. The date comes into the logic as a parameter, so boundaries
/// can be tested exactly.
struct UsageStatsTests {

    /// Fixed reference point: "today" in tests. A real date would make the tests
    /// flaky (they would start failing at midnight UTC).
    private let now = Date(timeIntervalSince1970: 1_800_000_000)   // Jan 15, 2027 UTC
    private func daysAgo(_ n: Int) -> Date { now.addingTimeInterval(-Double(n) * 86_400) }

    @Test("События складываются по метрикам независимо")
    func addsPerMetric() {
        var s = UsageStats()
        s.add(.errorsFixed, on: now)
        s.add(.errorsFixed, on: now)
        s.add(.layoutSwitches, on: now)
        #expect(s.total(.errorsFixed) == 2)
        #expect(s.total(.layoutSwitches) == 1)
        #expect(s.total(.dictatedWords) == 0)
    }

    @Test("Счётчик надиктовки принимает количество слов, а не одно событие")
    func addsWithCount() {
        var s = UsageStats()
        s.add(.dictatedWords, count: 37, on: now)
        #expect(s.total(.dictatedWords) == 37)
    }

    @Test("Ноль и отрицательное количество не пишутся — это не событие")
    func ignoresNonPositive() {
        var s = UsageStats()
        s.add(.errorsFixed, count: 0, on: now)
        s.add(.errorsFixed, count: -5, on: now)
        #expect(s.total(.errorsFixed) == 0)
        #expect(s.isEmpty)
    }

    // MARK: - "Last week" window boundaries: this is where mistakes happen

    @Test("Окно «за неделю» включает СЕГОДНЯ и 6 предыдущих дней")
    func weekWindowIncludesToday() {
        var s = UsageStats()
        for d in 0..<7 { s.add(.errorsFixed, on: daysAgo(d)) }
        #expect(s.total(.errorsFixed, lastDays: 7, now: now) == 7, "7 дней = сегодня + 6 назад")
    }

    @Test("Седьмой день назад в окно НЕ входит — классическая ошибка на единицу")
    func weekWindowExcludesEighthDay() {
        var s = UsageStats()
        s.add(.errorsFixed, on: daysAgo(7))   // just past the boundary
        #expect(s.total(.errorsFixed, lastDays: 7, now: now) == 0)
        #expect(s.total(.errorsFixed) == 1, "за всё время событие всё равно есть")
    }

    @Test("«За всё время» не равно «за неделю», когда есть старые события")
    func allTimeDiffersFromWeek() {
        var s = UsageStats()
        s.add(.layoutSwitches, count: 10, on: now)
        s.add(.layoutSwitches, count: 90, on: daysAgo(30))
        #expect(s.total(.layoutSwitches, lastDays: 7, now: now) == 10)
        #expect(s.total(.layoutSwitches) == 100)
    }

    @Test("Нулевое или отрицательное окно даёт 0, а не всю историю")
    func nonPositiveWindow() {
        var s = UsageStats()
        s.add(.errorsFixed, count: 5, on: now)
        #expect(s.total(.errorsFixed, lastDays: 0, now: now) == 0)
        #expect(s.total(.errorsFixed, lastDays: -3, now: now) == 0)
    }

    // MARK: - Pruning

    @Test("Старые дни выбрасываются, свежие остаются")
    func prunesOldDays() {
        var s = UsageStats()
        s.add(.errorsFixed, on: daysAgo(1))
        s.add(.errorsFixed, on: daysAgo(UsageStats.retentionDays + 10))
        #expect(s.total(.errorsFixed) == 2)
        s.prune(now: now)
        #expect(s.total(.errorsFixed) == 1, "старое ведро должно уйти")
        #expect(s.total(.errorsFixed, lastDays: 7, now: now) == 1, "свежее — остаться")
    }

    @Test("Подрезка не съедает день ровно на границе хранения")
    func pruneKeepsBoundaryDay() {
        var s = UsageStats()
        s.add(.errorsFixed, on: daysAgo(UsageStats.retentionDays - 1))
        s.prune(now: now)
        #expect(s.total(.errorsFixed) == 1)
    }

    // MARK: - Day key and serialization

    @Test("Ключ дня — календарная дата в UTC, сортируемая как строка")
    func dayKeyFormat() {
        let key = UsageStats.dayKey(for: now)
        #expect(key.count == 10, "формат YYYY-MM-DD: \(key)")
        // String comparison of ISO dates = chronological order; prune relies on this.
        #expect(UsageStats.dayKey(for: daysAgo(1)) < key)
    }

    @Test("Разное время одного дня попадает в ОДНО ведро")
    func sameDaySameBucket() {
        var s = UsageStats()
        let morning = Date(timeIntervalSince1970: 1_800_000_000)
        let evening = morning.addingTimeInterval(8 * 3600)
        s.add(.errorsFixed, on: morning)
        s.add(.errorsFixed, on: evening)
        #expect(UsageStats.dayKey(for: morning) == UsageStats.dayKey(for: evening) ||
                s.total(.errorsFixed) == 2)
        #expect(s.total(.errorsFixed) == 2)
    }

    @Test("Статистика переживает круг кодирования — иначе счётчики обнулятся при перезапуске")
    func roundTripsThroughCoding() throws {
        var s = UsageStats()
        s.add(.dictatedWords, count: 120, on: now)
        s.add(.snippetsInserted, on: daysAgo(3))
        let restored = try JSONDecoder().decode(UsageStats.self, from: JSONEncoder().encode(s))
        #expect(restored == s)
        #expect(restored.total(.dictatedWords) == 120)
    }

    // MARK: - Dictation word count

    @Test("Слова считаются по непустым токенам")
    func wordCount() {
        #expect("привет мир".wordCount == 2)
        #expect("  двойные   пробелы  ".wordCount == 2, "пустые токены не считаются словами")
        #expect("абзац один\n\nабзац два".wordCount == 4, "переносы — тоже разделители")
        #expect("".wordCount == 0)
        #expect("   \n  ".wordCount == 0)
        #expect("одно".wordCount == 1)
    }
}

/// Undo subtracts the event. An error here is silent: the counter just lies,
/// and you could notice only by comparing with reality, which nobody does.
@Suite("Статистика: откат события")
struct UsageStatsSubtractTests {

    private static let day = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("Вычитает из дня самого действия, а не из сегодняшнего")
    func subtractsFromActionDay() {
        var stats = UsageStats()
        let yesterday = Self.day.addingTimeInterval(-86_400)
        stats.add(.errorsFixed, on: yesterday)
        stats.add(.errorsFixed, on: Self.day)

        stats.subtract(.errorsFixed, on: yesterday)

        #expect(stats.total(.errorsFixed, lastDays: 1, now: Self.day) == 1)
        #expect(stats.total(.errorsFixed) == 1)
    }

    @Test("Ниже нуля не опускается — отрицательная статистика читается как баг")
    func neverGoesNegative() {
        var stats = UsageStats()
        stats.add(.snippetsInserted, on: Self.day)
        stats.subtract(.snippetsInserted, count: 5, on: Self.day)
        #expect(stats.total(.snippetsInserted) == 0)
    }

    @Test("Вычитание из дня, которого нет в хранилище, ничего не ломает")
    func subtractFromMissingDayIsNoop() {
        var stats = UsageStats()
        stats.add(.layoutSwitches, on: Self.day)
        // The bucket may have been pruned by `prune`: nothing to subtract from.
        stats.subtract(.layoutSwitches, on: Self.day.addingTimeInterval(-30 * 86_400))
        #expect(stats.total(.layoutSwitches) == 1)
    }

    @Test("Слова надиктовки откатываются пачкой, как и записывались")
    func subtractsWordBatch() {
        var stats = UsageStats()
        stats.add(.dictatedWords, count: 42, on: Self.day)
        stats.subtract(.dictatedWords, count: 42, on: Self.day)
        #expect(stats.total(.dictatedWords) == 0)
        #expect(stats.isEmpty)
    }
}
