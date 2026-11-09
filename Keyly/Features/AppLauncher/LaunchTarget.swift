import Foundation

/// What exactly a launcher target opens.
///
/// Launching used to go only through `openApplication(at:)`, which handles apps only. Folders,
/// files and links silently failed to open: the hotkey fired, the log had an error, nothing
/// happened on screen.
enum LaunchTarget: Equatable {
    /// An app — can be activated, and hidden by pressing again.
    case application(bundleId: String?, url: URL)
    /// A folder or file — opened with its associated app.
    case file(url: URL)
    /// A link — opened in the default browser.
    case link(url: URL)

    /// Classifies the string saved in the target. It may be a path or a URL; they can't be
    /// parsed the same way — "/Applications/Safari.app" and "https://…" behave differently, and
    /// mixing them up means a hotkey that silently does nothing.
    static func resolve(_ raw: String, bundleIdentifier: (URL) -> String? = { _ in nil }) -> LaunchTarget? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(),
           scheme != "file", !scheme.isEmpty {
            return .link(url: url)
        }

        let url = URL(fileURLWithPath: trimmed)
        if url.pathExtension.lowercased() == "app" {
            return .application(bundleId: bundleIdentifier(url), url: url)
        }
        return .file(url: url)
    }

    /// Default name for the list row. For a link it's the host: a full URL in the row crowds
    /// out everything else and is unreadable anyway.
    static func suggestedName(for raw: String) -> String {
        switch resolve(raw) {
        case .link(let url):
            return url.host ?? url.absoluteString
        case .application(_, let url), .file(let url):
            return url.deletingPathExtension().lastPathComponent
        case nil:
            return raw
        }
    }
}
