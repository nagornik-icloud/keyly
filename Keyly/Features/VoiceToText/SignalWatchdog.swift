import Foundation

/// Input signal watchdog.
///
/// Catches exactly ONE thing: the input DROPPED (headset unplugged, device disappeared) — then digital
/// zero is written to the file while the user sees the timer running and talks into the void. A pause
/// in speech, thinking, a quiet room — are NOT this.
///
/// Works in DECIBELS, not linear level. Reason: a linear scale can't tell "quiet" from "dead". The
/// previous code converted dB to linear with a cutoff `decibels <= -60 → 0`, so ANY quiet room was
/// declared digital zero, the watchdog fired, and recording stopped by itself whenever the user paused
/// to think for three seconds. It showed up on the very first real use: "I start talking, go quiet —
/// the recording ends by itself although I didn't end it".
///
/// In dB the difference is obvious: a live microphone in a quiet room gives −50…−70 dB (room noise
/// and the device's own noise), while a dropped input gives −120…−160 dB, i.e. the scale floor.
///
/// Pure type: the "input lost" decision is checked by a test, not by unplugging headphones by hand.
struct SignalWatchdog {
    /// Below this there is NO signal at all. Not "quiet" but a dead input: a live microphone
    /// never drops this low, even in a soundproof room.
    static let deadInputDecibels: Float = -110
    /// How long we tolerate it. Eight seconds: a "thinking mid-sentence" pause can last five seconds,
    /// but a dropped input won't fix itself within eight.
    static let timeout: TimeInterval = 8.0

    private var silentSince: TimeInterval?

    enum Verdict: Equatable {
        case ok
        /// No signal for longer than the timeout, but there WAS one before: the input dropped mid-recording
        /// (headset unplugged, device disappeared).
        case lost
        /// There has been NO signal since the recording started. This is not "dropped" but "not granted":
        /// macOS can return `.authorized` for the permission and still deny access to the device
        /// ("HALS_IOContext: Client is not granted access to the input device"), and
        /// `AVAudioRecorder.record()` still returns `true` in that case. The user then needs the
        /// "Microphone" section in settings, not a story about the headset.
        case neverStarted
    }

    /// Whether this recording has had at least one live sample. That is what tells "access not granted"
    /// apart from "dropped along the way".
    private var everHadSignal = false

    /// Feeds the next sample IN DECIBELS (what `averagePower` returns).
    /// `now` is passed in so the test doesn't have to actually sleep.
    mutating func feed(decibels: Float, now: TimeInterval) -> Verdict {
        guard decibels <= Self.deadInputDecibels else {
            everHadSignal = true
            silentSince = nil
            return .ok
        }
        guard let since = silentSince else {
            silentSince = now
            return .ok
        }
        guard now - since >= Self.timeout else { return .ok }
        return everHadSignal ? .lost : .neverStarted
    }

    /// Reset after stopping: the next recording starts with a clean counter.
    mutating func reset() {
        silentSince = nil
        everHadSignal = false
    }
}
