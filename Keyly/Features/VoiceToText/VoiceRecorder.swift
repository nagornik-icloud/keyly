import AVFoundation
import Foundation

@MainActor
final class VoiceRecorder {
    private var recorder: AVAudioRecorder?
    /// Listens for recorder FAILURES. There used to be no delegate at all: if recording failed by
    /// itself (encoding error, device disappeared), the product learned NOTHING about it — the timer
    /// ran, the badge stayed, but nothing was being written. There was nothing to diagnose with.
    private lazy var delegate = RecorderDelegate(owner: self)

    var isRecording: Bool { recorder != nil }

    /// Recording file name. A PARAMETER, not a constant: the try-out on the settings screen has its own
    /// recorder, and a shared path would mean its `deleteFile()` erases what the user already dictated.
    private let fileName: String

    init(fileName: String = "keyly-recording.m4a") {
        self.fileName = fileName
    }

    /// Recordings are deleted after use, but a crash leaves the user's speech on disk.
    /// Called at launch: removes any leftover recording files of Keyly from the temp folder
    /// (including the pre-rename name and the realtime fallback dumps).
    static func removeLeftoverRecordings() {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory
        let names = (try? fm.contentsOfDirectory(atPath: dir.path)) ?? []
        for name in names where (name.hasPrefix("keyly-") && name.hasSuffix("recording.m4a"))
            || name == "working-punto-recording.m4a" || name.hasPrefix("realtime-fallback-") {
            try? fm.removeItem(at: dir.appendingPathComponent(name))
        }
    }

    var tempAudioURL: URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(fileName)
    }

    /// Why recording didn't start. Cases are split by the user's ACTION, not by error code:
    /// "not asked yet" is fixed by the system dialog, "denied" by a toggle in Privacy
    /// settings, "device silent" not by settings at all.
    enum StartFailure: Error {
        /// The permission has never been requested. The NATIVE dialog is needed, not the Privacy pane:
        /// apps that have never asked for the microphone don't appear in that list yet.
        case permissionUnknown
        /// The user denied it (or it is blocked by MDM). Fixed only by a toggle in settings.
        case notPermitted
        /// Permission is there, but the device didn't deliver a stream. The cause is NOT known: used by
        /// another app, disabled, unplugged, no default input — `record()` doesn't distinguish them,
        /// so the user-facing text must not claim a specific cause either.
        case deviceUnavailable
    }

    func start() throws {
        // Check permission BEFORE creating the recorder: without it `record()` returns false, and
        // recording "starts" idle — timer running, badge showing, no sound.
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            break
        case .notDetermined:
            Log.warn(.voice, "VoiceRecorder: право на микрофон ещё не запрашивали")
            throw StartFailure.permissionUnknown
        default:
            Log.warn(.voice, "VoiceRecorder: доступ к микрофону запрещён — запись не начата")
            throw StartFailure.notPermitted
        }

        let url = tempAudioURL
        try? FileManager.default.removeItem(at: url)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        let rec = try AVAudioRecorder(url: url, settings: settings)
        // Level metering is needed by the input watchdog: an unplugged headset gives digital
        // zero, and without metering that is indistinguishable from a silent user.
        rec.isMeteringEnabled = true
        rec.delegate = delegate
        // `record()` returns Bool and gives false WITHOUT throwing when the device is busy/unavailable.
        // The result used to be discarded and `recorder` assigned anyway: `isRecording` became true,
        // the timer ran, the badge stayed — and on stop there was no file, and the module silently
        // exited. From outside it looked like "voice stopped working".
        guard rec.record() else {
            Log.error(.voice, "VoiceRecorder: устройство не начало запись (занято или недоступно)")
            throw StartFailure.deviceUnavailable
        }
        recorder = rec
        startSignalWatch()
        Log.info(.voice, "VoiceRecorder: запись начата → \(url.path)")
    }

    /// Called when the input is lost. Stopping the recording and transcribing what was recorded is
    /// the caller's job; this is only a signal: the recorder knows nothing about recognition
    /// or toasts.
    var onSignalLost: ((SignalWatchdog.Verdict) -> Void)?

    private var watchdog = SignalWatchdog()
    private var watchTimer: Timer?
    /// Watchdog tick counter — used to log the level once every 2 s rather than 4 times a second.
    private var levelLogTick = 0
    /// Level range over the recording — for the summary line in `stop()`.
    private var minDecibels: Float?
    private var maxDecibels: Float?

    private func startSignalWatch() {
        watchdog.reset()
        levelLogTick = 0
        minDecibels = nil
        maxDecibels = nil
        // 0.25 s step: more often means extra wakeups, less often means the watchdog learns about
        // a lost input with a delay comparable to the timeout itself.
        watchTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkSignal() }
        }
    }

    private func checkSignal() {
        guard let recorder, recorder.isRecording else { return }
        recorder.updateMeters()
        // AVAudioRecorder decibels (−160…0) are converted to 0…1 ONLY for the badge waveform.
        // The input-loss watchdog does NOT get them: it judges in decibels (see below) — a linear
        // scale can't tell "quiet" from "dead", and auto-stop already broke on exactly that.
        let decibels = recorder.averagePower(forChannel: 0)
        // There is NO MORE cutoff "below −60 dB → flat zero": it turned a quiet room into
        // digital zero, so the watchdog stopped recording on an ordinary pause in speech,
        // and the badge waveform fell into a dead line with quiet background music.
        // The linear level honestly continues down: −60 dB is 0.001, −80 dB is 0.0001.
        minDecibels = min(minDecibels ?? decibels, decibels)
        maxDecibels = max(maxDecibels ?? decibels, decibels)
        let level = powf(10, decibels / 20)
        // Log the level every 2 seconds. Without it a complaint like "the microphone cuts out after
        // ten seconds" is indistinguishable from "the watchdog was wrong", "the device dropped" and
        // "the recorder crashed": the product was equally silent about all three.
        levelLogTick += 1
        if levelLogTick % 8 == 0 {
            Log.info(.voice, "VoiceRecorder: вход \(String(format: "%.1f", decibels)) дБ "
                             + "(порог мёртвого входа \(SignalWatchdog.deadInputDecibels))")
        }
        // The same level feeds the recording badge: the waveform must be alive in batch mode too,
        // otherwise it shows sound only during live typing and lies the rest of the time.
        InputLevelMeter.shared.report(level: level)
        // The watchdog judges by DECIBELS: only they tell "quiet" apart from "input dropped".
        let verdict = watchdog.feed(decibels: decibels, now: Date().timeIntervalSince1970)
        guard verdict != .ok else { return }
        Log.warn(.voice, verdict == .neverStarted
                 ? "VoiceRecorder: звука не было НИ РАЗУ за \(SignalWatchdog.timeout) с — "
                   + "система не пустила к устройству (право есть, потока нет)"
                 : "VoiceRecorder: вход пропал посреди записи (был сигнал, стало тихо)")
        stopSignalWatch()
        onSignalLost?(verdict)
    }

    private func stopSignalWatch() {
        watchTimer?.invalidate()
        watchTimer = nil
        watchdog.reset()
    }

    func stop() {
        // Summary in ONE line: how long it lasted, file size, what the input was like. It shows at
        // once what happened: an empty file with a live input — the recorder crashed; a dead input —
        // the device dropped; a short duration with a live input — someone stopped recording early.
        // This used to say just "recording stopped", and a complaint like "the microphone cuts out
        // after ten seconds" had no evidence at all.
        let seconds = recorder?.currentTime ?? 0
        stopSignalWatch()
        recorder?.stop()
        recorder = nil
        let bytes = (try? FileManager.default
            .attributesOfItem(atPath: tempAudioURL.path)[.size] as? Int64) ?? nil
        Log.info(.voice, String(
            format: "VoiceRecorder: запись остановлена — %.1f с, %@, вход %@",
            seconds,
            bytes.map { "\($0 / 1024) КБ" } ?? "файла нет",
            // The level range is assembled HERE, not in a separate property: an extracted helper
            // with Russian text is read by the localization gate as a user-facing string — it judges
            // by the line of code, not by where the value ends up.
            minDecibels.flatMap { low in maxDecibels.map { high in
                String(format: "%.1f…%.1f дБ", low, high) } } ?? "не мерился"))
    }

    func deleteFile() {
        try? FileManager.default.removeItem(at: tempAudioURL)
    }
}

/// `AVAudioRecorder` delegate: the only way to learn that recording stopped BY ITSELF.
///
/// `AVAudioRecorder` doesn't throw after starting — it just stops writing, and `isRecording`
/// becomes `false`. The input watchdog can't catch this by construction: it bails out on
/// `guard recorder.isRecording`, so it stays silent for a stopped recorder. Without the delegate
/// both outcomes — "input dropped" and "recorder crashed" — looked the same to the product: silence.
private final class RecorderDelegate: NSObject, AVAudioRecorderDelegate {
    private weak var owner: VoiceRecorder?

    init(owner: VoiceRecorder) {
        self.owner = owner
    }

    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        guard !flag else { return }
        Log.error(.voice, "VoiceRecorder: запись завершилась НЕУДАЧНО (система оборвала поток)")
    }

    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        Log.error(.voice, "VoiceRecorder: ошибка кодирования — \(error?.localizedDescription ?? "без описания")")
    }
}
