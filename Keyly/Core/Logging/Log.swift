import Foundation
import OSLog

/// The single logging entry point. Replaces scattered NSLog calls across the project.
///
/// The key property — **the sanitizer is ALWAYS applied**, not left to the caller's memory.
/// A key leaks in transit: Gemini used to carry it in a URL query parameter, an `NSError` from
/// URLSession carries the full URL, and an innocent "let's log the error" puts a live key into
/// the system log. While the sanitizer had to be called by hand, every new raw error log
/// reopened the hole — so the duty was taken off the caller and built into the facade.
///
/// What the facade does NOT do: decide for the caller whether user TEXT may be logged.
/// Transcripts, field contents and snippets are not logged at all — only lengths.
enum Log {

    enum Category: String, CaseIterable {
        case hotKey     = "HotKey"
        case layout     = "Layout"
        case errorFix   = "ErrorFix"
        case voice      = "Voice"
        case snippets   = "Snippets"
        case modules    = "CustomModules"
        case launcher   = "AppLauncher"
        case undo       = "Undo"
        case app        = "App"
        case ui         = "UI"
        case network    = "Network"
        // The caret probe and the input injector kept THEIR OWN os.Logger instances — bypassing the
        // facade, and thus the sanitizer. They didn't write text, but the guarantee "user text never
        // gets into the log" rested on attentiveness, not on a mechanism: any next line in those
        // files could break it unnoticed.
        case caret      = "CaretProbe"
        case input      = "TextInjector"
    }

    private static let subsystem = AppIdentity.logSubsystem

    /// Built ONCE and immutable afterwards: logging happens from different threads, and a mutable
    /// static cache here is a race (caught by Swift 6 strict mode in the test package).
    private static let loggers: [Category: Logger] = {
        var map: [Category: Logger] = [:]
        for category in Category.allCases {
            map[category] = Logger(subsystem: subsystem, category: category.rawValue)
        }
        return map
    }()

    private static func logger(_ category: Category) -> Logger {
        loggers[category] ?? Logger(subsystem: subsystem, category: category.rawValue)
    }

    /// Normal flow of events.
    static func info(_ category: Category, _ message: @autoclosure () -> String) {
        emit(category, message(), level: .info)
    }

    /// A deviation we continue working with (fallback, retry, skip).
    static func warn(_ category: Category, _ message: @autoclosure () -> String) {
        emit(category, message(), level: .warn)
    }

    /// The operation was not performed.
    static func error(_ category: Category, _ message: @autoclosure () -> String) {
        emit(category, message(), level: .error)
    }

    private enum Level { case info, warn, error }

    private static func emit(_ category: Category, _ raw: String, level: Level) {
        // `.public` here is safe and deliberate: the string has already passed the sanitizer, and a
        // readable log is needed — otherwise diagnostics turn into a wall of "<private>".
        let safe = LogSanitizer.sanitize(raw)
        let log = logger(category)
        switch level {
        // `.notice`, not `.info`: the info level in unified logging lives ONLY in memory and never
        // reaches disk — `log show` over ten minutes of work returned zero entries, and the log
        // export for bug reports would produce an empty file. Verified: `log stream` saw the events,
        // `log show` did not.
        case .info:  log.notice("\(safe, privacy: .public)")
        case .warn:  log.warning("\(safe, privacy: .public)")
        case .error: log.error("\(safe, privacy: .public)")
        }
    }
}
