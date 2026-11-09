import Foundation

/// WebSocket client for the OpenAI Realtime Transcription API.
/// Flow: connect → wait for transcription_session.created → send .update with the model
/// and turn_detection=null (we drive start/stop manually) → send audio chunks →
/// on commit receive completed events with the final text.
final class RealtimeTranscriptionClient: NSObject {
    enum ClientError: Error, LocalizedError {
        case notConnected
        case server(String)
        case decode
        case http(Int, String)
        case connectTimeout

        /// For logs; the user sees `message` (localized, main actor).
        var errorDescription: String? {
            switch self {
            case .notConnected: return "No connection to the Realtime API"
            case .server(let m): return m
            case .decode: return "Undecodable Realtime event"
            case .http(let code, let body): return "Realtime API returned HTTP \(code). \(body.prefix(200))"
            case .connectTimeout: return "Realtime API did not answer in 5 seconds"
            }
        }

        @MainActor var message: String {
            switch self {
            case .notConnected: return "voice.rt.notConnected".loc
            case .server(let m): return m
            case .decode: return "voice.rt.decode".loc
            case .http(let code, _): return "voice.rt.http".loc(code)
            case .connectTimeout: return "voice.rt.timeout".loc
            }
        }
    }

    // Callbacks run on the main actor.
    @MainActor var onConnected: (() -> Void)?
    @MainActor var onPartial: ((String) -> Void)?
    @MainActor var onSegmentCompleted: ((String) -> Void)?
    @MainActor var onError: ((Error) -> Void)?
    @MainActor var onClosed: (() -> Void)?

    private var task: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var isOpen = false
    private var didReceiveSessionCreated = false
    private var pendingModel: String = "gpt-4o-mini-transcribe"
    private var pendingLanguage: String = "ru"
    private var connectTimeoutTask: Task<Void, Never>?
    /// Item IDs for which we have already emitted a completed transcript — so that
    /// .completed and .done don't produce duplicates.
    private var completedItemIds: Set<String> = []
    private var didLogFirstDelta = false

    /// The Realtime session model is the chat wrapper of the WS session (GA: `gpt-realtime-2`).
    /// The underlying transcription model (`gpt-realtime-whisper` / `gpt-4o-mini-transcribe`
    /// etc.) goes separately in audio.input.transcription.model.
    private static let realtimeSessionModel = "gpt-realtime-2"

    /// The stream's transcription model. Kept as a constant because the prompt DEPENDS on its name
    /// (`TranscriptionPrompt.text(forModel:)` doesn't send instructions to a whisper model),
    /// and a literal in two places would drift from that decision on the first model change.
    private static let transcriptionModel = "gpt-realtime-whisper"

    @MainActor
    func connect(apiKey: String, model: String, language: String = "ru") {
        guard task == nil else { return }
        pendingModel = model
        pendingLanguage = language
        didReceiveSessionCreated = false

        // GA endpoint — model is REQUIRED in the URL, and it must be the realtime model,
        // not the transcription one. The transcription model goes in session.update.
        var components = URLComponents(string: "wss://api.openai.com/v1/realtime")!
        components.queryItems = [URLQueryItem(name: "model", value: Self.realtimeSessionModel)]
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        urlSession = session

        let ws = session.webSocketTask(with: request)
        task = ws
        ws.resume()
        isOpen = true
        listen()

        // 5-second timeout — if the server doesn't send session.created by then, fail
        // explicitly. The WS can hang silently if the key has no Realtime access.
        connectTimeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            await MainActor.run { [weak self] in
                guard let self else { return }
                if !self.didReceiveSessionCreated, self.isOpen {
                    Log.info(.voice, "Realtime: connect timeout — нет session.created за 5с")
                    self.onError?(ClientError.connectTimeout)
                    self.close()
                }
            }
        }
    }

    func sendAudio(_ pcm: Data) {
        guard let task, isOpen else { return }
        let base64 = pcm.base64EncodedString()
        let payload: [String: Any] = [
            "type": "input_audio_buffer.append",
            "audio": base64
        ]
        send(payload)
        _ = task
    }

    func commit() {
        send(["type": "input_audio_buffer.commit"])
    }

    @MainActor
    func close() {
        guard isOpen else { return }
        isOpen = false
        connectTimeoutTask?.cancel()
        connectTimeoutTask = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        urlSession?.finishTasksAndInvalidate()
        urlSession = nil
        completedItemIds.removeAll()
        didLogFirstDelta = false
        onClosed?()
    }

    // MARK: - Private

    private func send(_ payload: [String: Any]) {
        guard let task else { return }
        do {
            let data = try JSONSerialization.data(withJSONObject: payload, options: [])
            guard let str = String(data: data, encoding: .utf8) else { return }
            task.send(.string(str)) { [weak self] error in
                if let error {
                    Task { @MainActor [weak self] in
                        self?.onError?(error)
                    }
                }
            }
        } catch {
            Task { @MainActor [weak self] in
                self?.onError?(error)
            }
        }
    }

    private func sendSessionUpdate() {
        // The URL with gpt-realtime-2 created a realtime session. session.update must
        // confirm the same type ("realtime"). We don't send response.create — the model
        // generates nothing in reply, it only gives us input_audio_transcription.
        //
        // To stream delta events we force gpt-realtime-whisper — other models
        // (gpt-4o-mini-transcribe, gpt-4o-transcribe) inside a realtime session don't
        // stream deltas, only the final segment. Plus delay="low" — the minimal server
        // buffer before sending us a chunk.
        let payload: [String: Any] = [
            "type": "session.update",
            "session": [
                "type": "realtime",
                "audio": [
                    "input": [
                        "format": [
                            "type": "audio/pcm",
                            "rate": 24000
                        ],
                        "transcription": [
                            "model": Self.transcriptionModel,
                            "language": pendingLanguage,
                            "delay": "xhigh",
                            // The prompt is COMPUTED FROM THE MODEL, not set as text.
                            //
                            // It is tempting to put a "don't answer the speech" ban here — that is
                            // exactly the problem being solved. Not allowed: the transcription model
                            // here is from the whisper family, and whisper doesn't follow instructions,
                            // but their TEXT can leak into the output (see TranscriptionPrompt) — so
                            // the user would get a piece of our ban in the field under the cursor
                            // instead of their speech. The cure would be worse than the disease.
                            //
                            // So `text(forModel:)` decides: whisper gets only biasing (language,
                            // terms), an instruction-following model also gets the ban. What protects
                            // against "answering the speech" on this path is two STRUCTURAL
                            // mechanisms, not text: `turn_detection: NSNull()` below and the item
                            // role filter in `isHumanSpeech` — assistant text physically cannot
                            // reach the field, whatever the model generates.
                            "prompt": TranscriptionPrompt.text(forModel: Self.transcriptionModel)
                        ],
                        "turn_detection": NSNull()
                    ]
                ]
            ]
        ]
        send(payload)
    }

    private func listen() {
        guard let task else { return }
        task.receive { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch result {
                case .failure(let err):
                    if self.isOpen {
                        // If the server managed to send an HTTP response before the upgrade failed,
                        // pull the status code from it — it often helps diagnose (401, 403, 429).
                        if let resp = self.task?.response as? HTTPURLResponse {
                            let body = "HTTP \(resp.statusCode)"
                            Log.error(.voice, "Realtime: receive failed. \(LogSanitizer.sanitize(body)). Error: \(LogSanitizer.sanitize(err.localizedDescription))")
                            self.onError?(ClientError.http(resp.statusCode, err.localizedDescription))
                        } else {
                            Log.error(.voice, "Realtime: receive failed: \(err.localizedDescription)")
                            self.onError?(err)
                        }
                        self.close()
                    }
                case .success(let message):
                    self.handle(message: message)
                    if self.isOpen { self.listen() }
                }
            }
        }
    }

    private func handle(message: URLSessionWebSocketTask.Message) {
        let raw: String
        switch message {
        case .string(let s): raw = s
        case .data(let d): raw = String(data: d, encoding: .utf8) ?? ""
        @unknown default: return
        }
        guard let data = raw.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            Log.info(.voice, "Realtime: undecodable event, \(raw.count) chars")  // may contain dictated text
            return
        }

        switch type {
        case "session.created":
            Log.info(.voice, "Realtime: session.created")
            didReceiveSessionCreated = true
            connectTimeoutTask?.cancel()
            sendSessionUpdate()
        case "session.updated":
            Log.info(.voice, "Realtime: session.updated")
            onConnected?()
        case "conversation.item.input_audio_transcription.delta":
            if !didLogFirstDelta {
                didLogFirstDelta = true
                Log.info(.voice, "Realtime: первая delta получена — стриминг работает")
            }
            if let delta = json["delta"] as? String {
                onPartial?(delta)
            }
        case "conversation.item.input_audio_transcription.completed":
            let itemId = json["item_id"] as? String
            if let transcript = json["transcript"] as? String {
                // The event name itself says this is an INPUT audio transcript; it usually has
                // no role — so the content type is known in advance. We still run the check:
                // if the server ever sends a role here, the role must decide.
                guard isHumanSpeech(role: json["role"] as? String,
                                    contentType: "input_audio",
                                    event: type) else { break }
                emitCompletedTranscript(itemId: itemId, transcript: transcript)
            }
        case "conversation.item.added":
            extractTranscript(from: json)
        case "conversation.item.done":
            // The final chord: the item is "closed" and holds the full transcript.
            // A safety net in case the .completed events didn't arrive.
            extractTranscript(from: json)
        case "input_audio_buffer.committed":
            break
        case "error":
            let msg = (json["error"] as? [String: Any])?["message"] as? String
                ?? "Realtime API error"
            Log.info(.voice, "Realtime: server error event: \(LogSanitizer.sanitize(msg))")
            onError?(ClientError.server(msg))
        default:
            Log.info(.voice, "Realtime: unhandled event type: \(type)")
        }
    }

    /// Extracts the transcript from the item structure (conversation.item.added / .done)
    /// and emits it through the item_id deduplicator.
    ///
    /// The role filter here is the ONLY structural guard on this path, so it is not "just in case".
    /// The session is opened on the chat model gpt-realtime-2: its own (assistant) items arrive in
    /// THE SAME event with the same content[].transcript field — only that is a transcript of the
    /// MODEL's speech, not the user's. The text then goes straight into the field under the cursor
    /// (VoiceToTextManager, live delta typing), and there is no post-processing at the "verbatim"
    /// level that could notice anything. So without this check the model's reply reaches the user
    /// as their own speech — the reported symptom: "I want to dictate something, and instead the
    /// app immediately answers my question. I don't need that."
    private func extractTranscript(from json: [String: Any]) {
        guard let item = json["item"] as? [String: Any],
              let contents = item["content"] as? [[String: Any]] else { return }
        let itemId = item["id"] as? String
        let role = item["role"] as? String
        for content in contents {
            guard let transcript = content["transcript"] as? String, !transcript.isEmpty else { continue }
            guard isHumanSpeech(role: role,
                                contentType: content["type"] as? String,
                                event: "conversation.item") else { continue }
            emitCompletedTranscript(itemId: itemId, transcript: transcript)
        }
    }

    /// Whether this is user speech. The DECISION is made by the pure `RealtimeItemFilter`, which is
    /// covered by tests; only the log trace stays here, which the test package doesn't pull in.
    ///
    /// Only the role and type go to the log. The text itself is never logged (privacy).
    private func isHumanSpeech(role: String?, contentType: String?, event: String) -> Bool {
        switch RealtimeItemFilter.judge(role: role, contentType: contentType) {
        case .humanSpeech:
            return true
        case .unlabelled:
            Log.info(.voice, "Realtime: у \(event) не пришла роль, тип контента "
                           + "\(LogSanitizer.sanitize(contentType ?? "—")) — принимаем как речь человека")
            return true
        case .foreign(let role):
            // This is exactly the substitution users complain about: model text arriving
            // disguised as their speech. Level warn, not info, so the line is visible
            // in the log without digging through noise.
            Log.warn(.voice, "Realtime: отброшен item роли \(LogSanitizer.sanitize(role)) "
                           + "(тип контента \(LogSanitizer.sanitize(contentType ?? "—"))) — это не речь человека")
            return false
        }
    }

    private func emitCompletedTranscript(itemId: String?, transcript: String) {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let itemId, completedItemIds.contains(itemId) { return }
        if let itemId { completedItemIds.insert(itemId) }
        onSegmentCompleted?(trimmed)
    }
}

// MARK: - URLSession delegates

extension RealtimeTranscriptionClient: URLSessionWebSocketDelegate, URLSessionDelegate {
    func urlSession(_ session: URLSession,
                    webSocketTask: URLSessionWebSocketTask,
                    didOpenWithProtocol protocol: String?) {
        Log.info(.voice, "Realtime: WebSocket upgrade успешен")
    }

    func urlSession(_ session: URLSession,
                    webSocketTask: URLSessionWebSocketTask,
                    didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
                    reason: Data?) {
        let reasonText = reason.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        Log.info(.voice, "Realtime: WebSocket закрылся, code=\(closeCode.rawValue) reason=\(reasonText)")
        Task { @MainActor [weak self] in
            guard let self, self.isOpen else { return }
            if !reasonText.isEmpty {
                self.onError?(ClientError.server("WS закрылся: \(reasonText)"))
            }
            self.close()
        }
    }

    nonisolated func urlSession(_ session: URLSession,
                                task: URLSessionTask,
                                didCompleteWithError error: Error?) {
        if let error {
            let statusCode = (task.response as? HTTPURLResponse)?.statusCode
            Log.info(.voice, "Realtime: task didCompleteWithError status=\(statusCode.map(String.init) ?? "—") err=\(LogSanitizer.sanitize(error.localizedDescription))")
        }
    }
}
