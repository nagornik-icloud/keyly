import AppKit
import Combine
import SwiftUI

/// What the dictation pill is showing right now.
///
/// There used to be ONE phase, "recording", and the pill was removed the moment
/// the user released the hotkey. Then recognition ran: seconds during which ABSOLUTELY NOTHING
/// happened on screen and the text had not appeared yet. That is indistinguishable from "it did not work",
/// and people pressed the hotkey a second time.
enum VoiceOverlayPhase {
    case recording
    /// Recording ended, recognition/processing is running. The pill STAYS on screen and changes its look.
    case processing
    /// Text was inserted and also left on the clipboard; shown briefly, then the plate hides.
    case copied
}

/// Pill state that lives SEPARATELY from the recording session.
///
/// Separately because "processing" continues AFTER the session is closed and
/// its object released: tying the look to the session would hide the indicator exactly where
/// it is needed most.
@MainActor
final class VoiceOverlayState: ObservableObject {
    @Published var phase: VoiceOverlayPhase = .recording {
        didSet {
            guard phase != oldValue else { return }
            announce()
        }
    }

    /// The phase change is the key moment of the feature, and for a blind user it must be an EVENT, not
    /// a silent change of pixels: the pill lives in a non-activating window, focus never enters
    /// it, and VoiceOver will not announce it on its own.
    private func announce() {
        let text: String
        switch phase {
        case .recording:  text = "voice.state.recording".loc
        case .processing: text = "voice.state.finalizing".loc
        case .copied:     text = "voice.state.copied".loc
        }
        NSAccessibility.post(element: NSApp as Any,
                             notification: .announcementRequested,
                             userInfo: [.announcement: text,
                                        .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }
}

/// Who currently occupies the top center of the screen.
///
/// The recording pill, toast and badge all go to ONE spot. While
/// the pill only lived during recording they barely overlapped; now it stays for the whole
/// processing, and the toast shows a recognition error exactly at its end. Without this marker
/// the toast would slide UNDER the pill (it sits at a higher level) and stick out at the edges.
@MainActor
enum TopCenterOverlaySlot {
    /// Height of the occupying pill plus its offset from the edge. 0 means the top is free.
    private(set) static var occupiedHeight: CGFloat = 0

    static func occupy(height: CGFloat) { occupiedHeight = height }
    static func release() { occupiedHeight = 0 }

    /// How much lower than usual a surface must sit to avoid overlapping the pill.
    static var dropDown: CGFloat { occupiedHeight > 0 ? occupiedHeight + Theme.Space.s : 0 }
}

/// Pill content in the NON-recording phases: "connecting" and "processing".
///
/// One layout for both, the same as recording: dot · wave · right column. The pill
/// CHANGES on a phase change but does not turn into a different object: "connecting" used to
/// be a bare 90pt circle that expanded on the first word into a capsule three times
/// wider, and it read as a swap, not a transition.
///
/// The dot is gray and still (recording is not running, so we must not promise otherwise), the wave runs on its own
/// (there is no input level here, but work is happening, and only motion can show it), and
/// a caption takes the timer's place: a frozen counter reads as a hang, not as work.
struct VoiceStatusRow: View {
    /// Catalog key with the phase caption.
    let titleKey: String
    /// `true` means processing (input already happened), `false` means connecting (no input yet).
    /// Distinguishes more than the caption: arrow direction and presence of the wave.
    var isProcessing: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            // The shape DISTINGUISHES the ends of the flow, not just the word. "Connecting" (arrow down:
            // still going in) and "Processing" (arrow up: already handing off) used to be frames
            // distinguishable only by caption: at a glance you could not tell whether you had
            // started recording or already finished.
            Image(systemName: isProcessing ? "arrow.up.circle" : "arrow.down.circle")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.Colors.fgMuted)
                .frame(width: 17)
            // The wave appears ONLY once there is input. In "Connecting" the microphone is not open yet,
            // and a running wave with 4…17.6pt amplitude was TALLER than the live wave of quiet speech (capped
            // at 10pt in silence): the "not hearing yet" phase looked more active than
            // the "hearing" phase. Motion must appear the moment input opens, otherwise it
            // lies about the most important thing.
            if isProcessing {
                VoiceWave(mode: .processing)
            }
            Text(titleKey.loc)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.Colors.fgMuted)
                .fixedSize()
            // There is NO processing seconds counter HERE: seen live, it was
            // judged noise and removed. The running wave carries the sign of life.
            //
            // The trade-off is explicit: with system "Reduce motion" the wave freezes
            // (`VoiceWave` honors the flag), and then nothing on the pill moves;
            // the counter existed for exactly that case.
        }
        .frame(height: VoiceWave.height)
    }
}

/// Final state of the plate: dictation is done and the text is also on the clipboard.
struct VoiceCopiedRow: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.Colors.fgMuted)
                .frame(width: 17)
            Text("voice.state.copied".loc)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.Colors.fgMuted)
                .fixedSize()
        }
        .frame(height: VoiceWave.height)
    }
}
