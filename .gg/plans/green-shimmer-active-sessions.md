# Green Shimmer for Active Chat Sessions

## Analysis

When the user dismisses the panel while an agent is still running, the `activeAgentTask` continues in the background (see `PromptPanelController.swift` line 237–253). When the panel is reopened, the session list shows but there's no visual indication of which chat is still processing.

### Key observations:
- `PromptPanelController` has `activeAgentTask` (Task) and `currentSession` (ChatSession?) tracking the active agent
- When panel is dismissed via `onDismiss`, only UI tasks are cancelled — `activeAgentTask` keeps running
- `SessionRowView` (private class in `SessionListView.swift`) renders each row with a title label
- The existing `SkeletonView` has a shimmer pattern using `CAGradientLayer` + `CABasicAnimation` we can reference

### Approach:
- Add a `Set<UUID>` of active session IDs to `SessionStore` (simple, central, observable)
- When agent starts for a session, add its ID; when done, remove it
- `SessionRowView` checks if its session is active and applies a green gradient shimmer mask on the title label
- The shimmer uses a `CAGradientLayer` with green-tinted colors animated left-to-right, applied as a mask on the title text

### Files to modify:
- `tamagotchai/Sources/Sessions/SessionStore.swift` — add `activeSessionIDs: Set<UUID>` with add/remove methods
- `tamagotchai/Sources/PromptPanel/SessionListView.swift` — pass active IDs to `SessionRowView`, add shimmer layer on title
- `tamagotchai/Sources/PromptPanel/PromptPanelController.swift` — mark session active on submit, inactive on completion/cancel

## Steps

1. In `SessionStore.swift`, add a `private(set) var activeSessionIDs: Set<UUID> = []` property with `markActive(_ id: UUID)` and `markInactive(_ id: UUID)` methods (4 lines each, just mutate the set and log).

2. In `SessionListView.swift`, add an `activeSessionIDs: Set<UUID>` parameter to the `reload(groups:emptyMessage:)` method (stored as a property), pass it through to `makeSessionRow`, and forward to `SessionRowView`.

3. In `SessionRowView` (inside `SessionListView.swift`), add a green shimmer effect: create a `CAGradientLayer` with green-tinted translucent colors (`NSColor.systemGreen` at varying opacities), position it over the title label, animate its `locations` from left to right (similar to `SkeletonView`'s shimmer pattern), and apply it only when the session ID is in the active set. The title text color should shift to a green tint (`NSColor.systemGreen`) when active.

4. In `FloatingPanel+Lists.swift`, update all calls to `sessionListView.reload(...)` to pass `activeSessionIDs: SessionStore.shared.activeSessionIDs` — this includes `showSessionList`, `filterSessionList`.

5. In `PromptPanelController.swift` `handleSubmit`, after `saveCurrentSession()` creates/updates `currentSession`, call `SessionStore.shared.markActive(currentSession!.id)` right before the `activeAgentTask = Task { ... }` block. Inside the task's completion paths (after `saveCurrentSession()` on success, and in all error/cancellation handlers), call `SessionStore.shared.markInactive(currentSession.id)`.

6. In `PromptPanelController.swift` `showPanel()`, when rebuilding the session list, pass `SessionStore.shared.activeSessionIDs` so already-running sessions show the shimmer immediately on panel reopen.

7. In `PromptPanelController.swift`, after the agent completes and calls `markInactive`, refresh the visible session list if the panel is showing the chats tab — call `handleTabChanged(currentTab)` or directly reload the session list so the shimmer stops.
