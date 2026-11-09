import AppKit

/// A store's data couldn't be read: the raw bytes were saved aside and writes are blocked
/// (VersionedStore). Without telling the user, they'd just see an empty list.
/// Shown once per store per launch.
@MainActor
final class StoreFailureAlert {
    private var shown: Set<String> = []
    private var observer: Any?

    func startObserving() {
        observer = NotificationCenter.default.addObserver(forName: .storeDecodeFailed, object: nil,
                                                          queue: .main) { [weak self] note in
            let store = note.userInfo?["store"] as? String ?? "?"
            let backup = note.userInfo?["backup"] as? String
            MainActor.assumeIsolated { self?.present(store: store, backup: backup) }
        }
    }

    private func present(store: String, backup: String?) {
        guard shown.insert(store).inserted else { return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "store.decodeFailed.title".loc
        alert.informativeText = backup.map { "store.decodeFailed.message".loc($0) }
            ?? "store.decodeFailed.noBackup".loc
        alert.addButton(withTitle: "common.ok".loc)
        alert.runModal()
    }
}
