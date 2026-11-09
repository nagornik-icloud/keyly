import Foundation

enum SnippetStore {

    /// Store with schema version, backup copy and write latch.
    /// The previous implementation read via `try?` and returned `[]` on any decode error —
    /// and the next save wiped the user's data with an empty list.
    private static let store = VersionedStore<Snippet>(key: SettingsKeys.snippets,
                                                       name: "snippets")

    static func load() -> [Snippet] { store.load() }

    /// Returns `false` if the write was rejected by the latch (reading failed earlier).
    /// The notification is sent only after a SUCCESSFUL write: otherwise listeners would re-read
    /// the store and decide that the list really became empty.
    @discardableResult
    static func save(_ snippets: [Snippet]) -> Bool {
        guard store.save(snippets) else { return false }
        NotificationCenter.default.post(name: .snippetsChanged, object: nil)
        return true
    }
}
