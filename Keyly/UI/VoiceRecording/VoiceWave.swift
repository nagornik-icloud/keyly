import SwiftUI

/// The voice wave: ONE for the whole product.
///
/// **How it works and why.**
///
/// Earlier versions drew a STATIC silhouette: each bar had its own multiplier, and
/// loudness merely SCALED that silhouette. It looked as if each bar had its own
/// fixed height that just grew or shrank with the noise level, with
/// no interactivity at all. Speaking without pauses froze the picture; only its size changed.
///
/// A real equalizer looks different: bars move up and down INDEPENDENTLY and do not
/// stop while there is sound. That is what is done here:
/// * TIME is a required input. A frame is computed from the clock, not from the last level sample,
///   so motion does not freeze at steady loudness.
/// * Each bar has ITS OWN oscillator: a sum of two sines with incommensurate frequencies and
///   its own phase. The sum has no common period: the pattern never loops, neighbors do not march in step.
/// * LOUDNESS sets only the ENVELOPE: quiet gives small ripples, loud gives full-height swings.
///   Silence reduces motion, it does not turn it off.
///
/// Why not a real FFT over frequencies: `AVAudioRecorder` exposes only a scalar
/// (`averagePower`) with no buffer access, and a second tap on the same microphone
/// is not allowed: two open inputs on macOS give either a device failure or a silent track in one
/// of them (the same warning is in `InputLevelMeter`). So the spectrum is not measured but
/// plausibly synthesized: a "you are heard" indicator needs motion in time with loudness,
/// not spectral accuracy.
struct VoiceWave: View {
    enum Mode: Equatable {
        case live(Float)
        case processing
    }

    let mode: Mode
    /// Bars are slightly LIGHTER than the timer: the wave is
    /// the pill's main element and must not drown in the same tone as the caption.
    var tint: Color = Theme.Colors.waveform

    /// Geometry shared by both modes and both pills.
    static let barCount = WaveformMath.barCount
    static let barWidth: CGFloat = 3
    static let barSpacing: CGFloat = 2
    static let height: CGFloat = CGFloat(WaveformMath.maxBar)
    static let minBar: CGFloat = CGFloat(WaveformMath.minBar)

    /// Below this level the input is considered DEAD and the wave becomes a flat line.
    ///
    /// The threshold is deliberately near zero. The previous one (0.04 on the normalized scale) flattened quiet
    /// background music into a line, even though the computer clearly heard something.
    /// Now quiet sound gives small but LIVE movement, and the line remains only where
    /// there really is no signal.
    static let deadBelow: Float = WaveformMath.deadBelow


    var body: some View {
        // BOTH modes need the clock, "hearing voice" and "processing": motion must not
        // depend on whether new level samples arrive.
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: KeylyMotion.isReduced)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            switch mode {
            case .live(let level):
                bars { index in Self.liveHeight(level: level, time: t, index: index) }
            case .processing:
                bars { index in Self.processingHeight(time: t, index: index) }
            }
        }
    }

    private func bars(_ height: @escaping (Int) -> CGFloat) -> some View {
        HStack(spacing: Self.barSpacing) {
            ForEach(0..<Self.barCount, id: \.self) { index in
                Capsule()
                    .fill(tint)
                    .frame(width: Self.barWidth, height: height(index))
            }
        }
        .frame(height: Self.height)
    }

    /// Bar height is computed in `WaveformMath` (a pure type without SwiftUI), because
    /// wave motion is verified by a TEST, not by eye on a screenshot: a single frame shows
    /// neither bars moving in sync nor the picture freezing at steady
    /// loudness, which is exactly what two earlier attempts missed.
    static func liveHeight(level: Float, time: TimeInterval, index: Int) -> CGFloat {
        CGFloat(WaveformMath.liveHeight(level: level, time: time, index: index))
    }

    static func processingHeight(time: TimeInterval, index: Int) -> CGFloat {
        CGFloat(WaveformMath.processingHeight(time: time, index: index))
    }
}
