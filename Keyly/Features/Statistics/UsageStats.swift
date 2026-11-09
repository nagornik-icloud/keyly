import Foundation

/// What we count: typo fixes · dictated words · layout switches · snippet insertions.
/// Stored LOCALLY, never sent anywhere.
enum UsageMetric: String, CaseIterable, Codable {
    case errorsFixed
    case dictatedWords
    case layoutSwitches
    case snippetsInserted
}

/// Accumulated stats — PURE logic, no storage or UI.
///
/// Organized in daily buckets, not two totals: "this week" can't be computed from one counter,
/// and storing every event with a timestamp is wasteful and unnecessary — day precision is
/// enough for the dashboard.
///
/// The date is NEVER read internally — it's passed in: otherwise the window logic can't be
/// tested, and window boundaries are exactly where such code goes wrong.
struct UsageStats: Codable, Equatable {

    /// Bucket key — a calendar day in UTC (`YYYY-MM-DD`). The local time zone is deliberately not
    /// used: otherwise flying to another time zone would reshuffle already accumulated days.
    typealias DayKey = String

    /// `[day: [metric: count]]`. Empty days aren't stored.
    private(set) var buckets: [DayKey: [UsageMetric: Int]] = [:]

    /// How many days to keep. 60 leaves headroom for the "this week" window and gaps, without
    /// unbounded growth in UserDefaults.
    static let retentionDays = 60

    static func dayKey(for date: Date) -> DayKey {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    // MARK: - Writing

    mutating func add(_ metric: UsageMetric, count: Int = 1, on date: Date) {
        guard count > 0 else { return }   // a negative "event" is not an event
        let key = Self.dayKey(for: date)
        buckets[key, default: [:]][metric, default: 0] += count
    }

    /// Reverts an event: the user undid the insertion, so it didn't happen.
    ///
    /// Subtract from the bucket of THE DAY the action happened, not today's: otherwise undoing
    /// after midnight something done yesterday would push today's counter negative and leave
    /// yesterday's inflated.
    ///
    /// Never go below zero. The bucket may already have been trimmed by `prune`, leaving nothing
    /// to subtract from — negative stats are worse than slightly inflated ones: they read as a bug.
    mutating func subtract(_ metric: UsageMetric, count: Int = 1, on date: Date) {
        guard count > 0 else { return }
        let key = Self.dayKey(for: date)
        guard let current = buckets[key]?[metric] else { return }
        let left = max(0, current - count)
        if left == 0 {
            buckets[key]?[metric] = nil
            if buckets[key]?.isEmpty == true { buckets[key] = nil }
        } else {
            buckets[key]?[metric] = left
        }
    }

    /// Drops buckets older than the retention period. Call on write — otherwise the dictionary grows forever.
    mutating func prune(now: Date) {
        let cutoff = Self.dayKey(for: now.addingTimeInterval(-Double(Self.retentionDays) * 86_400))
        buckets = buckets.filter { $0.key >= cutoff }   // ISO-format strings compare like dates
    }

    // MARK: - Reading

    /// Total over the last `days` calendar days, including today.
    func total(_ metric: UsageMetric, lastDays days: Int, now: Date) -> Int {
        guard days > 0 else { return 0 }
        let keys = (0..<days).map { Self.dayKey(for: now.addingTimeInterval(-Double($0) * 86_400)) }
        return keys.reduce(0) { $0 + (buckets[$1]?[metric] ?? 0) }
    }

    func total(_ metric: UsageMetric) -> Int {
        buckets.values.reduce(0) { $0 + ($1[metric] ?? 0) }
    }

    var isEmpty: Bool {
        buckets.allSatisfy { $0.value.values.allSatisfy { $0 == 0 } }
    }
}

extension String {
    /// Word count — for the dictation counter. Counts non-empty tokens after splitting on
    /// whitespace and newlines: `components` yields empty items on double spaces and "\n\n".
    var wordCount: Int {
        split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }
}
