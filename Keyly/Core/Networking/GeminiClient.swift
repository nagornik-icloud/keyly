import Foundation

enum GeminiClient {
    private static let baseURL = "https://generativelanguage.googleapis.com/v1beta/models"

    /// The key goes in a header, never in the URL: URLs end up in proxy logs and error texts.
    static func generateContentRequest(model: String, apiKey: String) throws -> URLRequest {
        guard let encoded = model.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "\(baseURL)/\(encoded):generateContent") else {
            throw NSError(domain: "Gemini", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Invalid Gemini model name"])
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        return request
    }

    // MARK: - Text completion

    static func complete(prompt: String, model: String, apiKey: String) async throws -> String {
        let body: [String: Any] = [
            "contents": [["parts": [["text": prompt]]]]
        ]
        var request = try generateContentRequest(model: model, apiKey: apiKey)
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await LLMSession.shared.data(for: request)
        try validateHTTP(response, data: data, domain: "Gemini")
        return try extractText(from: data)
    }

    // MARK: - Audio transcription

    static func transcribe(audioData: Data, model: String, prompt: String, apiKey: String) async throws -> String {
        let b64 = audioData.base64EncodedString()
        let body: [String: Any] = [
            "contents": [[
                "parts": [
                    ["text": prompt],
                    ["inlineData": ["mimeType": "audio/m4a", "data": b64]]
                ]
            ]]
        ]
        var request = try generateContentRequest(model: model, apiKey: apiKey)
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await LLMSession.shared.data(for: request)
        try validateHTTP(response, data: data, domain: "Gemini")
        return try extractText(from: data)
    }

    // MARK: - Private

    private static func validateHTTP(_ response: URLResponse, data: Data, domain: String) throws {
        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: domain, code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Invalid server response"])
        }
        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: domain, code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "Gemini error: \(body)"])
        }
    }

    private static func extractText(from data: Data) throws -> String {
        struct GeminiResponse: Decodable {
            struct Candidate: Decodable {
                struct Content: Decodable {
                    struct Part: Decodable { let text: String? }
                    let parts: [Part]
                }
                let content: Content
            }
            let candidates: [Candidate]
        }
        let decoded = try JSONDecoder().decode(GeminiResponse.self, from: data)
        if let text = decoded.candidates.first?.content.parts.first?.text, !text.isEmpty {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        throw NSError(domain: "Gemini", code: 2,
                      userInfo: [NSLocalizedDescriptionKey: "Empty response from Gemini"])
    }
}
