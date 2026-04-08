# Comprehensive Logging

## Problem

The app has almost zero useful logging. Errors are silently swallowed (`try?`), catch blocks show inline UI messages but don't log, API failures lose their response bodies, tool executions have no timing or error logs, and credential operations silently fail. There's no way to diagnose issues without attaching a debugger.

## Approach

Add `os.Logger` usage across every file that does I/O, error handling, or state transitions. Use Apple's unified logging with the existing subsystem `com.unstablemind.tamagotchai` and category-per-file. Log levels:

- `.debug` — verbose state transitions, timing, streaming details (already exists in FloatingPanel)
- `.info` — normal lifecycle events (app launch, login, tool execution, API calls)
- `.warning` — recoverable issues (credential load fail, tool not found, truncation)
- `.error` — failures (API errors, tool crashes, OAuth failures, credential save/load)
- `.fault` — should-never-happen states (nil panel, impossible code paths)

**How to view:** `log stream --predicate 'subsystem == "com.unstablemind.tamagotchai"' --level debug` in Terminal, or Console.app filtered by the subsystem.

## Audit of every file and what's missing

### TamagotchaiApp.swift
- No logging at all. Should log app launch, hotkey registration result.

### ClaudeService.swift (category: "claude")
- Has logger but barely uses it. Only logs token refresh.
- Missing: API request details (model, message count, tool count), HTTP status on error with response body, stream parsing errors, request build failures.

### ClaudeOAuth.swift
- Zero logging. Should log login start, code exchange attempt, token exchange HTTP status/error, state mismatch details, refresh attempts.

### ClaudeCredentials.swift
- Zero logging. Every `try?` silently swallows errors. Should log save/load/delete operations and their failures.

### AgentLoop.swift (category: "agent")
- Has logger, logs turn count and max-turns warning.
- Missing: tool execution errors (caught but only returned as string), tool execution timing, unknown tool name, API call failures propagating up.

### PromptPanelController.swift (category: "hotkey")
- Has logger, logs hotkey registration failures.
- Missing: submit handling, conversation history state, agent loop errors, stream errors in the catch block.

### FloatingPanel.swift (category: "panel")
- Has panelLogger with decent streaming debug logs.
- Missing: present/dismiss lifecycle, response errors.

### All Tools (BashTool, ReadTool, WriteTool, EditTool, LsTool, FindTool, GrepTool, WebFetchTool)
- Zero logging in any tool. Should log execution start (with key args), result summary, errors, timing.

### MascotView.swift
- No logging needed (pure UI animation).

### LoginView.swift
- Errors shown in UI but not logged.

### PermissionsChecker.swift
- No logging. Should log permission check results.

### StreamParser.swift
- No logging. Should log parse errors, unexpected event types.

## Steps

1. In `tamagotchai/Sources/AI/ClaudeCredentials.swift`: Add a private file-level logger (category: "credentials"). Log `.info` on successful save/load/delete. Log `.error` when `credentialsURL()` fails, when `ChaChaPoly.seal` fails, when `Data(contentsOf:)` fails, when `ChaChaPoly.open` fails, when JSON decode fails — replace the chain of `try?`/`guard` in `load()` with individual do/catch blocks so each failure point is logged separately. Log `.warning` if `getHardwareUUID()` returns nil (falling back to hardcoded key).

2. In `tamagotchai/Sources/AI/ClaudeOAuth.swift`: Add a private file-level logger (category: "oauth"). Log `.info` on `startLogin()` (with state UUID). Log `.info` on `completeLogin` entry (with code length, state). Log `.error` on invalid code format, state mismatch (log expected vs actual), token exchange HTTP failures (log status + response body). Log `.info` on successful token exchange. Log `.info` on `refreshToken` start. Log `.error` on refresh failure.

3. In `tamagotchai/Sources/AI/ClaudeService.swift`: Enhance existing logger. Log `.info` on `sendWithTools` call (message count, tool count). Log `.error` on API HTTP errors — read the response body and log it (currently discarded). Log `.error` on token refresh failure. Log `.info` on successful token refresh with new expiry. Log `.warning` on `notLoggedIn` error.

4. In `tamagotchai/Sources/AI/StreamParser.swift`: Add a private file-level logger (category: "stream"). Log `.error` on stream error events (the message from Anthropic). Log `.warning` on unrecognized event types. Log `.debug` on content_block_start with type. Log `.info` when parse completes with block count summary (N text blocks, N tool_use blocks, stop_reason).

5. In `tamagotchai/Sources/AI/AgentLoop.swift`: Enhance existing logger. Log `.info` on tool execution start (tool name, arg keys). Log `.error` when tool execution throws (tool name, error). Log `.warning` when unknown tool is requested (tool name). Log `.info` on tool execution complete (tool name, output length, duration in ms). Log `.error` when `sendWithTools` throws (the error). Log `.info` on turn complete with stop_reason.

6. In `tamagotchai/Sources/AI/Tools/BashTool.swift`: Add a private file-level logger (category: "tool.bash"). Log `.info` on execute start (command truncated to 200 chars, timeout). Log `.info` on execute complete (exit code, output length, whether timed out). Log `.error` on process launch failure.

7. In `tamagotchai/Sources/AI/Tools/ReadTool.swift`: Add a private file-level logger (category: "tool.read"). Log `.info` on execute (resolved path, offset, limit). Log `.warning` on binary file detected. Log `.error` on file read failure. Log `.info` on success (line count returned).

8. In `tamagotchai/Sources/AI/Tools/WriteTool.swift`: Add a private file-level logger (category: "tool.write"). Log `.info` on execute (resolved path, content byte count). Log `.error` on failures. Log `.info` on success.

9. In `tamagotchai/Sources/AI/Tools/EditTool.swift`: Add a private file-level logger (category: "tool.edit"). Log `.info` on execute (file path, old_text length, new_text length). Log `.error` on not found, multiple matches, file not readable. Log `.info` on success.

10. In `tamagotchai/Sources/AI/Tools/LsTool.swift`: Add a private file-level logger (category: "tool.ls"). Log `.info` on execute (path, showAll). Log `.error` on directory not found. Log `.info` on success (dir count, file count).

11. In `tamagotchai/Sources/AI/Tools/FindTool.swift`: Add a private file-level logger (category: "tool.find"). Log `.info` on execute (pattern, path). Log `.error` on directory not found. Log `.info` on success (match count).

12. In `tamagotchai/Sources/AI/Tools/GrepTool.swift`: Add a private file-level logger (category: "tool.grep"). Log `.info` on execute (pattern, path, include). Log `.error` on invalid regex, path not found. Log `.info` on success (match count, files searched count).

13. In `tamagotchai/Sources/AI/Tools/WebFetchTool.swift`: Add a private file-level logger (category: "tool.web"). Log `.info` on execute (URL, max_length). Log `.error` on blocked host, invalid URL, HTTP errors. Log `.info` on success (response size, truncated or not).

14. In `tamagotchai/Sources/PromptPanel/PromptPanelController.swift`: Enhance existing logger (rename category to "controller"). Log `.info` on `toggle()` (current visibility). Log `.info` on `showPanel()`. Log `.info` on `handleSubmit` (user text length). Log `.error` in the stream catch block (the actual error). Log `.warning` when not logged in on submit. Log `.info` on conversation history update (message count).

15. In `tamagotchai/Sources/PromptPanel/FloatingPanel.swift`: Add `.info` logs for `present()` and `dismiss()` lifecycle. Log `.error` if `streamResponse` receives an error from the stream.

16. In `tamagotchai/Sources/TamagotchaiApp.swift`: Add a private logger (category: "app"). Log `.info` on `applicationDidFinishLaunching` with login status and accessibility permission status. Log `.info` on `applicationWillTerminate`.

17. In `tamagotchai/Sources/Permissions/PermissionsChecker.swift`: Add a private logger (category: "permissions"). Log `.info` on each permission check with the result (granted/denied).
