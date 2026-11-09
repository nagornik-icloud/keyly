/// Decides whether a synthetic Cmd+C actually put new text on the clipboard.
///
/// Every capture path sends Cmd+C and then reads the clipboard. If nothing was selected,
/// the clipboard still holds the user's previous content — which must never be treated
/// as "the selection", or it gets sent to the AI provider.
enum CopyDetection {
    /// Returns the copied text, or nil when the copy did not happen.
    /// - Parameters:
    ///   - text: current clipboard string.
    ///   - startCount: `NSPasteboard.changeCount` right before Cmd+C.
    ///   - currentCount: `changeCount` now.
    ///   - initialText: clipboard string right before Cmd+C.
    static func freshText(_ text: String?, startCount: Int, currentCount: Int, initialText: String?) -> String? {
        guard let text, !text.isEmpty else { return nil }
        let copied = currentCount != startCount || text != (initialText ?? "")
        return copied ? text : nil
    }
}
