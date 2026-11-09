import Foundation

/// Latch for failed reads — SHARED by all stores, at file level.
///
/// It can't live inside `VersionedStore<Element>` (Swift doesn't allow static stored
/// properties in generics), and that's right in essence: the latch is about the store KEY, not
/// the element type. Otherwise `VersionedStore<Snippet>` and `VersionedStore<CustomAIModule>`
/// would each have their own copy and not see each other's failures.
private final class DecodeLatch: @unchecked Sendable {
    static let shared = DecodeLatch()
    private let lock = NSLock()
    private var keys: Set<String> = []

    func latch(_ key: String) { lock.lock(); keys.insert(key); lock.unlock() }
    func release(_ key: String) { lock.lock(); keys.remove(key); lock.unlock() }
    func isLatched(_ key: String) -> Bool { lock.lock(); defer { lock.unlock() }; return keys.contains(key) }
}

/// A store with schema version, backup and latch.
///
/// ONE type for all stores instead of six copies of the logic: the defect class
/// (`try?` → `[]` → `save()` overwrites) was reproduced in every new store precisely because
/// each one wrote its own read from scratch.
///
/// The main guarantee: **`save()` is physically impossible after a failed read**. A failed
/// decode used to return an empty list, the UI showed "nothing here", the user added one
/// entry — and it overwrote everything else. The latch breaks this chain at the third step.
struct VersionedStore<Element: Codable> {

    /// Key in UserDefaults.
    let key: String
    /// Name for the log and the backup file.
    let name: String
    /// Store instance. Not always `.standard`: `APIKeyStore` is initialized with its own
    /// (in tests — a temporary domain), and a hardcoded `.standard` would silently write elsewhere.
    let defaults: UserDefaults

    init(key: String, name: String, defaults: UserDefaults = .standard) {
        self.key = key
        self.name = name
        self.defaults = defaults
    }

    // MARK: - Reading

    /// Reads entries. On a failed decode SAVES the original bytes to a file, logs, sets the latch
    /// and returns an empty array — but with writing already forbidden.
    func load() -> [Element] {
        let data = defaults.data(forKey: key)
        switch StoreEnvelope.decode(data, as: Element.self) {
        case .empty:
            return []

        case .ok(let items, let version):
            if version < StoreEnvelope.currentVersion {
                // In-place migration: what was read in the old format is immediately written as an
                // envelope. The data is the same — only the wrapper changes, so it's safe and
                // happens once.
                Log.info(.app, "\(name): миграция схемы \(version) → \(StoreEnvelope.currentVersion), записей \(items.count)")
                _ = save(items, migrating: true)
            }
            return items

        case .corrupted(let raw, let reason):
            DecodeLatch.shared.latch(key)
            let backup = writeBackup(raw)
            Log.error(.app, """
                \(name): ДАННЫЕ НЕ ПРОЧИТАНЫ — \(LogSanitizer.sanitize(reason)). \
                Запись по этому ключу заблокирована до перезапуска, чтобы не затереть их пустотой. \
                Копия: \(backup?.path ?? "НЕ СОЗДАНА")
                """)
            NotificationCenter.default.post(name: .storeDecodeFailed, object: nil,
                                            userInfo: ["store": name,
                                                       "backup": backup?.path as Any])
            return []
        }
    }

    // MARK: - Writing

    /// Returns `false` if the write was rejected by the latch. The caller must treat it as a
    /// refusal, not as "saved silently".
    @discardableResult
    func save(_ items: [Element], migrating: Bool = false) -> Bool {
        if !migrating, DecodeLatch.shared.isLatched(key) {
            Log.error(.app, "\(name): запись ОТКЛОНЕНА — чтение этого хранилища ранее провалилось")
            return false
        }
        do {
            let data = try StoreEnvelope.encode(items)
            defaults.set(data, forKey: key)
            return true
        } catch {
            Log.error(.app, "\(name): не удалось закодировать (\(LogSanitizer.sanitize(error.localizedDescription)))")
            return false
        }
    }

    /// Only for tests and for recovery after a deliberate user decision.
    static func releaseLatch(_ key: String) { DecodeLatch.shared.release(key) }

    var isLatched: Bool { DecodeLatch.shared.isLatched(key) }

    // MARK: - Backup

    private func writeBackup(_ raw: Data) -> URL? {
        let fm = FileManager.default
        guard let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let dir = base.appendingPathComponent("Keyly/backups", isDirectory: true)
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = dir.appendingPathComponent(
                StoreEnvelope.backupFileName(store: name, at: Date()))
            try raw.write(to: url)
            return url
        } catch {
            return nil
        }
    }
}

extension Notification.Name {
    /// A store read failed. The listener shows a badge: silent data loss is worse than a loud
    /// error, and the user must learn about it right away, not a week later.
    static let storeDecodeFailed = Notification.Name("keyly.storeDecodeFailed")
}
