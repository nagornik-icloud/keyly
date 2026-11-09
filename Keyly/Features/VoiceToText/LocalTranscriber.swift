import Combine
import FluidAudio
import Foundation

/// Local speech recognition with Parakeet TDT v3 — a prototype for MEASUREMENT.
///
/// What matters here is the process, not the code: "Parakeet v3 prototype → measure Russian → decide".
/// The model officially supports Russian (25 European languages), with a stated WER of 5.51 % on
/// Fleurs and 3.00 % on CoVoST. Whether it is usable IN PRACTICE is decided by comparing its output
/// with the cloud on real speech: the model card numbers were not measured on this microphone or diction.
///
/// State is exposed (`state`) because the model weighs hundreds of megabytes and is downloaded over
/// the network: a silent wait the first time looks like a hung feature.
@MainActor
final class LocalTranscriber: ObservableObject {

    static let shared = LocalTranscriber()

    enum State: Equatable {
        case notLoaded
        case downloading(progress: Double)
        case ready
        case failed(String)

        var isReady: Bool { if case .ready = self { return true }; return false }
        var isBusy: Bool { if case .downloading = self { return true }; return false }
    }

    @Published private(set) var state: State = .notLoaded

    /// Where the package keeps model files. One home for the path — it is needed by the
    /// "Show in Finder" button, the free-space check, and the "is it downloaded" check.
    static var modelDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FluidAudio", isDirectory: true)
    }

    /// The folder of EXACTLY the model the current package version loads.
    ///
    /// The name is hardcoded in `FluidAudio` (`Repo.parakeet` → `parakeet-tdt-0.6b-v3-coreml`) and has
    /// changed across package updates: a machine may still have `parakeet-tdt-0.6b-v3` from the
    /// previous version next to it — "two 450 MB models", of which only one works.
    private static var currentModelDirectory: URL {
        modelDirectory
            .appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent(LocalModelFiles.currentFolder, isDirectory: true)
    }

    /// Where "Show in Finder" leads — to the model's OWN folder, not the `FluidAudio` root.
    /// Opening the root showed two folders instead of one: the product showed something other
    /// than what the line next to the button was talking about.
    static var modelFolderForFinder: URL { currentModelDirectory }

    /// The model is DOWNLOADED: a complete set of files of the right version is on disk. This is NOT
    /// the same as `state.isReady`, which means "loaded into RAM and ready to accept audio".
    ///
    /// The SET is checked, not "the folder is not empty": based on a non-empty folder the product once
    /// declared the model ready, showed "Model ready" and "Show in Finder", and then refused to record.
    /// The folder held two folders of different versions, and "something is there, so it works"
    /// was an assumption, not a check.
    static var isDownloadedOnDisk: Bool {
        let present = (try? FileManager.default.contentsOfDirectory(
            atPath: currentModelDirectory.path)) ?? []
        return LocalModelFiles.isComplete(present: Set(present))
    }

    /// Loads an already downloaded model into memory. DOWNLOADS NOTHING: if the set is not on disk,
    /// it returns immediately.
    ///
    /// Called at startup and when local mode is selected. Without it the model was loaded only by
    /// the "Download" button, so after EVERY app restart the product considered it missing — and
    /// told the user so only AFTER they had spoken a long phrase.
    func warmUpIfDownloaded() async {
        // Only for someone who ACTUALLY uses local mode. Otherwise a person who once
        // downloaded the model to compare and went back to the cloud would pay almost a gigabyte
        // of memory and a second of startup on every launch — forever.
        let mode = VoiceRecognitionMode(
            rawValue: UserDefaults.standard.string(forKey: SettingsKeys.voiceRecognitionMode) ?? "")
        guard mode == .onDevice else { return }
        guard Self.isDownloadedOnDisk, !state.isReady, !state.isBusy else { return }
        Log.info(.voice, "Локальная модель: файлы на диске есть — поднимаем в память без скачивания")
        // Cache-only load. `prepare()` calls `downloadAndLoad`, and with a corrupted file
        // INSIDE `.mlmodelc` that wipes the folder and downloads almost half a gigabyte — at startup,
        // silently, although downloading must happen only via the button (reproduced: removing
        // one `coremldata.bin` triggered a 450 MB download without asking).
        do {
            let models = try await AsrModels.loadFromCache(version: .v3)
            let manager = AsrManager(config: .default)
            try await manager.initialize(models: models)
            self.manager = manager
            state = .ready
            Log.info(.voice, "Локальная модель готова")
        } catch {
            // Stay silent in the UI: this is background warm-up, not a user action. The user will
            // learn the reason when pressing the hotkey — there the refusal comes BEFORE recording.
            Log.warn(.voice, "Локальная модель: прогрев не удался (\(LogSanitizer.sanitize(String(describing: error)))) — комплект на диске неполон или повреждён")
            state = .failed("")
        }
    }

    /// Whether local mode can be used. Files are in place — then yes: loading into memory
    /// happens on its own at the first dictation (`transcribe` calls `prepare`).
    /// Loading the model into memory at startup just to show the right state is not allowed —
    /// that is hundreds of megabytes for everyone who merely opened settings.
    var isUsable: Bool { state.isReady || Self.isDownloadedOnDisk }

    /// How much the model TAKES on disk right now — measured, not a constant from text.
    ///
    /// The constant was wrong twice in a row: "~480 MB" was left over from an old model version, and
    /// "~900 MB" came from measuring a folder that also held a copy from a previous package release.
    /// The user opens Finder and sees a different number — after the second time they stop
    /// trusting the other labels too. We measure what is there.
    static func downloadedBytes() -> Int64? {
        let dir = currentModelDirectory
        guard let walker = FileManager.default.enumerator(
            at: dir, includingPropertiesForKeys: [.totalFileAllocatedSizeKey],
            options: [.skipsHiddenFiles]) else { return nil }
        var total: Int64 = 0
        for case let url as URL in walker {
            let size = (try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey]))?
                .totalFileAllocatedSize ?? 0
            total += Int64(size)
        }
        return total > 0 ? total : nil
    }

    /// `AsrManager` is the package's actor; we keep a reference so the model isn't loaded per request
    /// (loading takes seconds and hundreds of megabytes of memory).
    private var manager: AsrManager?
    /// The current load. A second call WAITS for it instead of bailing out: the model downloads for
    /// minutes, and dictations made in that window would otherwise silently lose their result — even
    /// though the model would be ready seconds later.
    private var loadTask: Task<Void, Never>?
    /// When it is OK to retry after a failure. Without a pause every next dictation would restart a
    /// multi-hundred-megabyte load from scratch — a retry storm that would make the measurement itself
    /// look like "the model always fails and is slow".
    private var retryNotBefore: Date?
    private static let retryCooldown: TimeInterval = 60

    private init() {}

    /// Forget the downloaded model: the files have already been deleted externally, and state must reflect that.
    ///
    /// Without a reset the product would keep considering the model ready and route to local
    /// recognition that no longer exists — the failure would come only after the spoken phrase.
    func forgetDownloadedModel() {
        loadTask?.cancel()
        loadTask = nil
        // Release the model itself too: otherwise almost a gigabyte stayed in memory until the next
        // successful load, even though the user had already deleted the files.
        manager = nil
        state = .notLoaded
    }

    /// Downloads the model on first run and loads it.
    /// A repeated call during loading WAITS for the same task instead of starting a second one.
    func prepare() async {
        if let loadTask { await loadTask.value; return }
        guard !state.isReady else { return }
        if case .failed = state, let retryNotBefore, Date() < retryNotBefore {
            return   // cooling down after a failure
        }
        // Check free space BEFORE starting: otherwise a download on a full disk fails at the
        // very end — the user waits minutes, sees progress to the end, and gets a write error.
        let support = FileManager.default.urls(for: .applicationSupportDirectory,
                                               in: .userDomainMask)[0]
        switch DiskSpace.check(availableBytes: DiskSpace.availableBytes(at: support)) {
        case .notEnough(let required, let available):
            let message = "voice.model.noSpace".loc(DiskSpace.format(required),
                                                    DiskSpace.format(available))
            Log.warn(.voice, "Локальная модель: не хватает места, нужно \(required), есть \(available)")
            state = .failed(message)
            return
        case .enough, .unknown:
            break   // couldn't measure — try anyway; refusing because of our own blindness is worse
        }
        let task = Task { @MainActor in await self.load() }
        loadTask = task
        await task.value
        loadTask = nil
    }

    /// Number of load steps: the package downloads four model files one by one, then compiles.
    /// The number is hardcoded in the package (`AsrModels.download` iterates preprocessor/encoder/decoder/
    /// joint), and there is no external way to get it — if the version changes the bar will drift in
    /// pace but not break: the end is still forced to 100 % once loading actually finishes.
    private static let downloadStages = 5

    private func load() async {
        state = .downloading(progress: 0)
        Log.info(.voice, "Локальная модель: загрузка Parakeet v3")
        do {
            // The package reports the fraction SEPARATELY FOR EACH file and resets it to zero on the next.
            // Showing that as is would run the bar from 0 to 100 four times — it reads as a loop.
            // We compute an overall fraction, detecting the transition by the value dropping.
            let tracker = ProgressTracker()
            let models = try await AsrModels.downloadAndLoad(version: .v3) { [weak self] p in
                let overall = tracker.advance(to: p.fractionCompleted, stages: Self.downloadStages)
                Task { @MainActor in
                    guard let self, case .downloading = self.state else { return }
                    self.state = .downloading(progress: overall)
                }
            }
            let manager = AsrManager(config: .default)
            try await manager.initialize(models: models)
            self.manager = manager
            retryNotBefore = nil
            state = .ready
            Log.info(.voice, "Локальная модель готова")
        } catch {
            let message = LogSanitizer.sanitize(String(describing: error))
            state = .failed(message)
            retryNotBefore = Date().addingTimeInterval(Self.retryCooldown)
            Log.error(.voice, "Локальная модель: загрузка не удалась: \(message). Повтор не раньше чем через \(Int(Self.retryCooldown)) с")
        }
    }

    /// Transcribes a file. `nil` means the model isn't ready or recognition failed; the caller then
    /// goes to the cloud instead of showing the user nothing.
    ///
    /// We do NOT convert audio: the package accepts a URL and converts the format itself. Our own
    /// conversion would be one more place to silently damage the signal and get garbage text instead
    /// of an error — indistinguishable from poor model quality, which is exactly what we are measuring.
    func transcribe(url: URL) async -> Transcript? {
        if !state.isReady { await prepare() }
        guard state.isReady, let manager else { return nil }
        do {
            let started = Date()
            let result = try await manager.transcribe(url)
            let elapsed = Date().timeIntervalSince(started)
            Log.info(.voice, "Локальное распознавание: \(result.text.count) симв. за \(String(format: "%.1f", elapsed)) с")
            return Transcript(text: result.text,
                              confidence: result.confidence,
                              audioDuration: result.duration,
                              processingTime: elapsed)
        } catch {
            Log.error(.voice, "Локальное распознавание не удалось: \(LogSanitizer.sanitize(String(describing: error)))")
            return nil
        }
    }

    /// Merges the package's per-stage fractions into one overall fraction that only grows.
    ///
    /// A bar that jumps backwards is worse than no bar: it reads as "it broke and started over".
    /// So the value here is monotonic, and only actual readiness reaches 100 % — if there turn out
    /// to be more stages than expected, the bar stops at 99 % and waits.
    ///
    /// The class is thread-safe: the package callback arrives on an arbitrary queue.
    private final class ProgressTracker: @unchecked Sendable {
        private let lock = NSLock()
        private var stage = 0
        private var lastFraction = 0.0
        private var lastOverall = 0.0

        func advance(to fraction: Double, stages: Int) -> Double {
            lock.lock(); defer { lock.unlock() }
            // A drop in the fraction means the package moved on to the next file. The 0.05 threshold filters jitter.
            if fraction < lastFraction - 0.05 { stage += 1 }
            lastFraction = fraction
            let raw = (Double(stage) + fraction) / Double(stages)
            lastOverall = max(lastOverall, min(raw, 0.99))
            return lastOverall
        }
    }

    /// Result with metrics — they are the point of the measurement: we need to compare not only
    /// the text but also the speed relative to the cloud.
    struct Transcript: Equatable {
        let text: String
        let confidence: Float
        let audioDuration: TimeInterval
        let processingTime: TimeInterval

        /// How many times faster than real time. <1 means "slower than speech" —
        /// for dictation that is a verdict regardless of text quality.
        var realtimeFactor: Double {
            guard processingTime > 0 else { return 0 }
            return audioDuration / processingTime
        }
    }
}
