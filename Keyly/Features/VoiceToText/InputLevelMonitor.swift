import AVFoundation
import Combine
import Foundation

/// Live input level while the Microphone section is open.
///
/// Why separate from recording. The level bar moved ONLY during real dictation and sat at zero
/// otherwise — so exactly when the user came to check "does my Mac hear me", it stayed still and
/// read as "the microphone doesn't work". There was no other way to check: the only test on the
/// screen goes to the cloud and costs money — absurd for someone who chose the local model to
/// work offline.
///
/// Here the audio goes NOWHERE: not to a file, not to the network. Only loudness is measured.
///
/// The note in `InputLevelMeter` ("doesn't open its own capture: two open captures fail") still
/// holds — so the monitor stays silent while recording and tears itself down when the section
/// is closed.
@MainActor
final class InputLevelMonitor: ObservableObject {
    static let shared = InputLevelMonitor()

    /// RAW input level, without scale stretching. The "hearing you" label judges by it, not by the
    /// normalized value from `InputLevelMeter`: that one stretches the scale to the observed peak,
    /// and room noise after stretching gave 0.3–0.5 — a green "hearing you" in silence. The label
    /// promises "the Mac hears ME", so it must measure speech, not "anything at all at the input".
    @Published private(set) var rawLevel: Float = 0

    /// Speech threshold. Normal speech a meter from the built-in mic gives 0.02–0.08 raw; room
    /// noise and fans give a few thousandths.
    static let speechLevel: Float = 0.012

    private var engine: AVAudioEngine?
    /// Written by the audio thread, read by the main one — as in `VoiceRecorder`.
    private let levelBox = LevelBox()

    private final class LevelBox: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: Float = 0
        var value: Float {
            get { lock.lock(); defer { lock.unlock() }; return storage }
            set { lock.lock(); storage = newValue; lock.unlock() }
        }
    }

    /// How many screens currently want the live level. A counter, not a flag: the section may be
    /// open in two windows, and closing one must not turn off the meter in the other.
    private var subscribers = 0

    private init() {}

    /// Suspended during dictation. Separate from `subscribers`: the section is still open, the
    /// subscriber hasn't gone anywhere — the microphone is just busy with something more important.
    private var suspended = false

    func start() {
        subscribers += 1
        guard engine == nil, !suspended else { return }
        startEngine()
    }

    private func startEngine() {
        // The microphone is busy with real dictation — stay out: a second capture would cause a
        // device failure or a silent track in one of them.
        guard !VoiceToTextManager.shared.isDictating else { return }
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else { return }

        let newEngine = AVAudioEngine()
        let input = newEngine.inputNode
        AudioInputDevices.applySelected(to: input)
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else { return }

        // Throttle: not every buffer goes to the main actor, only about every fifth (~10 times a
        // second). A task per EVERY buffer flooded the main thread.
        let box = levelBox
        var tick = 0
        input.installTap(onBus: 0, bufferSize: 2048, format: format) { buffer, _ in
            let level = Self.linearLevel(of: buffer)
            box.value = level
            tick += 1
            guard tick % 5 == 0 else { return }
            Task { @MainActor in
                InputLevelMeter.shared.report(level: box.value)
                InputLevelMonitor.shared.rawLevel = box.value
            }
        }
        newEngine.prepare()
        do {
            try newEngine.start()
            engine = newEngine
            Log.info(.voice, "Монитор входа: слушаем уровень для экрана настроек")
        } catch {
            Log.warn(.voice, "Монитор входа: не запустился — \(LogSanitizer.sanitize(error.localizedDescription))")
        }
    }

    func stop() {
        subscribers = max(0, subscribers - 1)
        guard subscribers == 0 else { return }
        tearDown(reason: "остановлен")
    }

    /// Yields the microphone to dictation. Called from `VoiceToTextManager` AT THE START of recording.
    ///
    /// Checking "is the mic busy" when the section opens is NOT ENOUGH: the user opens settings,
    /// watches the bar and, without closing the window, presses the hotkey — two captures of one
    /// device fail or give a silent track, so the fixed indicator would break the main feature.
    func suspendForDictation() {
        suspended = true
        guard engine != nil else { return }
        tearDown(reason: "уступил микрофон диктовке")
    }

    /// Dictation ended — bring the meter back if the section is still open.
    func resumeAfterDictation() {
        suspended = false
        guard subscribers > 0, engine == nil else { return }
        startEngine()
    }

    private func tearDown(reason: String) {
        guard let engine else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        self.engine = nil
        rawLevel = 0
        InputLevelMeter.shared.reset()
        Log.info(.voice, "Монитор входа: \(reason)")
    }

    /// Linear level 0…1 — the same scale the recorder reports, so the bar behaves the same at rest
    /// and during dictation.
    private nonisolated static func linearLevel(of buffer: AVAudioPCMBuffer) -> Float {
        guard let channel = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<Int(buffer.frameLength) {
            sum += channel[i] * channel[i]
        }
        return sqrt(sum / Float(buffer.frameLength))
    }
}
