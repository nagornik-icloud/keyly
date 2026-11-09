import Foundation

/// A single session for all LLM and speech recognition calls (an LLM request fails on a
/// 60 s timeout).
///
/// Why a separate home rather than `timeoutInterval` on each request: the rule is one for the
/// whole product, while there are six places that create requests — a number set by hand would
/// inevitably drift, and a missed spot could only be found through a hung app.
///
/// What exactly is limited — the distinction matters:
/// - `timeoutIntervalForRequest` — a pause WITHOUT new data. We have no streaming, the response
///   arrives whole, so for regular requests this is exactly the wait ceiling we want.
/// - `timeoutIntervalForResource` — the ceiling for the whole operation. It's noticeably larger:
///   uploading an audio file for recognition on a slow network legitimately takes over a
///   minute, and cutting it at 60 s would break a working scenario rather than save from a hang.
enum LLMSession {

    /// Response wait ceiling.
    static let requestTimeout: TimeInterval = 60

    /// Ceiling for the whole operation — with headroom for uploading audio.
    static let resourceTimeout: TimeInterval = 300

    static let shared: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = requestTimeout
        config.timeoutIntervalForResource = resourceTimeout
        // Model responses must not be cached: an identical request must go to the network again,
        // otherwise "Run again" returns the previous result and looks like a stuck setting.
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()
}
