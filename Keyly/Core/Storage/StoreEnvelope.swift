import Foundation

/// Store envelope: schema version + payload.
///
/// Why a version. Without it an incompatible model change is indistinguishable from corrupted
/// data, and the only reaction to a failed decode is returning an empty list. Then a chain
/// already loaded in the product fires: decode fails → list is empty → the user sees "nothing
/// here" → adds one entry → `save()` physically overwrites all the others. Three steps from a
/// model change to losing all of the user's snippets, keys and modules.
///
/// The type is PURE (no UserDefaults, no file system) — so it's wired into the test package
/// and covered by tests. IO lives separately, in `VersionedStore`.
enum StoreEnvelope {

    /// Current schema version. Bumped on an INCOMPATIBLE model change.
    static let currentVersion = 1

    /// What decoding returned. Three outcomes, and "empty" differs from "broken" — that's the whole point.
    enum Decoded<Element> {
        /// Data was read. An empty array here means "there really are no entries".
        case ok([Element], version: Int)
        /// There were no entries yet (the key is empty). Not an error: first launch.
        case empty
        /// Data EXISTS but couldn't be read. The original bytes are attached — the caller must save
        /// them and must forbid writing over them.
        case corrupted(raw: Data, reason: String)
    }

    private struct Envelope<Element: Codable>: Codable {
        let schemaVersion: Int
        let items: [Element]
    }

    /// Decodes data accepting BOTH formats: a versioned envelope and legacy — a bare array without
    /// a version (how all stores wrote before this change). Legacy counts as version 0.
    ///
    /// The order of attempts is exactly this: envelope first, then the bare array. The reverse
    /// order would give a type error on an envelope and push working data into `corrupted`.
    static func decode<Element: Codable>(_ data: Data?, as: Element.Type) -> Decoded<Element> {
        guard let data, !data.isEmpty else { return .empty }
        let decoder = JSONDecoder()

        if let env = try? decoder.decode(Envelope<Element>.self, from: data) {
            return .ok(env.items, version: env.schemaVersion)
        }
        do {
            let legacy = try decoder.decode([Element].self, from: data)
            return .ok(legacy, version: 0)
        } catch {
            // Exactly the cases all this was written for end up here: a field became optional,
            // a type changed, an entry was partially written.
            return .corrupted(raw: data, reason: String(describing: error))
        }
    }

    /// Encodes into an envelope of the current version. A bare array is never written again —
    /// otherwise the next read again couldn't tell "old" from "broken".
    static func encode<Element: Codable>(_ items: [Element]) throws -> Data {
        try JSONEncoder().encode(Envelope(schemaVersion: currentVersion, items: items))
    }

    /// Backup file name for corrupted data. A separate function because the name is part of the
    /// contract: the user finds their data by it, and a test checks the format.
    /// The timestamp comes from OUTSIDE: pure logic doesn't look at the clock, otherwise it
    /// couldn't be tested.
    static func backupFileName(store: String, at timestamp: Date,
                               calendar: Calendar = Calendar(identifier: .gregorian)) -> String {
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second],
                                        from: timestamp)
        let stamp = String(format: "%04d%02d%02d-%02d%02d%02d",
                           c.year ?? 0, c.month ?? 0, c.day ?? 0,
                           c.hour ?? 0, c.minute ?? 0, c.second ?? 0)
        return "\(store)-corrupted-\(stamp).json"
    }
}
