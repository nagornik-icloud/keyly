import SwiftUI
import Combine

/// "Top center" dictation indicator (the default mode): dot + wave + timer,
/// and after stop the same capsule in the "processing" phase.
///
/// The previous version used the old visual language: `.ultraThinMaterial` glass, radius 18,
/// `Color.red`, `.primary`, a system borderless button. Moved to "Mono": the shared
/// floating plate recipe (`keylyOverlayPlate`) and tokens, so the overlay is one family with the badge,
/// the toast and the compact indicator; it hangs over other windows and is seen more often than any screen.
struct VoiceRecordingView: View {
    let elapsedProvider: () -> Int
    let onCancel: () -> Void
    /// Kept for call-site compatibility: the look is now the same for both positions.
    var compact: Bool = false
    /// Pill phase. Lives outside: "processing" continues after the recording
    /// is closed, so the look must not be tied to the session.
    @ObservedObject var state: VoiceOverlayState

    @ObservedObject private var meter = InputLevelMeter.shared
    @State private var now = Date()

    var body: some View {
        // One look for both positions, at the caret and at top center. The previous
        // full-size 280pt pill with a Cancel button
        // covered half the screen for a timer that reads fine in a capsule.
        content
            .fixedSize()
            // Padding comes from the `Theme.Space` scale (16/12). It was 18/12: 18 is not on the 4/8 scale,
            // and this was the only overlay in the product with its own horizontal padding.
            .padding(.horizontal, Theme.Space.l)
            .padding(.vertical, Theme.Space.m)
            // NO border: a light edge was rejected as visually noisy, so the
            // SHADOW holds the shape. That is why the shadow is more noticeable than the shared one, denser and wider; otherwise
            // a borderless capsule loses its edge. A deliberate trade-off: a border measured
            // >= 3:1 against all backdrops, a shadow cannot reach that number, but the
            // borderless look was chosen after seeing it live.
            .background(
                Capsule()
                    .fill(Theme.Elevation.fill)
                    .shadow(color: .black.opacity(Theme.Elevation.pillShadowOpacity),
                            radius: Theme.Elevation.pillShadowRadius,
                            y: Theme.Elevation.pillShadowY)
                    .shadow(color: .black.opacity(Theme.Elevation.pillContactOpacity),
                            radius: Theme.Elevation.pillContactRadius,
                            y: Theme.Elevation.pillContactY)
            )
            .animation(KeylyMotion.emphasis, value: state.phase)
            .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { value in
                now = value
            }
    }

    private var isProcessing: Bool { state.phase == .processing }

    @ViewBuilder
    private var content: some View {
        if state.phase == .copied {
            VoiceCopiedRow()
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("voice.state.copied".loc)
        } else if isProcessing {
            VoiceStatusRow(titleKey: "voice.state.finalizing", isProcessing: true)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("voice.state.finalizing".loc)
        } else {
            recordingRow
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("voice.state.recording".loc)
                .accessibilityValue(timerText)
                .accessibilityHint("voice.pill.cancelHint".loc)
        }
    }

    private var recordingRow: some View {
        HStack(spacing: 12) {
            RecordingDot()
            // Live wave: shows the microphone REALLY hears. Without it the pill looks the same
            // with a working input and with a disconnected headset, and those are two very
            // different situations for someone who is speaking at that moment.
            VoiceWave(mode: .live(meter.level))
            // The timer is QUIET. It used to be mono 17 semibold in
            // full fg and its weight took over the pill, even though the main thing there is the wave: it
            // alone answers "can they hear me?". Now it is 12 medium in fgMuted,
            // roughly the weight of the red dot on the left: dot · WAVE · timer.
            Text(timerText)
                .font(Theme.Typography.mono(12, .medium))
                .foregroundStyle(Theme.Colors.fgMuted)
                .monospacedDigit()
                // Without this the timer wraps per character into a column, and the capsule
                // collapses into a circle: the pill has no set width.
                .fixedSize()
            // There is NO "esc to cancel" caption here: seen live, it was
            // judged clutter. The exit itself works and stays: Esc cancels the operation via
            // OperationGate; the caption was removed, not the mechanism. The pill hangs over another window
            // and should stay minimal.
            // The hint is kept for VoiceOver in `accessibilityHint` below.
        }
        .frame(height: VoiceWave.height)
    }

    private var timerText: String {
        _ = now
        let elapsed = elapsedProvider()
        return String(format: "%d:%02d", elapsed / 60, elapsed % 60)
    }
}
