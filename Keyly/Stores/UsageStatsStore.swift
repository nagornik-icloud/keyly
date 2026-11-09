import Combine
import Foundation

/// Stores usage statistics. Local only — nothing leaves the machine.
///
/// A thin adapter: all the arithmetic of windows and daily buckets lives in `UsageStats` (pure
/// logic, covered by tests). Here: persistence, publishing to the UI and trimming old days.
@MainActor
final class UsageStatsStore: ObservableObject {

    static let shared = UsageStatsStore()

    private static let key = "usageStats"

    @Published private(set) var stats: UsageStats

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode(UsageStats.self, from: data) {
            stats = decoded
        } else {
            stats = UsageStats()
        }
    }

    /// Record an event. `count` is for dictated words (a whole phrase arrives at once).
    func record(_ metric: UsageMetric, count: Int = 1) {
        let now = Date()
        stats.add(metric, count: count, on: now)
        stats.prune(now: now)
        persist()
    }

    /// Roll back an event: the user undid an insertion (undo subtracts).
    /// `date` is the moment of the action ITSELF, not of the undo: otherwise we'd subtract from another day.
    func unrecord(_ metric: UsageMetric, count: Int = 1, at date: Date) {
        stats.subtract(metric, count: count, on: date)
        persist()
    }

    /// Reset — a button in Settings → "Advanced".
    func reset() {
        stats = UsageStats()
        persist()
        Log.info(.app, "Статистика сброшена")
    }

    // MARK: - Reading for the UI

    func value(_ metric: UsageMetric, period: Period) -> Int {
        switch period {
        case .week:    return stats.total(metric, lastDays: 7, now: Date())
        case .allTime: return stats.total(metric)
        }
    }

    enum Period: String, CaseIterable {
        case week
        case allTime
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(stats) else { return }
        UserDefaults.standard.set(data, forKey: Self.key)
    }
}
