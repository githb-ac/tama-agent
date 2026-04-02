# Add Agent Tools to Tamagotchai

## Analysis

The tamagotchai app currently has a simple Claude integration (`ClaudeService.swift`) that sends messages and streams text deltas back — **no tool use support**. The gg-coder project has a full tool system (bash, read, write, edit, find, grep, ls, web_fetch) with an agent loop that handles the tool_use → tool_result round-trip.

### What Needs to Happen

The Anthropic Messages API tool use flow works like this:
1. Send request with `tools` array (JSON Schema definitions)
2. API responds with `stop_reason: "tool_use"` and `content` blocks containing `tool_use` blocks
3. Client executes the tool locally
4. Client sends back a `tool_result` block in the next request
5. API continues with the tool output in context

Currently `ClaudeService` only handles `content_block_delta` text events. We need to:
- Define tool schemas as JSON (matching Anthropic's `input_schema` format)
- Parse `tool_use` content blocks from the streaming response
- Execute tools locally (sandboxed shell commands, file read/write, etc.)
- Send `tool_result` messages back and continue the conversation loop

### Architecture Decision

We'll build this in Swift, matching gg-coder's architecture pattern but adapted for the macOS app context:

- **Tool protocol** — `AgentTool` protocol with `name`, `description`, `inputSchema`, and `execute()` method
- **Individual tool files** — One file per tool under `Sources/AI/Tools/`
- **Agent loop** — New `AgentLoop` class that wraps `ClaudeService` with tool execution loop
- **Tool registry** — Simple array of tools, configured at startup

### Tool Scope for v1

For a desktop assistant, we want these tools (subset of gg-coder):
- **bash** — Execute shell commands (the most powerful tool)
- **read** — Read file contents with line numbers
- **write** — Write/create files
- **edit** — Find-and-replace in files
- **ls** — List directory contents
- **find** — Find files by glob pattern
- **grep** — Search file contents with regex
- **web_fetch** — Fetch URL contents

We'll skip `subagent`, `tasks`, `task_output`, `task_stop`, `enter_plan`, `exit_plan`, `skill` — those are CLI-specific.

### Key Files to Create

- `Sources/AI/Tools/AgentTool.swift` — Protocol + registry
- `Sources/AI/Tools/BashTool.swift` — Shell command execution
- `Sources/AI/Tools/ReadTool.swift` — File reading
- `Sources/AI/Tools/WriteTool.swift` — File writing
- `Sources/AI/Tools/EditTool.swift` — Find-and-replace editing
- `Sources/AI/Tools/LsTool.swift` — Directory listing
- `Sources/AI/Tools/FindTool.swift` — Glob file finding
- `Sources/AI/Tools/GrepTool.swift` — Regex file search
- `Sources/AI/Tools/WebFetchTool.swift` — URL fetching
- `Sources/AI/AgentLoop.swift` — Tool use loop that wraps ClaudeService

### Key Files to Modify

- `Sources/AI/ClaudeService.swift` — Add tool definitions to API request body, parse `tool_use` blocks from stream, return structured response (not just text deltas)
- `Sources/PromptPanel/PromptPanelController.swift` — Use `AgentLoop` instead of calling `ClaudeService.send()` directly

### How Tool Use Appears in the Anthropic SSE Stream

When tools are provided, the streaming events include:
```
event: content_block_start
data: {"type":"content_block_start","index":0,"content_block":{"type":"tool_use","id":"toolu_xxx","name":"bash","input":{}}}

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"..."}}

event: content_block_stop
data: {"type":"content_block_stop","index":0}

event: message_delta
data: {"type":"message_delta","delta":{"stop_reason":"tool_use"}}
```

The client then sends back:
```json
{
  "role": "user",
  "content": [
    {
      "type": "tool_result",
      "tool_use_id": "toolu_xxx",
      "content": "Exit code: 0\nHello world"
    }
  ]
}
```

### Risks

- **Security**: Shell execution on user's machine needs sandboxing considerations. For v1, we'll run in the user's home directory with their permissions (same as gg-coder CLI).
- **Process management**: Long-running bash commands need timeouts. We'll use `Process` (Foundation) with timeout handling.
- **File path safety**: Need to resolve paths and reject symlinks (matching gg-coder's approach).
- **Binary file detection**: Need extension-based binary check for read/grep tools.

## Steps

1. Create `Sources/AI/Tools/AgentTool.swift` with the `AgentTool` protocol defining `name: String`, `description: String`, `inputSchema: [String: Any]`, and `func execute(args: [String: Any]) async throws -> String`, plus a `ToolRegistry` class that holds the array of tools and serializes their schemas for the API
2. Create `Sources/AI/Tools/BashTool.swift` implementing shell command execution via Foundation `Process`, with timeout support (default 120s), output truncation (keep last 200 lines if over 2000 lines), TERM=dumb environment, and combined stdout/stderr capture
3. Create `Sources/AI/Tools/ReadTool.swift` implementing file reading with line numbers (cat -n style), offset/limit support, binary file detection by extension, and output truncation at 2000 lines or 50KB
4. Create `Sources/AI/Tools/WriteTool.swift` implementing file writing with parent directory creation, tracking of read files to prevent blind overwrites of existing files
5. Create `Sources/AI/Tools/EditTool.swift` implementing find-and-replace editing with exact text matching, uniqueness validation (must match exactly once), CRLF handling, and unified diff output
6. Create `Sources/AI/Tools/LsTool.swift` implementing directory listing with file types (d/f), human-readable sizes, directories-first sorting, and optional hidden file display
7. Create `Sources/AI/Tools/FindTool.swift` implementing glob-based file finding that walks the directory tree, respects common ignore patterns (node_modules, .git), caps results at 100, and sorts alphabetically
8. Create `Sources/AI/Tools/GrepTool.swift` implementing regex-based file content search returning filepath:line:content format, skipping binary files, with configurable max results (default 50) and case-insensitive option
9. Create `Sources/AI/Tools/WebFetchTool.swift` implementing URL fetching with HTML tag stripping, SSRF protection (block localhost/private IPs), content truncation at configurable max length (default 10000 chars), and 30-second timeout
10. Refactor `Sources/AI/ClaudeService.swift` to support a new `sendWithTools()` method that includes tool definitions in the API request body, parses streaming events for both text deltas AND tool_use content blocks (accumulating partial JSON from `input_json_delta` events), and returns a structured response containing text content and tool calls instead of just text strings
11. Create `Sources/AI/AgentLoop.swift` implementing the tool execution loop: send message with tools → if response has tool_use blocks, execute each tool → send tool_results back → repeat until the model responds with end_turn (no tool calls), with a max turns limit of 50 and proper error handling
12. Update `Sources/PromptPanel/PromptPanelController.swift` to use `AgentLoop` instead of calling `ClaudeService.send()` directly, streaming both text deltas and tool execution status updates to the floating panel, and updating the system prompt to describe available tools and the working directory
