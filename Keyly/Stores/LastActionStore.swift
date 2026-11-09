import AppKit

/// A record for undo: `(element, range, inserted text, original, time)`.
///
/// The range is NOT stored as a number but derived from a pair of "before/after" snapshots. Reason:
/// a numeric range goes stale after any edit higher up in the text, while a pair of snapshots lets
/// us FIND our piece wherever it ended up and restore exactly that. The previous version stored only
/// "the whole field as it was" and restored the entire field — along with everything the user had
/// typed after us.
struct UndoRecord {
    /// Full field text BEFORE our operation.
    let beforeText: String
    /// Full field text AFTER it.
    let afterText: String
    let targetElement: AXUIElement?
    let targetApp: NSRunningApplication?
    let createdAt: Date
    /// Which usage counter this operation increased. Undo subtracts it back:
    /// an undone insertion is an insertion that never happened.
    let metric: UsageMetric?
    let metricCount: Int

    /// What we inserted: the part of `afterText` that differs from `beforeText`.
    var insertedFragment: String { UndoPlan.diff(before: beforeText, after: afterText).new }
    /// What was in its place.
    var originalFragment: String { UndoPlan.diff(before: beforeText, after: afterText).old }

    /// Lifetime. Undo is a destructive operation on someone else's text, and a record that has been
    /// lying around for half an hour almost certainly refers to a field the user no longer remembers.
    static let lifetime: TimeInterval = 10 * 60
    var isExpired: Bool { Date().timeIntervalSince(createdAt) > Self.lifetime }
}

@MainActor
final class LastActionStore {
    static let shared = LastActionStore()

    private(set) var lastRecord: UndoRecord? {
        didSet {
            NotificationCenter.default.post(
                name: .lastActionChanged,
                object: nil,
                userInfo: ["hasRecord": lastRecord != nil]
            )
        }
    }

    private init() {}

    /// Records a text replacement operation. `before` and `after` are full field snapshots.
    /// Identical snapshots are NOT recorded: there is nothing to undo, and the record would
    /// overwrite the previous one, which can actually be undone.
    func record(before: String, after: String, element: AXUIElement?, app: NSRunningApplication?,
                metric: UsageMetric? = nil, metricCount: Int = 1) {
        guard before != after else { return }
        lastRecord = UndoRecord(beforeText: before, afterText: after,
                                targetElement: element, targetApp: app, createdAt: Date(),
                                metric: metric, metricCount: metricCount)
    }

    func clear() {
        lastRecord = nil
    }
}
