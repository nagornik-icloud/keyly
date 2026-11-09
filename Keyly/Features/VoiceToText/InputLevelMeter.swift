import Foundation
import Combine

/// Input level for the indicator on the Voice screen.
///
/// Does NOT open its own capture: two simultaneously open microphone captures on macOS give
/// either a device failure or a silent track in one of them. Values are put here by whoever is
/// already recording — the screen only displays them. No recording — no level, and the bar
/// honestly stays at zero.
@MainActor
final class InputLevelMeter: ObservableObject {
    static let shared = InputLevelMeter()

    /// Normalized level 0…1 — what the waveform draws.
    @Published private(set) var level: Float = 0

    /// Observed maximum for the session. Normal speech a meter from the built-in microphone gives
    /// a linear level around 0.02–0.08 — on a 0…1 scale those are motionless bars, and movement
    /// was visible only when shouting. So the scale stretches to the ACTUAL loudness: loud gives
    /// the same amplitude, quiet is visible too.
    private var observedPeak: Float = 0.02

    /// Peak floor: keeps silence and room noise from inflating to full scale.
    private static let minimumPeak: Float = 0.004
    /// How fast the peak decays. Slowly — otherwise after a loud word the quiet ones immediately
    /// shoot to the ceiling and the waveform jerks.
    private static let peakDecay: Float = 0.997

    /// NOISE GATE: below this RAW level the input counts as silence, and zero is reported.
    ///
    /// Without it auto-gain inflated room noise to half scale: with `raw ≈ 0.005` and a peak floor
    /// of 0.02, `sqrt(raw / peak)` gives 0.5 — so in complete silence the waveform danced at half
    /// amplitude, and the user saw "the mic hears me" when it heard nothing (if the voice can't be
    /// heard over background noise, the bars should be a flat line).
    ///
    /// The threshold is ABSOLUTE and not subject to auto-gain — that's the whole point: the scale
    /// may only stretch to SPEECH, otherwise silence always grows to the ceiling.
    /// 0.0005 linear ≈ −66 dB. The threshold is deliberately LOW: it cuts only a dead input, not
    /// quiet sound. The old 0.012 (≈ −38 dB) cut the normal level of a quiet room and background
    /// music — the waveform went flat while the computer could clearly hear something.
    private static let noiseGate: Float = 0.0005

    private init() {}

    func report(level newLevel: Float) {
        let raw = min(max(newLevel, 0), 1)
        guard raw > Self.noiseGate else {
            // Silence — a flat zero. The bars form a line instead of imitating speech.
            level = 0
            return
        }
        // The peak counts only sound ABOVE the gate: otherwise room noise sets the scale itself.
        observedPeak = max(raw, max(observedPeak * Self.peakDecay, Self.minimumPeak))
        // Measure from the gate, not from zero: the first audible sound should give a visible rise,
        // not the same half scale as noise.
        let span = max(observedPeak - Self.noiseGate, 0.001)
        let above = (raw - Self.noiseGate) / span
        // The square root compresses the top of the scale: without it everything but peaks hugs
        // zero, and the waveform stands still again.
        level = min(1, sqrt(min(max(above, 0), 1)))
    }

    func reset() {
        level = 0
        observedPeak = Self.minimumPeak
    }
}
