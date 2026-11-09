import SwiftUI

/// Dictation try-out on the "Voice" screen.
///
/// A separate view from `ModuleTryOutSection` because the interaction is fundamentally different:
/// there the user TYPES text and clicks "Check", here they SPEAK, and the action has a start
/// and an end. The "TRY IT" header and result styling stay shared — otherwise the same
/// meaning would look two different ways on neighboring screens.
struct VoiceTryOutSection: View {

    /// Whether the try-out is ready. A reason is mandatory: a silent disabled state is not allowed.
    let isReady: Bool
    var notReadyReason: String = ""

    @StateObject private var preview = VoicePreview()
    @AppStorage(SettingsKeys.voiceRecognitionMode) private var modeRaw: String = VoiceRecognitionMode.default.rawValue

    private var isLiveMode: Bool {
        (VoiceRecognitionMode(rawValue: modeRaw) ?? .default).isLive
    }

    private var costHint: String {
        VoiceRecognitionMode(rawValue: modeRaw) == .onDevice
            ? "module.tryOut.voice.hint.local".loc
            : "module.tryOut.voice.hint.cloud".loc
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            SectionLabel(text: "module.tryOut".loc)
            HStack(spacing: Theme.Space.m) {
                Button(buttonTitle) { preview.toggle() }
                    .buttonStyle(KeylySecondaryButtonStyle())
                    .disabled(!isReady || preview.state == .transcribing)
                if preview.isRecording {
                    // A sign that the microphone was really acquired. Without it "pressed and silence"
                    // is indistinguishable from "the button didn't work".
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Theme.Colors.danger)
                            .frame(width: 7, height: 7)
                        Text("module.tryOut.voice.recording.hint".loc)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.fgMuted)
                    }
                }
                Spacer(minLength: 0)
            }
            if !isReady, !notReadyReason.isEmpty {
                Text(notReadyReason)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.fgMuted)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("module.tryOut.voice.hint".loc)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.fgMuted)
                    .fixedSize(horizontal: false, vertical: true)
                // Cost note — PER MODE. An unconditional "costs nothing" was true only on the
                // on-device model: in cloud modes the try-out sends the recording to the provider
                // and costs as much as a normal dictation. Exactly the person who installed Keyly to
                // save money would press it again and again while tuning the microphone.
                Text(costHint)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.fgMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // A tool must announce its OWN inapplicability. The try-out records and transcribes
            // in one go; it does not reproduce typing while speaking, and staying silent about it is
            // not acceptable — in this mode the user would test something other than what they use.
            if isLiveMode {
                Text("module.tryOut.voice.liveNote".loc)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.fgMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            resultBlock
        }
    }

    private var buttonTitle: String {
        switch preview.state {
        case .recording:    return "module.tryOut.voice.recording".loc
        case .transcribing: return "module.tryOut.voice.transcribing".loc
        default:            return "module.tryOut.voice.idle".loc
        }
    }

    @ViewBuilder
    private var resultBlock: some View {
        switch preview.state {
        case .done(let text):
            resultText(text, tint: Theme.Colors.fg)
        case .failed(let message):
            // A failure uses the same block as success: it is also an ANSWER of the try-out, and
            // hiding it in a toast would force the user to catch the message with their eyes.
            resultText(message, tint: Theme.Colors.warning)
        default:
            EmptyView()
        }
    }

    private func resultText(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(Theme.Typography.body)
            .foregroundStyle(tint)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .padding(Theme.Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                    .fill(Theme.Colors.surfaceHover)
            )
    }
}
