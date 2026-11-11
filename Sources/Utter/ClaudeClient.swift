import UtterCore
import Foundation

enum ClaudeError: LocalizedError {
    case missingAPIKey
    case http(status: Int, message: String)
    case refusal
    case badResponse

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: "Add your Anthropic API key in Settings."
        case let .http(status, message): "Claude API error \(status): \(message)"
        case .refusal: "Claude declined this request."
        case .badResponse: "Unexpected response from the Claude API."
        }
    }
}

/// Minimal Messages API client over raw HTTP (there is no official Swift SDK).
/// Bodies are plain JSON dictionaries so assistant content (including thinking
/// blocks) can be passed back to the API unchanged in tool loops.
struct ClaudeClient {
    let apiKey: String
    let model: String

    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    static func fromPrefs() throws -> ClaudeClient {
        guard let key = Keychain.apiKey() else { throw ClaudeError.missingAPIKey }
        return ClaudeClient(apiKey: key, model: Prefs.model)
    }

    /// Server-side refusal fallback ("default" routing). Not available for Haiku.
    private var supportsFallbacks: Bool { !model.contains("haiku") }

    func send(_ body: [String: Any]) async throws -> [String: Any] {
        var body = body
        body["model"] = model
        if supportsFallbacks { body["fallbacks"] = "default" }

        var request = URLRequest(url: Self.endpoint, timeoutInterval: 90)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2026-10-21", forHTTPHeaderField: "anthropic-version")
        if supportsFallbacks {
            request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        var attempt = 0
        while true {
            attempt += 1
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]

            if status == 200, let json {
                if json["stop_reason"] as? String == "refusal" { throw ClaudeError.refusal }
                return json
            }
            // Retry rate limits, overload and server errors with a short backoff.
            let retryable = status == 429 || status == 529 || status >= 500
            if retryable, attempt < 3 {
                try await Task.sleep(nanoseconds: UInt64(attempt) * 700_000_000)
                continue
            }
            let message = ((json?["error"] as? [String: Any])?["message"] as? String)
                ?? String(data: data, encoding: .utf8) ?? "unknown error"
            throw ClaudeError.http(status: status, message: message)
        }
    }

    /// Concatenates the response's text blocks.
    static func text(of message: [String: Any]) -> String {
        let blocks = message["content"] as? [[String: Any]] ?? []
        return blocks
            .filter { $0["type"] as? String == "text" }
            .compactMap { $0["text"] as? String }
            .joined()
    }
}
