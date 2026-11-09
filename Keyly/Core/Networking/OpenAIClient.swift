import Foundation

enum OpenAIClient {
    private static let chatURL = URL(string: "https://api.openai.com/v1/chat/completions")!
    private static let transcribeURL = URL(string: "https://api.openai.com/v1/audio/transcriptions")!

    // MARK: - Text completion

    /// `temperature` is optional: proofreading tasks need zero, conversational ones the provider
    /// default. Reasoning models (`gpt-5*`) REJECT any value ≠ 1 with a 400 — here it is silently
    /// omitted, otherwise picking such a model would break processing entirely (the same pitfall
    /// as `max_completion_tokens` during key validation).
    static func complete(systemPrompt: String, userText: String, model: String, apiKey: String,
                         temperature: Double? = nil) async throws -> String {
        var body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userText]
            ]
        ]
        if let temperature, acceptsTemperature(model: model) {
            body["temperature"] = temperature
        }
        var request = URLRequest(url: chatURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await LLMSession.shared.data(for: request)
        try validateHTTP(response, data: data, domain: "OpenAI")

        struct Response: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable { let content: String }
                let message: Message
            }
            let choices: [Choice]
        }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        guard let content = decoded.choices.first?.message.content, !content.isEmpty else {
            throw OpenAIError.emptyResponse
        }
        return content
    }

    // MARK: - Model quirks

    /// Whether the model accepts the `temperature` parameter. `gpt-5*` reasoning models don't: they
    /// answer 400 to any value other than 1, and the text processing request would fail entirely.
    /// Both processing functions used to send `temperature: 0` unconditionally, and picking gpt-5
    /// silently turned into "Polishing failed — text is raw".
    private static func acceptsTemperature(model: String) -> Bool {
        !model.hasPrefix("gpt-5")
    }

    // MARK: - Audio transcription

    static func transcribe(audioData: Data,
                           model: String,
                           prompt: String,
                           apiKey: String,
                           filename: String = "audio.m4a") async throws -> String {
        let mimeType = mimeType(for: filename)

        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()

        func append(_ s: String) { body.append(Data(s.utf8)) }

        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n")
        append("Content-Type: \(mimeType)\r\n\r\n")
        body.append(audioData)
        append("\r\n")

        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"model\"\r\n\r\n")
        append("\(model)\r\n")

        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"prompt\"\r\n\r\n")
        append("\(prompt)\r\n")

        append("--\(boundary)--\r\n")

        var request = URLRequest(url: transcribeURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let (data, response) = try await LLMSession.shared.data(for: request)
        try validateHTTP(response, data: data, domain: "OpenAI")

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = json["text"] as? String else {
            let raw = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "OpenAI", code: -2,
                          userInfo: [NSLocalizedDescriptionKey: "No text in response. Raw: \(raw)"])
        }
        return text
    }

    // MARK: - Private

    private static func mimeType(for filename: String) -> String {
        let ext = (filename as NSString).pathExtension.lowercased()
        switch ext {
        case "wav":  return "audio/wav"
        case "mp3":  return "audio/mpeg"
        case "mp4":  return "audio/mp4"
        case "mpeg", "mpga": return "audio/mpeg"
        case "webm": return "audio/webm"
        case "ogg":  return "audio/ogg"
        case "flac": return "audio/flac"
        case "m4a":  return "audio/m4a"
        default:     return "audio/m4a"
        }
    }

    private static func validateHTTP(_ response: URLResponse, data: Data, domain: String) throws {
        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: domain, code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Invalid server response"])
        }
        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: domain, code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: body])
        }
    }
}

enum OpenAIError: Error {
    case emptyResponse
}
