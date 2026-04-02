import Foundation
import os

/// Event emitted by the agent loop for UI updates.
enum AgentEvent: Sendable {
    case textDelta(String)
    case toolStart(name: String, id: String)
    case toolResult(name: String, output: String)
    case turnComplete(text: String)
    case error(String)
}

/// Runs the tool execution loop: send → tool_use → execute → tool_result → repeat.
@MainActor
final class AgentLoop {
    private let claude = ClaudeService.shared
    private let registry: ToolRegistry
    private let maxTurns: Int
    private let logger = Logger(
        subsystem: "com.unstablemind.tamagotchai",
        category: "agent"
    )

    init(
        workingDirectory: String? = nil,
        maxTurns: Int = 50
    ) {
        registry = ToolRegistry.defaultRegistry(
            workingDirectory: workingDirectory
        )
        self.maxTurns = maxTurns
    }

    /// Run the agent loop with a conversation, streaming events back.
    func run(
        messages: [[String: Any]],
        systemPrompt: String? = nil,
        onEvent: @escaping @Sendable (AgentEvent) -> Void
    ) async throws -> [[String: Any]] {
        var conversation = messages
        let tools = registry.apiToolDefinitions()
        var accumulatedText = ""

        for turn in 0 ..< maxTurns {
            logger.info("Agent loop turn \(turn + 1)")

            let response = try await claude.sendWithTools(
                messages: conversation,
                tools: tools,
                systemPrompt: systemPrompt,
                onEvent: { event in
                    if case let .textDelta(text) = event {
                        onEvent(.textDelta(text))
                    }
                    if case let .toolUseStart(id, name) = event {
                        onEvent(.toolStart(name: name, id: id))
                    }
                }
            )

            // Build the assistant message content for conversation
            let assistantContent = buildAssistantContent(
                from: response
            )
            conversation.append([
                "role": "assistant",
                "content": assistantContent,
            ])

            // Accumulate text
            accumulatedText += response.textContent

            // Continue only if stop_reason is "tool_use" and we have tool calls
            let toolCalls = response.toolUseCalls
            let shouldContinue =
                response.stopReason == "tool_use" && !toolCalls.isEmpty
            if !shouldContinue {
                onEvent(.turnComplete(text: accumulatedText))
                return conversation
            }

            // Execute each tool and collect results
            let toolResults = await executeTools(
                toolCalls,
                onEvent: onEvent
            )

            // Add tool results as user message
            conversation.append([
                "role": "user",
                "content": toolResults,
            ])
        }

        let limit = maxTurns
        logger.warning("Agent loop hit max turns (\(limit))")
        onEvent(
            .error("Reached maximum number of turns (\(limit))")
        )
        onEvent(.turnComplete(text: accumulatedText))
        return conversation
    }

    // MARK: - Private Helpers

    private func buildAssistantContent(
        from response: ClaudeResponse
    ) -> [[String: Any]] {
        response.content.map { block in
            switch block {
            case let .text(text):
                ["type": "text", "text": text]
            case let .toolUse(id, name, input):
                [
                    "type": "tool_use",
                    "id": id,
                    "name": name,
                    "input": input,
                ] as [String: Any]
            case let .serverToolUse(id, name, input):
                [
                    "type": "server_tool_use",
                    "id": id,
                    "name": name,
                    "input": input,
                ] as [String: Any]
            case let .serverToolResult(toolUseId, content):
                [
                    "type": "web_search_tool_result",
                    "tool_use_id": toolUseId,
                    "content": content,
                ] as [String: Any]
            case let .serverToolResultError(toolUseId, errorCode):
                [
                    "type": "web_search_tool_result",
                    "tool_use_id": toolUseId,
                    "content": [[
                        "type": "web_search_tool_result_error",
                        "error_code": errorCode,
                    ]],
                ] as [String: Any]
            }
        }
    }

    private func executeTools(
        _ toolCalls: [(id: String, name: String, input: [String: Any])],
        onEvent: @escaping @Sendable (AgentEvent) -> Void
    ) async -> [[String: Any]] {
        var results: [[String: Any]] = []

        for call in toolCalls {
            let output: String
            nonisolated(unsafe) let args = call.input
            if let tool = registry.tool(named: call.name) {
                do {
                    output = try await tool.execute(args: args)
                } catch {
                    output = "Error: \(error.localizedDescription)"
                }
            } else {
                output = "Error: Unknown tool '\(call.name)'"
            }

            let truncated = truncateOutput(output)
            onEvent(
                .toolResult(name: call.name, output: truncated)
            )

            results.append([
                "type": "tool_result",
                "tool_use_id": call.id,
                "content": truncated,
            ])
        }

        return results
    }

    private func truncateOutput(
        _ output: String,
        maxChars: Int = 100_000
    ) -> String {
        if output.count <= maxChars {
            return output
        }
        let prefix = output.prefix(maxChars)
        return String(prefix) + "\n[...truncated at \(maxChars) chars]"
    }
}
