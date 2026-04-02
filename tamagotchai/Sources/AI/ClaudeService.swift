import Foundation
import os

extension TimeZone {
    func offsetString() -> String {
        let seconds = secondsFromGMT()
        let h = abs(seconds) / 3600
        let m = (abs(seconds) % 3600) / 60
        let sign = seconds >= 0 ? "+" : "-"
        return m == 0
            ? "\(sign)\(h)"
            : String(format: "%@%d:%02d", sign, h, m)
    }
}

/// A single content block in a Claude API response.
enum ContentBlock: @unchecked Sendable {
    case text(String)
    case toolUse(id: String, name: String, input: [String: Any])
    /// Server-side tool (web_search) — executed by Anthropic, passed through as-is.
    case serverToolUse(id: String, name: String, input: [String: Any])
    /// Server-side tool result (web_search_tool_result) — passed through as-is.
    case serverToolResult(toolUseId: String, content: [[String: Any]])
    /// Server-side tool result error (web_search_tool_result with error).
    case serverToolResultError(toolUseId: String, errorCode: String)
}

/// Structured response from a Claude API call.
struct ClaudeResponse: @unchecked Sendable {
    let content: [ContentBlock]
    let stopReason: String?

    var textContent: String {
        content.compactMap { block in
            if case let .text(text) = block { return text }
            return nil
        }.joined()
    }

    var toolUseCalls: [(id: String, name: String, input: [String: Any])] {
        content.compactMap { block in
            if case let .toolUse(id, name, input) = block {
                return (id: id, name: name, input: input)
            }
            return nil
        }
    }
}

/// Event streamed during a sendWithTools call.
enum StreamEvent: Sendable {
    case textDelta(String)
    case toolUseStart(id: String, name: String)
    case response(ClaudeResponse)
}

/// Singleton service for calling the Anthropic Messages API with OAuth credentials.
@MainActor
final class ClaudeService {
    static let shared = ClaudeService()

    private let logger = Logger(
        subsystem: "com.unstablemind.tamagotchai",
        category: "claude"
    )
    private let apiURL = URL(string: "https://api.anthropic.com/v1/messages")!
    private let model = "claude-haiku-4-5-20251001"

    /// Base system prompt — static, cacheable.
    let baseSystemPrompt = """
    You are Tamagotchai, a personal assistant living on the user's desktop.

    ## personality & tone

    Talk like texting a close friend. Chill, casual, real.

    - lowercase always (except proper nouns, acronyms, or emphasis)
    - skip periods at end of messages
    - emojis sparingly
    - direct and concise - no fluff, no corporate speak
    - joke around, be a little sarcastic, keep it fun
    - if something's unclear, ask instead of guessing
    - you help with tasks, answer questions, and keep them motivated
    - never say "I'm an AI" or "as a language model" — you're their homie on the desktop
    """

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

    /// Sends a conversation and returns an async stream of text deltas (legacy).
    func send(
        messages: [[String: String]],
        systemPrompt: String? = nil
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let token = try await self.validAccessToken()
                    try await self.streamRequestLegacy(
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

    /// Sends a conversation with tool definitions and streams events back.
    /// Returns a structured ClaudeResponse with both text and tool_use blocks.
    func sendWithTools(
        messages: [[String: Any]],
        tools: [[String: Any]],
        systemPrompt: String? = nil,
        onEvent: @escaping @Sendable (StreamEvent) -> Void
    ) async throws -> ClaudeResponse {
        let token = try await validAccessToken()
        return try await streamRequestWithTools(
            token: token,
            messages: messages,
            tools: tools,
            systemPrompt: systemPrompt,
            onEvent: onEvent
        )
    }

    // MARK: - Token Management

    private func validAccessToken() async throws -> String {
        guard var creds = credentials else {
            throw ClaudeServiceError.notLoggedIn
        }

        if creds.isExpired {
            logger.info("Token expired, refreshing…")
            let refreshed = try await ClaudeOAuth.refreshToken(
                creds.refreshToken
            )
            try ClaudeCredentials.save(refreshed)
            credentials = refreshed
            creds = refreshed
        }

        return creds.accessToken
    }

    // MARK: - Legacy Streaming (text only)

    private func streamRequestLegacy(
        token: String,
        messages: [[String: String]],
        systemPrompt: String?,
        continuation: AsyncThrowingStream<String, Error>.Continuation
    ) async throws {
        let request = try buildRequest(
            token: token,
            messages: messages,
            tools: nil,
            systemPrompt: systemPrompt
        )

        let (bytes, response) = try await URLSession.shared.bytes(
            for: request
        )

        guard let http = response as? HTTPURLResponse,
              (200 ..< 300).contains(http.statusCode)
        else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw ClaudeServiceError.apiError(statusCode: code)
        }

        var currentEvent = ""

        for try await line in bytes.lines {
            if line.hasPrefix("event: ") {
                currentEvent = String(line.dropFirst(7))
            } else if line.hasPrefix("data: "),
                      currentEvent == "content_block_delta"
            {
                let json = String(line.dropFirst(6))
                if let data = json.data(using: .utf8),
                   let obj = try? JSONSerialization.jsonObject(
                       with: data
                   ) as? [String: Any],
                   let delta = obj["delta"] as? [String: Any],
                   let text = delta["text"] as? String
                {
                    continuation.yield(text)
                }
            } else if line.hasPrefix("data: "),
                      currentEvent == "error"
            {
                let json = String(line.dropFirst(6))
                if let data = json.data(using: .utf8),
                   let obj = try? JSONSerialization.jsonObject(
                       with: data
                   ) as? [String: Any],
                   let error = obj["error"] as? [String: Any],
                   let message = error["message"] as? String
                {
                    continuation.finish(
                        throwing: ClaudeServiceError.streamError(message)
                    )
                    return
                }
            }
        }

        continuation.finish()
    }

    // MARK: - Tool-aware Streaming

    private func streamRequestWithTools(
        token: String,
        messages: [[String: Any]],
        tools: [[String: Any]],
        systemPrompt: String?,
        onEvent: @escaping @Sendable (StreamEvent) -> Void
    ) async throws -> ClaudeResponse {
        let request = try buildRequest(
            token: token,
            messages: messages,
            tools: tools,
            systemPrompt: systemPrompt
        )

        let (bytes, response) = try await URLSession.shared.bytes(
            for: request
        )

        guard let http = response as? HTTPURLResponse,
              (200 ..< 300).contains(http.statusCode)
        else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw ClaudeServiceError.apiError(statusCode: code)
        }

        return try await parseToolStream(
            bytes: bytes,
            onEvent: onEvent
        )
    }

    // MARK: - Dynamic Context

    private func dynamicContext() -> String {
        let now = Date()
        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "EEEE, MMMM d, yyyy"
        let timeFmt = DateFormatter()
        timeFmt.dateFormat = "h:mm a"
        let tz = TimeZone.current

        return """
        [current context]
        date: \(dateFmt.string(from: now))
        time: \(timeFmt.string(from: now))
        timezone: \(tz.identifier) (UTC\(tz.offsetString()))
        platform: macOS
        """
    }

    // MARK: - Request Building

    private func buildRequest(
        token: String,
        messages: [[String: Any]],
        tools: [[String: Any]]?,
        systemPrompt: String?
    ) throws -> URLRequest {
        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        request.setValue(
            "Bearer \(token)",
            forHTTPHeaderField: "Authorization"
        )
        request.setValue(
            "2023-06-01",
            forHTTPHeaderField: "anthropic-version"
        )
        request.setValue(
            "claude-code-20250219,oauth-2025-04-20,prompt-caching-2024-07-31",
            forHTTPHeaderField: "anthropic-beta"
        )
        request.setValue(
            "application/json",
            forHTTPHeaderField: "Content-Type"
        )
        request.setValue(
            "claude-cli/2.1.75",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("cli", forHTTPHeaderField: "x-app")

        var systemBlocks: [[String: Any]] = []

        // Base prompt — static, cached
        var baseBlock: [String: Any] = [
            "type": "text",
            "text": baseSystemPrompt,
        ]
        if systemPrompt != nil {
            // Cache the base block when there's extra context after it
            baseBlock["cache_control"] = ["type": "ephemeral"]
        }
        systemBlocks.append(baseBlock)

        // Extra context (tools description, etc.) — cached
        if let extra = systemPrompt {
            systemBlocks.append([
                "type": "text",
                "text": extra,
                "cache_control": ["type": "ephemeral"],
            ])
        }

        // Dynamic context — current time, never cached
        systemBlocks.append([
            "type": "text",
            "text": dynamicContext(),
        ])

        var body: [String: Any] = [
            "model": model,
            "max_tokens": 16384,
            "stream": true,
            "system": systemBlocks,
            "messages": messages,
        ]

        // Merge client tools with server-side tools (web search)
        var allTools: [[String: Any]] = tools ?? []
        allTools.append([
            "type": "web_search_20250305",
            "name": "web_search",
            "max_uses": 5,
        ])
        body["tools"] = allTools

        request.httpBody = try JSONSerialization.data(
            withJSONObject: body
        )

        return request
    }

    // MARK: - Stream Parsing

    private func parseToolStream(
        bytes: URLSession.AsyncBytes,
        onEvent: @escaping @Sendable (StreamEvent) -> Void
    ) async throws -> ClaudeResponse {
        let parser = StreamParser(onEvent: onEvent)
        try await parser.parse(bytes: bytes)
        let result = parser.buildResponse()
        onEvent(.response(result))
        return result
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

// MARK: - StreamParser

/// Parses SSE events from the Anthropic streaming API, tracking text and
/// tool_use content blocks.
private class StreamParser {
    private let onEvent: @Sendable (StreamEvent) -> Void
    private var currentEvent = ""
    private var contentBlocks: [ContentBlock] = []
    private var stopReason: String?

    // Client tool-use accumulation
    private var toolId: String?
    private var toolName: String?
    private var toolJsonParts: [String] = []
    private var isServerTool = false

    // Server tool result accumulation
    private var serverResultToolUseId: String?
    private var serverResultContent: [[String: Any]] = []

    // Text accumulation
    private var textParts: [String] = []

    init(onEvent: @escaping @Sendable (StreamEvent) -> Void) {
        self.onEvent = onEvent
    }

    func parse(bytes: URLSession.AsyncBytes) async throws {
        for try await line in bytes.lines {
            try processLine(line)
        }
        flushText()
    }

    func buildResponse() -> ClaudeResponse {
        ClaudeResponse(
            content: contentBlocks,
            stopReason: stopReason
        )
    }

    // MARK: - Line Processing

    private func processLine(_ line: String) throws {
        if line.hasPrefix("event: ") {
            currentEvent = String(line.dropFirst(7))
            return
        }

        guard line.hasPrefix("data: ") else { return }
        let json = String(line.dropFirst(6))
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(
                  with: data
              ) as? [String: Any]
        else { return }

        switch currentEvent {
        case "content_block_start":
            handleBlockStart(obj)
        case "content_block_delta":
            handleBlockDelta(obj)
        case "content_block_stop":
            handleBlockStop()
        case "message_delta":
            handleMessageDelta(obj)
        case "message_stop":
            // Final signal — flush any remaining state
            flushText()
        case "error":
            try handleError(obj)
        default:
            break
        }
    }

    private func handleBlockStart(_ obj: [String: Any]) {
        guard let block = obj["content_block"] as? [String: Any],
              let type = block["type"] as? String
        else { return }

        if type == "tool_use" {
            flushText()
            toolId = block["id"] as? String
            toolName = block["name"] as? String
            toolJsonParts = []
            isServerTool = false
            if let id = toolId, let name = toolName {
                onEvent(.toolUseStart(id: id, name: name))
            }
        } else if type == "server_tool_use" {
            flushText()
            toolId = block["id"] as? String
            toolName = block["name"] as? String
            toolJsonParts = []
            isServerTool = true
            if let id = toolId, let name = toolName {
                onEvent(.toolUseStart(id: id, name: name))
            }
        } else if type == "web_search_tool_result" {
            let useId = block["tool_use_id"] as? String ?? ""
            let content = block["content"] as? [[String: Any]] ?? []
            // Check for error in the content array
            if let first = content.first,
               first["type"] as? String == "web_search_tool_result_error",
               let errorCode = first["error_code"] as? String
            {
                contentBlocks.append(
                    .serverToolResultError(
                        toolUseId: useId,
                        errorCode: errorCode
                    )
                )
            } else {
                contentBlocks.append(
                    .serverToolResult(
                        toolUseId: useId,
                        content: content
                    )
                )
            }
        } else if type == "text" {
            textParts = []
        }
    }

    private func handleBlockDelta(_ obj: [String: Any]) {
        guard let delta = obj["delta"] as? [String: Any],
              let type = delta["type"] as? String
        else { return }

        if type == "text_delta",
           let text = delta["text"] as? String
        {
            textParts.append(text)
            onEvent(.textDelta(text))
        } else if type == "input_json_delta",
                  let partial = delta["partial_json"] as? String
        {
            toolJsonParts.append(partial)
        }
    }

    private func handleBlockStop() {
        if let id = toolId {
            let fullJson = toolJsonParts.joined()
            var input: [String: Any] = [:]
            if let jsonData = fullJson.data(using: .utf8),
               let parsed = try? JSONSerialization.jsonObject(
                   with: jsonData
               ) as? [String: Any]
            {
                input = parsed
            }
            if isServerTool {
                contentBlocks.append(
                    .serverToolUse(
                        id: id,
                        name: toolName ?? "",
                        input: input
                    )
                )
            } else {
                contentBlocks.append(
                    .toolUse(
                        id: id,
                        name: toolName ?? "",
                        input: input
                    )
                )
            }
            toolId = nil
            toolName = nil
            toolJsonParts = []
            isServerTool = false
        } else {
            flushText()
        }
    }

    private func handleMessageDelta(_ obj: [String: Any]) {
        if let delta = obj["delta"] as? [String: Any],
           let reason = delta["stop_reason"] as? String
        {
            stopReason = reason
        }
    }

    private func handleError(_ obj: [String: Any]) throws {
        if let error = obj["error"] as? [String: Any],
           let message = error["message"] as? String
        {
            throw ClaudeService.ClaudeServiceError.streamError(message)
        }
    }

    private func flushText() {
        guard !textParts.isEmpty else { return }
        contentBlocks.append(.text(textParts.joined()))
        textParts = []
    }
}
