import Foundation

/// Turns an LLM request error (URLError / NSError with an API response body / APIKeyError)
/// into a short human-readable toast message.
///
/// Why: any failure of the text modules used to go silently into a log line and `return nil` —
/// the user saw nothing and took it as "the request went out and never came back".
/// Now the reason (no key, nonexistent model, no network, quota exhausted) is shown in an
/// explicit toast.
enum LLMErrorPresenter {

    static func userMessage(for error: Error, provider: APIProvider, model: String) -> String {
        if let apiKeyError = error as? APIKeyError {
            switch apiKeyError {
            case .missingKey:    return "llm.error.missingKey".loc(provider.title)
            }
        }

        if error is OpenAIError {
            return "llm.error.emptyAnswer".loc(model)
        }

        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost:
                return "llm.error.offline".loc
            case .timedOut:
                return "llm.error.timeout".loc(provider.title)
            default:
                return "llm.error.network".loc(provider.title)
            }
        }

        let ns = error as NSError
        let body = (ns.userInfo[NSLocalizedDescriptionKey] as? String) ?? ns.localizedDescription

        // The OpenAI/Gemini response body usually contains {"error":{"code":...,"message":...}}.
        if let code = apiErrorCode(from: body) {
            switch code {
            case "model_not_found":
                return "llm.error.badModel".loc(model)
            case "invalid_api_key":
                return "llm.error.badKey".loc(provider.title)
            case "insufficient_quota":
                return "llm.error.providerQuota".loc(provider.title)
            case "unsupported_parameter", "unsupported_value":
                return "llm.error.badParams".loc(model)
            default:
                break
            }
        }

        switch ns.code {
        case 401:        return "llm.error.badKey".loc(provider.title)
        case 403:        return "llm.error.http403".loc(provider.title, model)
        case 404:        return "llm.error.http404".loc(model)
        case 429:        return "llm.error.http429".loc(provider.title)
        case 500...599:  return "llm.error.http5xx".loc(provider.title)
        default:         return "llm.error.generic".loc(provider.title)
        }
    }

    /// Extracts `error.code` (or `error.type`) from the API response JSON body.
    private static func apiErrorCode(from body: String) -> String? {
        guard let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = json["error"] as? [String: Any] else { return nil }
        if let code = error["code"] as? String { return code }
        if let type = error["type"] as? String { return type }
        return nil
    }
}
