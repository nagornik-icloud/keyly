import SwiftUI

/// Microphone selection and level indicator.
///
/// Input SELECTION is active only in "while speaking" mode: there recording goes through
/// `AVAudioEngine`, which can be assigned an input. Batch modes record with `AVAudioRecorder`,
/// which has no input selection, so a working-looking picker there would be a phantom.
///
/// An attempt to move batch recording to the engine (so selection works everywhere) was
/// rolled back: the rewritten recording hung on stop, and that is the core of the app. The
/// level INDICATOR stays live in all modes — it records nothing and does not depend on the
/// recording method.
struct VoiceInputDeviceSection: View {
    /// Whether device SELECTION is available in the current mode. The level indicator always works.
    let isSelectable: Bool

    @AppStorage(SettingsKeys.voiceInputDeviceUID) private var selectedUID: String = ""
    @State private var devices: [AudioInputDevices.Device] = []
    /// Name of the device that "System input" resolves to right now.
    @State private var systemName: String?
    @StateObject private var meter = InputLevelMeter.shared
    @StateObject private var monitor = InputLevelMonitor.shared

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            SectionLabel(text: "voice.input.title".loc)

            HStack(spacing: Theme.Space.m) {
                Menu {
                    Button {
                        selectedUID = ""
                    } label: {
                        Label("voice.input.system".loc,
                              systemImage: selectedUID.isEmpty ? "checkmark" : "waveform")
                    }
                    if !devices.isEmpty {
                        Divider()
                        ForEach(devices) { device in
                            Button {
                                selectedUID = device.uid
                            } label: {
                                Label(device.name,
                                      systemImage: selectedUID == device.uid ? "checkmark" : "mic")
                            }
                        }
                    }
                } label: {
                    pickerLabel
                }
                .buttonStyle(.plain)
                .frame(maxWidth: 260)
                .keylyInapplicable(when: !isSelectable, reason: "voice.input.systemOnly".loc)

                VStack(alignment: .leading, spacing: 4) {
                    LevelBar(level: meter.level)
                        .frame(width: 120, height: 6)
                    // A strip WITHOUT a caption at rest is indistinguishable from a decorative line and
                    // from "the microphone doesn't work": the user speaks, looks at it and concludes
                    // they are not heard. Now it is live — while the section is open the level is
                    // measured locally, with no network and no recording — and labeled in
                    // words.
                    Text(hearing ? "voice.input.hearing".loc : "voice.input.silence".loc)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(hearing ? Theme.Colors.success : Theme.Colors.fgDim)
                }
                Spacer(minLength: 0)
            }
            // What "System input" resolves to RIGHT NOW. Without this the only control on
            // the topic did not answer the question it is opened for: what is recording the
            // sound now — the built-in microphone or a headset.
            if selectedUID.isEmpty, let system = systemName {
                Text("voice.input.systemNow".loc(system))
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.fgMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear {
            devices = AudioInputDevices.available()
            systemName = AudioInputDevices.systemDefaultName()
            InputLevelMonitor.shared.start()
        }
        .onDisappear { InputLevelMonitor.shared.stop() }
        // A change of the selected input is a reason to restart the monitor: it holds the device
        // that was selected when it started.
        .onChange(of: selectedUID) {
            systemName = AudioInputDevices.systemDefaultName()
            InputLevelMonitor.shared.stop()
            InputLevelMonitor.shared.start()
        }
        // The device list is rebuilt every time the screen appears: headsets are plugged
        // and unplugged while the app is running, and a frozen list would show an input
        // that is gone — or hide one just connected.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            devices = AudioInputDevices.available()
            systemName = AudioInputDevices.systemDefaultName()
        }
    }

    /// "Hearing" is based on the RAW level: the normalized one is stretched to the observed peak,
    /// and after stretching room noise gave a green confirmation on silence.
    private var hearing: Bool { monitor.rawLevel > InputLevelMonitor.speechLevel }

    private var pickerLabel: some View {
        HStack(spacing: 6) {
            Image(systemName: "mic")
                .font(.system(size: 11))
                .foregroundStyle(Theme.Colors.fgDim)
            Text(currentName)
                .font(Theme.Typography.bodyEmphasis)
                .foregroundStyle(Theme.Colors.fg)
                .lineLimit(1)
            Spacer(minLength: 6)
            Image(systemName: "chevron.down")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.Colors.fgDim)
        }
        .padding(.horizontal, Theme.Space.m)
        .frame(height: Theme.Size.control)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                .fill(Theme.Colors.surfaceHover)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                        .stroke(Theme.Colors.border, lineWidth: 1)
                )
        )
    }

    /// Name of the selected input. If the device disappeared (unplugged), say so directly:
    /// a silent fallback to the system input would only be noticed by the wrong sound in the recording.
    private var currentName: String {
        guard !selectedUID.isEmpty else { return "voice.input.system".loc }
        if let device = devices.first(where: { $0.uid == selectedUID }) { return device.name }
        return "voice.input.missing".loc
    }
}

/// Input level strip. Separate from the picker: it has its own refresh rate, and there is
/// no reason to redraw the device menu along with it.
private struct LevelBar: View {
    let level: Float

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.Colors.surfaceHover)
                Capsule()
                    .fill(Theme.Colors.accent)
                    .frame(width: geo.size.width * CGFloat(min(max(level, 0), 1)))
            }
        }
        .animation(.linear(duration: 0.08), value: level)
    }
}
