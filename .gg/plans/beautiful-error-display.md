# Beautiful Error Display

## Problem
Errors display as raw technical text (e.g. `Error: Claude API error (HTTP 429)`) — unstyled, unhelpful, and unclear whether it's the user's fault or a provider issue.

## Error Sources (All Display Points)

1. **Stream/API errors** — `PromptPanelController.swift:331` — `panel.showResponse("Error: \(error.localizedDescription)")`
2. **Not-logged-in** — `PromptPanelController.swift:214-218` — `panel.showResponse("Not logged in to Claude...")`
3. **Agent loop errors** — `AgentLoop.swift:278-282` — `onEvent(.error(msg))` — inline `⚠️` text
4. **Login view errors** — `LoginView.swift:113-117` — plain red text
5. **Token refresh errors** — `ClaudeService.swift:101` — thrown up to #1
6. **Tool errors** — `AgentLoop.swift:189` — returned to LLM, not user-facing directly

## Design: Styled Error Blocks

Errors render as styled blocks in the response area — left-aligned, colored background, rounded rect. Clean and to the point. No emojis.

### Visual Design
- **Background**: Tinted rounded rect — red for provider errors, orange for auth, muted for user-action-needed
- **Border**: Subtle matching-color border
- **Text**: Title line (bold) + message line (regular), white/light color
- **Layout**: Left-aligned, full width with padding
- **No icons, no emojis** — just clear text

### Error categories — clear attribution to who's at fault

| Error | Current | New |
|-------|---------|-----|
| HTTP 429 | "Claude API error (HTTP 429)" | Title: "Claude is Overloaded" / Message: "Anthropic's servers are under heavy load. Try again in a moment." |
| HTTP 401/403 | "Claude API error (HTTP 401)" | Title: "Authentication Failed" / Message: "Your Claude session has expired. Log in again to continue." |
| HTTP 500/502/503 | "Claude API error (HTTP 500)" | Title: "Claude is Having Issues" / Message: "Anthropic's servers are experiencing problems. Try again shortly." |
| Not logged in | "Not logged in to Claude..." | Title: "Not Connected" / Message: "Log in to Claude from the menu bar to get started." |
| Network timeout | "The request timed out." | Title: "Connection Timed Out" / Message: "Couldn't reach Anthropic's servers. Check your internet and try again." |
| Stream errors | "Claude error: ..." | Title: "Stream Interrupted" / Message: simplified friendly text |
| OAuth errors | Raw HTTP body | Title: "Login Failed" / Message: "Couldn't connect to Anthropic. Please try again." |

## Steps

1. Add `showError(title:message:tint:)` method to `FloatingPanel` — renders a styled left-aligned block (tinted background, rounded rect, bold title + regular message)
2. Create `AppError` enum in `tamagotchai/Sources/PromptPanel/AppError.swift` — maps raw errors to `(title, message, tint)` tuples
3. Update `PromptPanelController.handleSubmit` catch block to map errors through `AppError` and call `panel.showError()`
4. Update not-logged-in path to use `panel.showError()`
5. Update agent loop `.error` event to use a subtle styled inline block instead of plain `⚠️` text
6. Improve `LoginView` error display with a styled pill (tinted background) instead of plain red text
