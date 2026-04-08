# Notifications & Schedule Sessions Plan

## Analysis

### Current Notification Issues
- `NotchNotificationPresenter` toast has a fixed width (340pt) and subtitle is capped at `maximumNumberOfLines = 2` with `lineBreakMode = .byTruncatingTail` (line 225)
- Routine results are additionally truncated to 200 chars via `String(result.prefix(200))` (line 41)
- The toast panel has `ignoresMouseEvents = true` (line 95) — not clickable at all
- No way to view full notification content after dismissal

### Current Scheduler + Sessions Architecture
- `ScheduleStore.executeRoutine()` creates a standalone `AgentLoop()` with no session context (line 198)
- Routine results are fire-and-forget — shown as notifications, never persisted to any session
- Reminders are also fire-and-forget — just a notification with name + prompt text
- The session system (`SessionStore` + `ChatSession`) is entirely chat-focused
- `ScheduleStore` persists jobs to `schedules.json`, completely separate from sessions

### What Needs to Change

**Notifications:**
- Remove the 2-line cap, allow dynamic height (up to a max)
- Remove `ignoresMouseEvents = true` to make clickable
- On click: open a detail modal panel (same glassmorphic style as chat UI, scrollable, full content)
- Auto-dismiss timer should pause on hover and resume on mouse exit

**Schedule Sessions:**
- Create two special "system" sessions: one for Reminders, one for Routines
- These are non-deletable, always present in the session list
- Routine execution should save its prompt + result as messages in the Routines session
- Reminder firing should save the reminder name + text in the Reminders session
- Add a tab bar / segment control at the top of the session list to filter: All | Reminders | Routines
- The Reminders/Routines sessions appear under their respective tabs (not in "All" — or maybe they do appear in All too, always pinned at top)

## Steps

1. In `NotchNotificationPresenter.swift`, increase subtitle `maximumNumberOfLines` from 2 to 5, remove the `String(result.prefix(200))` truncation in `showRoutineResult`, and make toast height dynamic based on content (up to a max of ~200pt), keeping the `fittingSize` approach but with a taller cap.

2. In `NotchNotificationPresenter.swift`, remove `panel.ignoresMouseEvents = true` (line 95), add mouse click handling that calls a new `onTap` closure, pause the auto-dismiss timer on `mouseEntered` and resume on `mouseExited` by using a tracking area on the toast panel's content view.

3. Create `tamagotchai/Sources/Notifications/NotificationDetailPanel.swift` — an NSPanel subclass styled identically to `FloatingPanel` (glassmorphic `NSVisualEffectView` with `hudWindow` material, corner radius 28, same 680pt width). It displays the full notification title + body in a scrollable `NSTextView` (read-only, same markdown rendering style). Has a close button (X) or dismisses on Escape/focus loss. Presented centered on screen.

4. Wire `NotchNotificationPresenter`'s `onTap` to dismiss the toast and open `NotificationDetailPanel` with the full title + body text. Store the current notification's full title/body as static properties so they're available on click.

5. In `ChatSession.swift`, add a `sessionType` property: `enum SessionType: String, Codable { case chat, reminders, routines }` with a default of `.chat`. Add a custom `init(from:)` fallback for legacy sessions. Add a computed `isDeletable: Bool` that returns `false` for reminders/routines types.

6. In `SessionStore.swift`, add methods `remindersSession()` and `routinesSession()` that return the singleton system sessions, creating them on first access with well-known UUIDs (hardcoded). Add `appendMessage(to sessionId: UUID, message: ChatMessage)` for appending a single message without replacing the whole session. Filter system sessions from deletion in `delete(id:)`.

7. In `ScheduleStore.swift`, update `fireReminderNotification(_:)` to also append a message (role: .assistant, content: "**Reminder: {name}**\n\n{prompt}") to the Reminders system session via `SessionStore.shared.appendMessage(...)`.

8. In `ScheduleStore.swift`, update `executeRoutine(_:)` to append both the prompt (as user message) and the result (as assistant message) to the Routines system session via `SessionStore.shared.appendMessage(...)`.

9. In `SessionListView.swift`, add a segmented tab bar at the top with three segments: "All", "Reminders", "Routines". The "All" tab shows all chat sessions (with system sessions pinned at top). "Reminders" tab loads the Reminders system session directly (acts as a click to view it). "Routines" tab loads the Routines system session directly. Add an `onTabChanged` callback and `selectedTab` state.

10. In `FloatingPanel.swift`, wire the new tab bar — add `showSessionList` overload or update existing to accept a tab selection. Forward tab changes to `PromptPanelController` via a new `onTabChanged` callback.

11. In `PromptPanelController.swift`, handle tab selection — when "Reminders" or "Routines" tab is selected, load the corresponding system session via `loadSession()`. When "All" is selected, show the normal grouped session list. Update `deleteSession` to check `isDeletable` and skip system sessions.

12. Build the project with `xcodegen generate && xcodebuild -project Tamagotchai.xcodeproj -scheme Tamagotchai -configuration Debug build` and fix any compilation errors.
