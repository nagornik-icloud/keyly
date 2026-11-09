import Foundation

/// Dictation waveform arithmetic — WITHOUT SwiftUI and without a runtime.
///
/// Extracted from the view because two earlier attempts at this waveform failed the same way:
/// looking at a single frame you can see neither that the bars move IN SYNC nor that the picture
/// FREEZES at a steady volume. A frame shows one moment in time, while the problem is about
/// motion over time. That can only be caught by a test.
enum WaveformMath {

    static let barCount = 13
    /// Minimum bar height — also the height of the "flat line" with a dead input.
    static let minBar: Double = 4
    static let maxBar: Double = 22
    /// Below this level the input counts as dead: the waveform becomes a flat line.
    static let deadBelow: Float = 0.002

    /// Each bar's own frequency (revolutions per second), deliberately incommensurable: the sum
    /// of sines must have no common period, otherwise the bars sync up and march in step.
    static let rate: [Double] = [5.3, 7.1, 4.7, 8.3, 6.1, 9.7, 5.9,
                                 7.7, 4.3, 8.9, 6.7, 5.1, 7.3]
    /// Starting phases — so the bars don't line up at one height on the very first frame.
    static let phase: [Double] = [0.0, 2.4, 4.1, 1.3, 5.6, 3.2, 0.7,
                                  4.8, 2.0, 5.1, 1.7, 3.9, 2.8]
    /// Per-bar "height": the edges stay lower than the middle even at full volume, otherwise the
    /// waveform looks like a rectangular block.
    static let gain: [Double] = [0.55, 0.78, 0.92, 1.0, 0.88, 0.96, 1.0,
                                 0.94, 0.86, 1.0, 0.90, 0.74, 0.52]

    /// Height of bar `index` at time `time` with volume `level` (0…1).
    ///
    /// Volume sets only the ENVELOPE; the bar's motion is driven by time. So the picture stays
    /// alive even at a constant volume — it should look like an equalizer, not like each bar
    /// having its own height that merely follows the noise level.
    static func liveHeight(level: Float, time: TimeInterval, index: Int) -> Double {
        guard level > deadBelow else { return minBar }
        let clamped = Double(min(max(level, 0), 1))
        let envelope = clamped.squareRoot()
        let i = index % barCount
        let fast = sin(time * rate[i] + phase[i])
        let slow = sin(time * rate[i] * 0.37 + phase[i] * 1.7)
        let wobble = (fast * 0.65 + slow * 0.35 + 1) / 2      // 0…1
        let span = (maxBar - minBar) * gain[i] * envelope
        return minBar + span * (0.25 + 0.75 * wobble)
    }

    /// Bar height of the traveling wave in the "processing" phase.
    static func processingHeight(time: TimeInterval, index: Int) -> Double {
        let wave = (sin(time * 3.0 - Double(index) * 0.55) + 1) / 2
        return minBar + (maxBar - minBar) * wave * 0.85
    }
}
