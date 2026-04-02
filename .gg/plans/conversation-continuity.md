# Conversation Continuity & UI Improvements

## Analysis

**Current state:**
- `ClaudeService.send()` sends a single `messages` array with one user message — no history
- `FloatingPanel` clears everything on `present()` but never clears the input after a response finishes
- `responseMaxHeight` is 400px — the response area can't grow beyond this
- System prompt is `"You are Claude Code, Anthropic's official CLI for Claude."` — wrong identity

**What needs to change:**

### 1. Clear input after response finishes
In `FloatingPanel.finishTyping()` and `showResponse()`, clear `inputField.stringValue` so the user can type a follow-up.

### 2. Conversation history in the response area
The response area currently replaces its content each time. Instead, we need to accumulate messages. The simplest approach: maintain a `conversationMarkdown` string that accumulates all messages (user + assistant), and render that into the text view. Each new streamed response appends to it.

Layout: user messages right-aligned or prefixed with **You:**, assistant messages prefixed with assistant label. Simplest: just use markdown headers/separators.

### 3. Conversation history in API calls  
`ClaudeService` needs to accept a `messages` array (not just a single string). The controller maintains the conversation history and passes it each time.

### 4. System prompt
Change from Claude Code identity to Tamagotchai personal assistant identity.

## Steps
1. In `ClaudeService.swift` (line 13), replace the `systemPromptPrefix` with a Tamagotchai-themed system prompt that describes a personal assistant focused on helping users with tasks and keeping them motivated.
2. In `ClaudeService.swift`, change the `send()` method (line 37) to accept `messages: [[String: String]]` instead of `userMessage: String`, and update `streamRequest` (line 78) to pass the full messages array to the API body instead of a single user message.
3. In `PromptPanelController.swift`, add a `private var conversationHistory: [[String: String]] = []` property to track the conversation. Update `handleSubmit` (line 68) to append the user message to history before sending, pass the full history to `ClaudeService.send()`, and append the assistant response to history after streaming completes.
4. In `FloatingPanel.swift`, add a `private var conversationMarkdown = ""` property that accumulates all rendered messages. Update `streamResponse` to append a user message header (e.g. `"\n\n---\n\n**You:** <text>\n\n"`) to `conversationMarkdown` before streaming, then stream the assistant's response appended after it. The `displayedMarkdown` should be `conversationMarkdown + currentStreamingText`.
5. In `FloatingPanel.swift`, update `finishTyping()` (line ~538) to: (a) commit the final assistant text into `conversationMarkdown`, (b) clear `inputField.stringValue = ""`, and (c) make the input field first responder again so the user can type immediately.
6. In `FloatingPanel.swift`, increase `responseMaxHeight` from 400 to 600 (line 19) to give more room for multi-turn conversations.
7. In `FloatingPanel.swift`, update `showResponse()` (used for error messages) to also clear the input field after displaying.
8. In `PromptPanelController.swift`, reset `conversationHistory` in `showPanel()` (line 49) when the panel is freshly presented, so each panel invocation starts a new conversation.
9. Build and verify with `xcodebuild`.
