# Browser Automation Tool — CDP Engine

## Overview

Add a `browser` agent tool to Tamagotchai that controls Chromium-based browsers (Chrome, Brave, Edge, Arc, Vivaldi, Opera) via the Chrome DevTools Protocol over a native `URLSessionWebSocketTask` WebSocket connection. Zero external dependencies. Zero cost.

## Architecture

Three new files:

### 1. `tamagotchai/Sources/AI/Tools/Browser/CDPConnection.swift`
Low-level CDP WebSocket client. Handles:
- Connecting to `ws://127.0.0.1:{port}/devtools/page/{targetId}` via `URLSessionWebSocketTask`
- Sending JSON-RPC commands (`{id, method, params}`) and matching responses by `id`
- Receiving async events pushed by Chrome
- Auto-incrementing command IDs
- Concurrent send/receive with `AsyncStream` for events

Key types:
```
final class CDPConnection: @unchecked Sendable {
    func connect(url: URL) async throws
    func send(method: String, params: [String: Any]?) async throws -> [String: Any]
    func disconnect()
    var events: AsyncStream<CDPEvent>
}
struct CDPEvent { let method: String; let params: [String: Any] }
```

### 2. `tamagotchai/Sources/AI/Tools/Browser/BrowserManager.swift`
Manages browser lifecycle — discovery, launch, and connection. Handles:
- Auto-detecting installed Chromium browsers on macOS by checking known paths:
  - `/Applications/Google Chrome.app/Contents/MacOS/Google Chrome`
  - `/Applications/Brave Browser.app/Contents/MacOS/Brave Browser`
  - `/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge`
  - `/Applications/Arc.app/Contents/MacOS/Arc`
  - `/Applications/Vivaldi.app/Contents/MacOS/Vivaldi`
  - `/Applications/Opera.app/Contents/MacOS/Opera`
  - `/Applications/Chromium.app/Contents/MacOS/Chromium`
- **Connect mode**: Reading `DevToolsActivePort` file from user data dir, or probing port 9222, to attach to an already-running browser with remote debugging enabled
- **Launch mode**: Spawning a new browser process with `--remote-debugging-port=0 --headless=new` (or headed), parsing the WS URL from stderr
- Discovering page targets via `GET http://127.0.0.1:{port}/json/list`
- Maintaining a singleton `CDPConnection` that persists across tool calls (reused within an agent loop)
- Cleanup on disconnect

Key types:
```
final class BrowserManager: @unchecked Sendable {
    static let shared: BrowserManager
    func ensureConnected(headless: Bool) async throws -> CDPConnection
    func disconnect()
}
```

### 3. `tamagotchai/Sources/AI/Tools/Browser/BrowserTool.swift`
The `AgentTool` implementation. Single tool with an `action` parameter that dispatches to high-level browser operations. Actions:

| Action | CDP Methods Used | Description |
|--------|-----------------|-------------|
| `navigate` | `Page.navigate` + wait `Page.loadEventFired` | Go to a URL |
| `click` | `Runtime.evaluate` (querySelector) → `DOM.getBoxModel` → `Input.dispatchMouseEvent` (mouseMoved, mousePressed, mouseReleased) | Click an element by CSS selector |
| `type` | `Runtime.evaluate` (focus) → `Input.dispatchKeyEvent` per char | Type text into focused/selected element |
| `get_text` | `Runtime.evaluate` (`document.querySelector(sel).innerText`) | Extract text content from element |
| `get_html` | `Runtime.evaluate` (`document.documentElement.outerHTML`) | Get page HTML |
| `screenshot` | `Page.captureScreenshot` | Take a screenshot, return base64 PNG |
| `evaluate` | `Runtime.evaluate` | Execute arbitrary JavaScript |
| `wait` | `Runtime.evaluate` polling loop | Wait for a selector to appear |

Input schema:
```json
{
  "type": "object",
  "properties": {
    "action": { "type": "string", "enum": ["navigate", "click", "type", "get_text", "get_html", "screenshot", "evaluate", "wait"] },
    "url": { "type": "string", "description": "URL to navigate to (navigate action)" },
    "selector": { "type": "string", "description": "CSS selector for element targeting" },
    "text": { "type": "string", "description": "Text to type or JS to evaluate" },
    "headless": { "type": "boolean", "description": "Run headless (default: false)" },
    "timeout": { "type": "integer", "description": "Timeout in ms (default: 30000)" }
  },
  "required": ["action"]
}
```

## Registration

Add `BrowserTool()` to `ToolRegistry.defaultRegistry()` in `AgentTool.swift` (line 57-74).

## Implementation Details

### CDP WebSocket Protocol
- Each command: `{"id": N, "method": "Page.navigate", "params": {"url": "..."}}`
- Each response: `{"id": N, "result": {...}}` or `{"id": N, "error": {"code": ..., "message": "..."}}`
- Events (no `id`): `{"method": "Page.loadEventFired", "params": {...}}`
- Use `URLSessionWebSocketTask` — no SPM dependency needed
- Pending commands tracked in a `[Int: CheckedContinuation]` dictionary
- Background receive loop forwards events to an `AsyncStream`

### Browser Discovery & Launch
- `Process` to launch browser (same pattern as `BashTool`)
- Parse stderr for `DevTools listening on ws://...` line
- For connect mode: `URLSession.shared.data(from: URL("http://127.0.0.1:9222/json/list"))` to get targets
- Fallback: read `~/Library/Application Support/Google/Chrome/DevToolsActivePort` 

### Clicking Strategy
Rather than the complex DOM.getBoxModel → Input.dispatchMouseEvent pipeline, use `Runtime.evaluate` with JS that calls `element.click()` for simplicity and reliability. This avoids coordinate math and viewport issues. For sites that check `event.isTrusted`, we can add the low-level input dispatch as a future enhancement.

### Screenshot Return
`Page.captureScreenshot` returns base64 PNG. Return it as `[Screenshot captured: {width}x{height}, {byteSize} bytes base64 PNG]` with a truncated preview. The agent can reference it but we don't return the full base64 to avoid token bloat.

### Logging
Category: `tool.browser` — following existing convention.

### Error Handling
`BrowserToolError` enum as `LocalizedError`, matching existing tool pattern:
- `noBrowserFound` — no Chromium browser installed
- `connectionFailed(String)` — WebSocket connection error  
- `commandFailed(String)` — CDP command returned error
- `timeout` — operation timed out
- `missingParameter(String)` — required param not provided
- `elementNotFound(String)` — selector matched nothing

### Concurrency
- `CDPConnection` is `@unchecked Sendable` (holds the WebSocket task and pending continuations)
- `BrowserManager` is `@unchecked Sendable` (singleton with lock-protected state)
- `BrowserTool` is a plain `final class: AgentTool` (stateless, delegates to BrowserManager)

## Risks

- **Chrome 136+ profile lock**: `--remote-debugging-port` is silently ignored on default profiles. Connect mode must handle this by reading DevToolsActivePort or falling back to launch mode.
- **Browser not installed**: Graceful error message listing which browsers we looked for.
- **Port conflicts**: Using port 0 for launch mode avoids conflicts.
- **Process cleanup**: Must terminate launched browser on disconnect to avoid zombie processes.

## Steps

1. Create `tamagotchai/Sources/AI/Tools/Browser/CDPConnection.swift` — the low-level CDP WebSocket client with `connect()`, `send()`, `disconnect()`, event stream, and pending-command matching via `[Int: CheckedContinuation]`
2. Create `tamagotchai/Sources/AI/Tools/Browser/BrowserManager.swift` — browser path detection for all Chromium variants on macOS, launch mode (spawn process, parse WS URL from stderr), connect mode (read DevToolsActivePort / probe port 9222 / fetch `/json/list`), singleton lifecycle management
3. Create `tamagotchai/Sources/AI/Tools/Browser/BrowserTool.swift` — the `AgentTool` implementation with action-based dispatch (navigate, click, type, get_text, get_html, screenshot, evaluate, wait), input schema, error enum, and logging
4. Register `BrowserTool()` in `ToolRegistry.defaultRegistry()` in `tamagotchai/Sources/AI/Tools/AgentTool.swift` by adding it to the tools array
5. Run `xcodegen generate` then `xcodebuild -project Tamagotchai.xcodeproj -scheme Tamagotchai -configuration Debug build` to verify clean compilation
