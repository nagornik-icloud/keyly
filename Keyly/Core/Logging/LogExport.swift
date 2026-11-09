import Foundation

/// Exports the log to a file for a bug report.
///
/// The log goes to the system's unified logging, not to our own file — so "rotation by size
/// and age" is not our problem: macOS keeps the retention window and cleans up old entries.
/// One task remains: give the user a file to attach to an email.
///
/// Read via `log show` — the only supported way to get entries out. Read ONLY our own: a
/// subsystem predicate, otherwise the whole system stream, including other apps, would end
/// up in the file.
enum LogExport {

    /// How much history to take. More than a day isn't needed in a bug report, and size grows linearly.
    static let window = "1d"

    enum ExportError: Error {
        case toolFailed(status: Int32)
        case empty
    }

    /// Writes the log to the given file. Returns the line count — zero is a result too, and it
    /// must be reported: people read "empty file" as a broken export.
    @discardableResult
    static func write(to url: URL, subsystem: String = AppIdentity.logSubsystem) throws -> Int {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        process.arguments = [
            "show",
            "--predicate", "subsystem == \"\(subsystem)\"",
            "--last", window,
            "--info", "--debug",
            "--style", "syslog",
        ]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        try process.run()
        // Read BEFORE waitUntilExit: the pipe has a limited buffer, and on a large log the process
        // would stall waiting to be read — while we'd be waiting for it to finish.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw ExportError.toolFailed(status: process.terminationStatus)
        }
        guard !data.isEmpty else { throw ExportError.empty }

        try data.write(to: url, options: .atomic)
        let lines = String(data: data, encoding: .utf8)?
            .split(separator: "\n", omittingEmptySubsequences: false).count ?? 0
        Log.info(.app, "Лог выгружен: \(lines) строк")
        return lines
    }

    /// Default file name. The date is in the name because there can be several bug reports, and
    /// "keyly-log.txt" would silently overwrite the first one the second time.
    static func suggestedFileName(now: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: now)
        return String(format: "keyly-log-%04d%02d%02d-%02d%02d.txt",
                      c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0)
    }
}
