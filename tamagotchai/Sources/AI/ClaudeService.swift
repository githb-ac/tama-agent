import Foundation
import os

/// Singleton service for calling the Anthropic Messages API with OAuth credentials.
@MainActor
final class ClaudeService {
    static let shared = ClaudeService()

    private let logger = Logger(subsystem: "com.unstablemind.tamagotchai", category: "claude")
    private let apiURL = URL(string: "https://api.anthropic.com/v1/messages")!
    private let model = "claude-haiku-4-5-20251001"

    private let systemPromptPrefix =
        "You are Tamagotchai, a friendly personal assistant on the user's desktop. " +
        "You help with tasks, answer questions, and keep the user motivated. " +
        "Be concise, warm, and helpful."

    /// Current credentials — loaded from Keychain on init.
    private(set) var credentials: OAuthCredentials?

    var isLoggedIn: Bool { credentials != nil }

    private init() {
        credentials = ClaudeCredentials.load()
    }

    /// Update credentials after login/refresh.
    func setCredentials(_ creds: OAuthCredentials?) {
        credentials = creds
    }

    func logout() {
        credentials = nil
        ClaudeCredentials.delete()
    }

    // MARK: - API

    /// Sends a conversation and returns an async stream of text deltas.
    func send(
        messages: [[String: String]],
        systemPrompt: String? = nil
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let token = try await self.validAccessToken()
                    try await self.streamRequest(
                        token: token,
                        messages: messages,
                        systemPrompt: systemPrompt,
                        continuation: continuation
                    )
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Token Management

    private func validAccessToken() async throws -> String {
        guard var creds = credentials else {
            throw ClaudeServiceError.notLoggedIn
        }

        if creds.isExpired {
            logger.info("Token expired, refreshing…")
            let refreshed = try await ClaudeOAuth.refreshToken(creds.refreshToken)
            try ClaudeCredentials.save(refreshed)
            credentials = refreshed
            creds = refreshed
        }

        return creds.accessToken
    }

    // MARK: - Streaming Request

    private func streamRequest(
        token: String,
        messages: [[String: String]],
        systemPrompt: String?,
        continuation: AsyncThrowingStream<String, Error>.Continuation
    ) async throws {
        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("claude-code-20250219,oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("claude-cli/2.1.75", forHTTPHeaderField: "User-Agent")
        request.setValue("cli", forHTTPHeaderField: "x-app")

        let fullSystemPrompt: String = if let extra = systemPrompt {
            systemPromptPrefix + "\n\n" + extra
        } else {
            systemPromptPrefix
        }

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 4096,
            "stream": true,
            "system": fullSystemPrompt,
            "messages": messages,
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)

        guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw ClaudeServiceError.apiError(statusCode: statusCode)
        }

        var currentEvent = ""

        for try await line in bytes.lines {
            if line.hasPrefix("event: ") {
                currentEvent = String(line.dropFirst(7))
            } else if line.hasPrefix("data: "), currentEvent == "content_block_delta" {
                let json = String(line.dropFirst(6))
                if let data = json.data(using: .utf8),
                   let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let delta = obj["delta"] as? [String: Any],
                   let text = delta["text"] as? String
                {
                    continuation.yield(text)
                }
            } else if line.hasPrefix("data: "), currentEvent == "error" {
                let json = String(line.dropFirst(6))
                if let data = json.data(using: .utf8),
                   let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let error = obj["error"] as? [String: Any],
                   let message = error["message"] as? String
                {
                    continuation.finish(throwing: ClaudeServiceError.streamError(message))
                    return
                }
            }
        }

        continuation.finish()
    }

    // MARK: - Errors

    enum ClaudeServiceError: LocalizedError {
        case notLoggedIn
        case apiError(statusCode: Int)
        case streamError(String)

        var errorDescription: String? {
            switch self {
            case .notLoggedIn:
                "Not logged in to Claude. Use the menu bar to log in."
            case let .apiError(statusCode):
                "Claude API error (HTTP \(statusCode))"
            case let .streamError(message):
                "Claude error: \(message)"
            }
        }
    }
}
