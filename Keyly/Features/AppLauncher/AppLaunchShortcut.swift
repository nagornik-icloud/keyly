import Foundation

struct AppLaunchShortcut: Identifiable, Codable, Equatable {
    let id: UUID
    var appPath: String
    var appName: String
    var keyCombo: KeyCombo?
    /// Bookmark to the target. A path breaks silently: the app moved to another folder or was
    /// renamed — the hotkey fires, there is nothing to open, and the app gives no clue why.
    /// A bookmark survives moves and renames.
    ///
    /// Optional: targets created before bookmarks existed don't have one, and losing saved
    /// shortcuts because of that is not acceptable — the path stays a working fallback.
    var bookmark: Data?

    init(id: UUID = UUID(), appPath: String, appName: String? = nil,
         keyCombo: KeyCombo?, bookmark: Data? = nil) {
        self.id = id
        self.appPath = appPath
        self.appName = appName ?? URL(fileURLWithPath: appPath).deletingPathExtension().lastPathComponent
        self.keyCombo = keyCombo
        self.bookmark = bookmark
    }

    /// Current path to the target: bookmark first, then the saved string.
    ///
    /// Resolving the bookmark may return a DIFFERENT path — that is the whole point: the app
    /// moved, and the target still works.
    var resolvedURL: URL {
        guard let bookmark else { return URL(fileURLWithPath: appPath) }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark,
                                 options: [.withoutUI],
                                 bookmarkDataIsStale: &stale) else {
            return URL(fileURLWithPath: appPath)
        }
        return url
    }

    /// Bookmark for a URL. Doesn't throw: a target without a bookmark is better than a target
    /// that couldn't be created — it will still open by path.
    static func makeBookmark(for url: URL) -> Data? {
        try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    var displayName: String {
        appName.isEmpty ? URL(fileURLWithPath: appPath).deletingPathExtension().lastPathComponent : appName
    }
}
