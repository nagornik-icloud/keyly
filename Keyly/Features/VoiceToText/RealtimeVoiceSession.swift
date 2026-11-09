import Combine
import Foundation

/// Coordinates the realtime session: microphone → websocket → accumulating completed segments
/// and the current partial. The UI subscribes to the @Published properties.
@MainActor
final class RealtimeVoiceSession: ObservableObject {
    enum State {
        case idle
        case connecting
        case recording
        case finalizing
        case finished
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var completedSegments: [String] = []
    @Published private(set) var partial: String = ""
    @Published private(set) var level: Float = 0.0

    /// Callback for an external observer when the session falls into .failed.
    var onFailed: ((String) -> Void)?

    /// Callback for every delta — for live typing straight into the input field.
    var onDeltaTyped: ((String) -> Void)?

    /// The final joined text, split into sentences: every `sentencesPerParagraph` sentences
    /// make one paragraph, separated by `\n\n`. Done locally and instantly — no LLM requests.
    var finalText: String {
        let joined = completedSegments.joined(separator: " ")
        return Self.splitIntoParagraphs(joined).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func splitIntoParagraphs(_ text: String, sentencesPerParagraph: Int = 3) -> String {
        guard !text.isEmpty else { return text }
        // Split at sentence-ending punctuation followed by a space.
        // A unique marker is used to keep the punctuation mark itself intact.
        let marker = "\u{0001}"
        var marked = text
        for ending in [". ", "! ", "? ", "… "] {
            marked = marked.replacingOccurrences(of: ending,
                                                 with: String(ending.first!) + marker)
        }
        let sentences = marked
            .components(separatedBy: marker)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard sentences.count > sentencesPerParagraph else { return text }

        var paragraphs: [[String]] = [[]]
        for sentence in sentences {
            if paragraphs[paragraphs.count - 1].count >= sentencesPerParagraph {
                paragraphs.append([sentence])
            } else {
                paragraphs[paragraphs.count - 1].append(sentence)
            }
        }
        return paragraphs
            .map { $0.joined(separator: " ") }
            .joined(separator: "\n\n")
    }

    /// What to show in the UI right now: completed + partial, separated by a space.
    var displayText: String {
        let body = completedSegments.joined(separator: " ")
        if partial.isEmpty { return body }
        return body.isEmpty ? partial : body + " " + partial
    }

    private let client = RealtimeTranscriptionClient()
    private let capture = RealtimeAudioCapture()
    private var continuation: CheckedContinuation<String, Never>?
    private var idleDeadline: Task<Void, Never>?
    private var maxDeadline: Task<Void, Never>?

    private let idleWaitNs: UInt64 = 1_500_000_000   // 1.5 s of server silence → finish
    private let maxWaitNs: UInt64  = 6_000_000_000   // hard ceiling of 6 s

    /// Seconds of audio captured so far — to decide whether a fallback makes sense.
    var capturedSeconds: Double { capture.capturedSeconds }

    /// Dumps the accumulated PCM as a WAV file (for falling back to /audio/transcriptions).
    @discardableResult
    func writeCapturedAudio(to url: URL) -> Bool {
        capture.writeWavFile(to: url)
    }

    init() {
        client.onConnected = { [weak self] in
            guard let self else { return }
            self.state = .recording
        }
        client.onPartial = { [weak self] delta in
            guard let self else { return }
            self.partial += delta
            // The server is still sending — extend the idle timer.
            if case .finalizing = self.state { self.rescheduleIdleDeadline() }
            // Hand the delta out — the manager types it into the field right away.
            self.onDeltaTyped?(delta)
        }
        client.onSegmentCompleted = { [weak self] text in
            guard let self else { return }
            self.partial = ""
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                self.completedSegments.append(trimmed)
            }
            // While finalizing, keep waiting for more chunks in case a long phrase
            // was cut into segments with processing pauses.
            if case .finalizing = self.state { self.rescheduleIdleDeadline() }
        }
        client.onError = { [weak self] error in
            guard let self else { return }
            let msg = (error as? RealtimeTranscriptionClient.ClientError)?.message ?? error.localizedDescription
            self.state = .failed(msg)
            self.onFailed?(msg)
            self.resolveFinalization()
        }
        client.onClosed = { [weak self] in
            guard let self else { return }
            self.capture.stop()
        }

        capture.onSamples = { [weak self] data in
            self?.client.sendAudio(data)
        }
        capture.onLevel = { [weak self] lvl in
            self?.level = lvl
        }
    }

    /// Start. Returns immediately — subscribers get the state via @Published.
    func start(apiKey: String, model: String, language: String = "ru") {
        guard case .idle = state else { return }
        state = .connecting
        completedSegments = []
        partial = ""
        level = 0
        client.connect(apiKey: apiKey, model: model, language: language)
        do {
            try capture.start()
        } catch {
            let msg = (error as? RealtimeAudioCapture.CaptureError)?.message ?? error.localizedDescription
            state = .failed(msg)
            onFailed?(msg)
            client.close()
        }
    }

    /// Stops recording, sends commit and waits for the final text.
    /// Returns the joined result. Waits for up to 1.5 s of server silence or 6 s at most.
    func finishAndCollect() async -> String {
        switch state {
        case .recording, .connecting:
            break
        case .failed:
            return finalText
        default:
            return finalText
        }

        state = .finalizing
        capture.stop()
        client.commit()

        let text: String = await withCheckedContinuation { cont in
            self.continuation = cont
            self.rescheduleIdleDeadline()
            self.maxDeadline = Task { [weak self] in
                try? await Task.sleep(nanoseconds: self?.maxWaitNs ?? 6_000_000_000)
                await MainActor.run { [weak self] in
                    self?.resolveFinalization()
                }
            }
        }
        client.close()
        state = .finished
        return text
    }

    private func rescheduleIdleDeadline() {
        idleDeadline?.cancel()
        idleDeadline = Task { [weak self] in
            try? await Task.sleep(nanoseconds: self?.idleWaitNs ?? 1_500_000_000)
            if Task.isCancelled { return }
            await MainActor.run { [weak self] in
                self?.resolveFinalization()
            }
        }
    }

    /// Full cancel — without keeping the text.
    func cancel() {
        capture.stop()
        client.close()
        resolveFinalization()
        state = .idle
        completedSegments = []
        partial = ""
        level = 0
    }

    private func resolveFinalization() {
        idleDeadline?.cancel()
        idleDeadline = nil
        maxDeadline?.cancel()
        maxDeadline = nil
        if let cont = continuation {
            continuation = nil
            cont.resume(returning: finalText)
        }
    }
}

#if DEBUG
extension RealtimeVoiceSession {
    /// Mock for SwiftUI previews: sets `level`/`state` without a network session.
    static func previewMock(level: Float, state: State) -> RealtimeVoiceSession {
        let session = RealtimeVoiceSession()
        session.level = level
        session.state = state
        return session
    }
}
#endif
