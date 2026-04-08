# Remove Server-Side Web Search (Moonshot `$web_search` & Anthropic `server_tool_use`)

## Background

We have a built-in `WebSearchTool` (`web_search`) in our tool registry that scrapes DuckDuckGo/Brave/Google. Previously, certain providers also had their own server-side web search:

- **Moonshot**: injected a `$web_search` built-in tool, handled via `call.name.hasPrefix("$")` in AgentLoop
- **Anthropic (StreamParser)**: handled `server_tool_use` and `web_search_tool_result` content blocks for Anthropic's server-side web search

Since all models now use our built-in `web_search` tool, the server-side web search code paths are dead code.

## What to Remove

### 1. Moonshot `$web_search` injection — `ClaudeService.swift` (lines 339–345)
Remove the block that injects `$web_search` into OpenAI tools when provider is `.moonshot`.

### 2. Provider built-in `$`-prefixed tool execution — `AgentLoop.swift` (lines 182–204)
Remove the `call.name.hasPrefix("$")` block that skips local execution for server-side tools. All tools are now local.

### 3. Server tool content blocks — `ClaudeModels.swift` (lines 7–12)
Remove `serverToolUse`, `serverToolResult`, `serverToolResultError` cases from `ContentBlock`.

### 4. Server tool handling in `StreamParser.swift`
- Remove `isServerTool` flag (line 22) and all references
- Remove the `server_tool_use` handling in `handleBlockStart` (lines 119–127)
- Remove the `web_search_tool_result` handling in `handleBlockStart` (lines 128–149)
- In `handleBlockStop`, remove the `isServerTool` branch — always append `.toolUse` (lines 196–212)

### 5. Server tool round-tripping in `AgentLoop.swift`
- `buildAssistantContent` (lines 149–170): remove `serverToolUse`, `serverToolResult`, `serverToolResultError` switch cases

### 6. Server tool skip in `convertToolToOpenAI` — `ClaudeService.swift` (lines 445–448)
Remove the filter that skips tools with type containing `web_search`. Our built-in tool uses `name` not `type`.

### 7. Server tool skip in `CodexRequestBuilder.swift` (lines 164–167)
Same pattern — remove the `type.contains("web_search")` filter.

### 8. Server tool types in `ChatSession.swift`
- Remove `serverToolUse`, `serverToolResult`, `serverToolResultError` from `MessageContent` enum (lines 18–20)
- Remove their `CodingKeys`, `ContentType` cases, encode/decode paths
- Remove `server_tool_use` and `web_search_tool_result` handling in `from(apiMessage:)` (lines 197–219)
- Remove `serverToolUse`, `serverToolResult`, `serverToolResultError` in `toAPIFormat()` (lines 246–258)

### 9. Moonshot-specific web search system prompt notes — `PromptPanelController.swift` (lines 604–606, 621–623)
Remove the `webSearchNote` conditional that adds a special note for Moonshot. All providers now have web search via the built-in tool, so mention it unconditionally in the system prompt.

### 10. Update Moonshot comment in `ClaudeService.swift` (line 5)
Update the doc comment referencing "Moonshot/Kimi" — still valid as a provider, just no longer special for web search.

### 11. `reasoning_content` round-tripping — `AgentLoop.swift` (lines 84–88) & `ClaudeService.swift` (lines 412–415)
Keep this — it's used by Xiaomi/Moonshot for thinking round-trips, not web-search-specific.

### 12. `OpenAIStreamParser.swift` comments (lines 9, 22)
Update Moonshot-specific comments to say "OpenAI-compatible providers" generically.

## Risks

- **Existing sessions**: Saved `ChatSession` data may contain `serverToolUse`/`serverToolResult`/`serverToolResultError` blocks. Removing these `MessageContent` cases will cause decoding failures for old sessions. **Mitigation**: Add a `.unknown` fallback case that silently drops unrecognized block types during decode, or handle the missing cases gracefully in `init(from:)`.
- **Anthropic models not present yet**: If we ever add Anthropic Claude models directly (which use `server_tool_use` for their built-in web search), we'd need to re-add this. But since we're currently only using third-party providers, this is fine.

## Steps

1. In `ClaudeService.swift`, remove the Moonshot `$web_search` injection block (lines 339–345) and the `type.contains("web_search")` filter in `convertToolToOpenAI` (lines 445–448)
2. In `AgentLoop.swift`, remove the `call.name.hasPrefix("$")` provider built-in tool block (lines 182–204) and remove the `serverToolUse`/`serverToolResult`/`serverToolResultError` cases from `buildAssistantContent` (lines 149–170)
3. In `ClaudeModels.swift`, remove `serverToolUse`, `serverToolResult`, `serverToolResultError` cases from `ContentBlock` and update the comment on line 19
4. In `StreamParser.swift`, remove `isServerTool` flag and all server tool handling (`server_tool_use`, `web_search_tool_result` in `handleBlockStart`, the `isServerTool` branch in `handleBlockStop`)
5. In `CodexRequestBuilder.swift`, remove the `type.contains("web_search")` server tool filter (lines 164–167)
6. In `ChatSession.swift`, remove `serverToolUse`/`serverToolResult`/`serverToolResultError` from `MessageContent` enum and all their encode/decode/convert paths, adding a fallback for old persisted data that may contain these types
7. In `PromptPanelController.swift`, remove the Moonshot-specific `webSearchNote` conditional and mention web search unconditionally in both `agentSystemPrompt` and `voiceSystemPrompt`
8. In `OpenAIStreamParser.swift`, update Moonshot-specific comments to be generic
9. Build and verify with `xcodebuild` — fix any remaining compile errors from removed cases
