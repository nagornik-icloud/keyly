import SwiftUI
import Combine

/// Compact capsule indicator for dictation in streaming mode.
/// Three phases: connecting -> recording (dot + live wave + optional timer) -> processing.
struct RealtimeIndicatorView: View {
    @ObservedObject var session: RealtimeVoiceSession
    let elapsedProvider: () -> Int
    let showTimer: Bool
    /// The pill phase comes from outside: "processing" outlives the session itself (see `VoiceOverlayState`).
    @ObservedObject var state: VoiceOverlayState

    @State private var now = Date()

    var body: some View {
        content
            // Same tokens as the batch pill (18 is not on the 4/8 scale).
            .padding(.horizontal, Theme.Space.l)
            .padding(.vertical, Theme.Space.m)
            // The capsule looks THE SAME as the batch recording pill. Two states
            // of one feature used to look different:
            // a rectangular plate in streaming mode and a capsule in batch mode.
            // No border, the shadow holds the shape, exactly like the batch pill.
            // One recipe for both, so they do not drift apart.
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
            .fixedSize()
            .animation(KeylyMotion.emphasis, value: isConnecting)
            .animation(KeylyMotion.emphasis, value: isFinalizing)
            .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { t in
                now = t
            }
    }

    /// Total capsule height: needed by whoever computes where neighboring surfaces go.
    static var capsuleHeight: CGFloat { VoiceWave.height + 24 }

    /// While connecting to the Realtime API there is no recording yet: show a neutral
    /// spinner, NOT a red dot + wave, so it cannot be mistaken for recording.
    private var isConnecting: Bool {
        guard !isFinalizing else { return false }
        switch session.state {
        case .idle, .connecting: return true
        default:                 return false
        }
    }

    /// "Processing". There are two sources, both legitimate: the session itself announced finalization,
    /// or dictation already stopped and post-processing is running, with no session at that moment.
    private var isFinalizing: Bool {
        if state.phase == .processing { return true }
        if case .finalizing = session.state { return true }
        return false
    }

    @ViewBuilder
    private var content: some View {
        if isFinalizing {
            // One "processing" look for both recognition modes: a shared home
            // (`VoiceStatusRow`), not a second implementation of the same phase.
            VoiceStatusRow(titleKey: "voice.state.finalizing", isProcessing: true)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("voice.state.finalizing".loc)
        } else if isConnecting {
            // "Connecting" is no longer a system spinner in an empty capsule: same layout
            // as the neighboring phases; otherwise the pill changed shape, not just look, and at the first
            // word expanded from a circle into a capsule three times wider.
            // This also drops `ProgressView`, which `ImageRenderer` did not capture at all: the phase
            // was missing from the QA screenshots entirely.
            VoiceStatusRow(titleKey: "voice.state.connecting")
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("voice.state.connecting".loc)
        } else {
            recordingContent
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("voice.state.recording".loc)
                .accessibilityValue(timerText)
        }
    }

    private var recordingContent: some View {
        HStack(spacing: 12) {
            // Shared recording dot (see `RecordingDot`): there used to be a separate one here, white with
            // a different pulse, so the same process looked different in the two modes.
            RecordingDot()
            // The wave is shared with the batch pill (`VoiceWave`). There used to be separate
            // geometry here: seven 2.5pt bars vs nine 3pt bars, i.e. one signal drawn as two
            // different pictures depending on the mode.
            VoiceWave(mode: .live(session.level))
            // The word "Recording" is removed: the dot and the live wave say it better than a label, and
            // space in the capsule is expensive.
            if showTimer {
                // A quiet timer, as in the batch pill: the wave is the main thing on the capsule.
                Text(timerText)
                    .font(Theme.Typography.mono(12, .medium))
                    .foregroundStyle(Theme.Colors.fgMuted)
                    .monospacedDigit()
                    .fixedSize()
            }
        }
        .frame(height: VoiceWave.height)
    }

    private var timerText: String {
        _ = now
        let elapsed = elapsedProvider()
        return String(format: "%d:%02d", elapsed / 60, elapsed % 60)
    }
}

#if DEBUG
private struct IndicatorPreviewWrapper: View {
    let level: Float
    let state: RealtimeVoiceSession.State
    let showTimer: Bool

    var body: some View {
        // Top center, as in the real window.
        ZStack(alignment: .top) {
            // Simulated desktop to judge the glass on different backgrounds.
            LinearGradient(colors: [.blue, .purple, .black],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            RealtimeIndicatorView(
                session: .previewMock(level: level, state: state),
                elapsedProvider: { 5 },
                showTimer: showTimer,
                state: VoiceOverlayState()
            )
            .padding(.top, 16)
        }
        .frame(width: 520, height: 220)
    }
}

#Preview("Запись · громко · таймер") {
    IndicatorPreviewWrapper(level: 0.85, state: .recording, showTimer: true)
}

#Preview("Запись · тихо · без таймера") {
    IndicatorPreviewWrapper(level: 0.15, state: .recording, showTimer: false)
}

#Preview("Подключение") {
    IndicatorPreviewWrapper(level: 0.0, state: .connecting, showTimer: true)
}
#endif
