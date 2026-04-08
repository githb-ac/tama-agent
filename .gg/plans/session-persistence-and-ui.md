# Session Persistence & Session List UI

## Analysis

### Current State
- `PromptPanelController` holds `conversationHistory: [[String: Any]]` in memory only
- Every `showPanel()` call resets `conversationHistory = []` — a fresh session each time
- No persistence of any conversation data between panel activations
- The conversation format is `[[String: Any]]` (Claude API message format — role + content blocks)

### Storage Decision: JSON Files (not SQLite)

**JSON files** are the right choice here for several reasons:
- Follows the established pattern — `ScheduleStore` already uses JSON + Codable for persistence
- Conversations are naturally document-shaped (one file per session)
- No additional dependencies needed (no SQLite library)
- Easy to debug — users can inspect files directly
- The `[[String: Any]]` message format maps cleanly to JSON
- Lightweight and reliable with atomic writes
- Storage location: `~/Library/Application Support/Tamagotchai/sessions/`

### Reference: HuggingFace chat-macOS

The [huggingface/chat-macOS](https://github.com/huggingface/chat-macOS) repo is the Spotlight-like reference. Key patterns:
- **Conversation model**: `id`, `title`, `updatedAt`, `messages`, grouped by date ("Today", "This Week", "This Month", "Older")
- **Sidebar**: `SidebarContent` in `ConversationView.swift` — a `List` with sections, each showing conversation titles
- **Selection**: `menuModel.currentConversationId` binds to list selection; `onChange` loads the conversation

For our UI, since we're a Spotlight-style panel (not a full window with sidebar), sessions should appear **below the input field** when the panel opens and input is empty — similar to Spotlight showing recent items. When the user starts typing, the session list hides and the normal chat flow begins.

### UI Approach

When the panel activates with no active session:
```
┌──────────────────────────────────────────┐
│ 🐱  Ask anything…                        │
├──────────────────────────────────────────┤
│  Today                                   │
│    Fix the login bug              12:30p │
│    Help me write tests             9:15a │
│  This Week                               │
│    Refactor auth module      Mon 3:45p   │
│    Debug memory leak         Sun 11:20a  │
└──────────────────────────────────────────┘
```

- Clicking a session loads it → shows full chat history in the response area
- Typing in the input field hides the session list → starts a new chat or continues the loaded one
- The session list uses the same visual language as the response area (NSVisualEffectView, same fonts/colors)
- Sessions grouped by date like HuggingChat: "Today", "This Week", "This Month", "Older"

## Architecture

### New Files
- `tamagotchai/Sources/Sessions/ChatSession.swift` — `Codable` session model
- `tamagotchai/Sources/Sessions/SessionStore.swift` — persistence + CRUD
- `tamagotchai/Sources/PromptPanel/SessionListView.swift` — AppKit session list below input

### Modified Files
- `tamagotchai/Sources/PromptPanel/FloatingPanel.swift` — add session list view, show/hide logic
- `tamagotchai/Sources/PromptPanel/PromptPanelController.swift` — wire session persistence, load/save on submit/dismiss
- `tamagotchai/Sources/AI/ClaudeModels.swift` — add `Codable` message types for persistence

### Data Model

```swift
struct ChatMessage: Codable, Identifiable {
    let id: UUID
    let role: MessageRole
    let content: [MessageContent]
    let timestamp: Date
    
    enum MessageRole: String, Codable { case user, assistant }
}

enum MessageContent: Codable {
    case text(String)
    case toolUse(id: String, name: String, input: Data) // JSON-encoded input
    case toolResult(toolUseId: String, content: String)
    case serverToolUse(id: String, name: String, input: Data)
    case serverToolResult(toolUseId: String, content: Data)
    case serverToolResultError(toolUseId: String, errorCode: String)
}

struct ChatSession: Codable, Identifiable {
    let id: UUID
    var title: String
    var messages: [ChatMessage]
    let createdAt: Date
    var updatedAt: Date
}
```

### Conversion Layer

The tricky part is converting between `[[String: Any]]` (the runtime API format) and `ChatMessage` (the Codable persistence format). We need:
- `ChatMessage.toAPIFormat() -> [String: Any]` — for sending to Claude
- `ChatMessage.fromAPIFormat(_ dict: [String: Any]) -> ChatMessage` — for saving after API returns

### Title Generation

Auto-generate session title from the first user message:
- Take first 50 chars of the first user message text
- Truncate at word boundary, add "…" if truncated

## Steps

1. Create `tamagotchai/Sources/Sessions/ChatSession.swift` with `ChatSession` and `ChatMessage` Codable models, including `MessageContent` enum with all content block types, and conversion methods between `[String: Any]` API format and the Codable types
2. Create `tamagotchai/Sources/Sessions/SessionStore.swift` — a `@MainActor` singleton that persists sessions as individual JSON files in `~/Library/Application Support/Tamagotchai/sessions/`, with methods: `loadAll()`, `save(session:)`, `delete(id:)`, `session(for:)`, and `allSessionsGroupedByDate()` returning `[String: [ChatSession]]` grouped into "Today"/"This Week"/"This Month"/"Older"
3. Create `tamagotchai/Sources/PromptPanel/SessionListView.swift` — an AppKit `NSView` subclass that displays grouped sessions in a scrollable list below the input field, using the same `NSVisualEffectView` + `.hudWindow` styling as the rest of the panel, with date section headers and session rows showing title + relative timestamp, a hover highlight effect, and a click handler callback `onSelectSession: ((ChatSession) -> Void)?`
4. Update `tamagotchai/Sources/PromptPanel/FloatingPanel.swift` to add the session list view between the divider and response area in `mainStack`, show it when the panel presents (if there are saved sessions and input is empty), hide it when the user starts typing or a chat is active, and add methods `showSessionList(_:)` and `hideSessionList()`
5. Update `tamagotchai/Sources/PromptPanel/PromptPanelController.swift` to create/load sessions: on `showPanel()` load and display recent sessions, on first `handleSubmit()` create a new `ChatSession` (or use the loaded one), save the session after each agent loop completion (updating `conversationHistory` and the session), restore a session when the user clicks one from the list (repopulate `conversationHistory` and render chat in the response area), and add a `currentSession: ChatSession?` property to track the active session
6. Update `tamagotchai/Sources/PromptPanel/FloatingPanel.swift` to add a `restoreConversation(messages:)` method that renders all past user bubbles and assistant responses into the response area from a loaded session, reusing the existing `makeUserBubble()` and `MarkdownRenderer.render()` methods, so clicking a session shows the full chat history
7. Verify the build compiles with `xcodegen generate && xcodebuild -project Tamagotchai.xcodeproj -scheme Tamagotchai -configuration Debug build` and fix any Swift 6 strict concurrency or type errors
