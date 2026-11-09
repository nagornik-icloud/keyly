import Foundation

enum AppRunMode {
    /// Debug tool runs (screenshots, probes, galleries — any `KEYLY_*` variable) must never
    /// touch the user's real data or other running apps. The caret probe is the exception:
    /// it is switched on during normal work.
    static var isToolRun: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.environment.keys.contains {
            $0.hasPrefix("KEYLY_") && $0 != "KEYLY_CARET_DEBUG"
        }
        #else
        return false
        #endif
    }
}
