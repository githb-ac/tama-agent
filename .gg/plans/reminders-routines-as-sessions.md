# Reminders & Routines as Individual Sessions

## Current State
- Each reminder/routine saves to a single monolithic system session (one for all reminders, one for all routines)
- Reminders/Routines tab shows conversation-style content in the response area
- System sessions are pinned at top of "All" tab
- `showSystemSessionContent` renders messages in the response text view

## Goal
- Each reminder firing = its own session (like chat sessions), displayed as a row in the session list
- Each routine execution = its own session, same treatment
- Tabs filter the session list: All shows only `.chat`, Reminders shows only `.reminders`, Routines shows only `.routines`
- Each tab shows sessions as rows (same UI as chat sessions) with time, title, delete, click-to-view
- Cap at 25 most recent per type; auto-prune older ones
- No more pinned section in "All" tab
- Clicking a reminder/routine row loads it like a normal session (restoreConversation)

## Files Changed

### `tamagotchai/Sources/Sessions/SessionStore.swift`
- Remove `remindersSessionID`, `routinesSessionID` constants
- Remove `remindersSession()`, `routinesSession()` singleton methods
- Remove `appendMessage()` method  
- Revert `allSessionsGroupedByDate()` to only include `.chat` sessions (remove pinned section)
- Add `sessionsGroupedByDate(type:)` that filters by `SessionType` and groups the same way
- Add `pruneExcess(type:max:)` that deletes oldest sessions of a type when count exceeds max
- Make `isDeletable` always true (all sessions are deletable now)
- Remove protection in `delete(id:)` that blocks non-deletable sessions

### `tamagotchai/Sources/Sessions/ChatSession.swift`
- Remove `isDeletable` computed property (or make it always return true)
- Keep `SessionType` enum as-is

### `tamagotchai/Sources/Scheduler/ScheduleStore.swift`
- `fireReminderNotification`: create a new `.reminders` session per firing with title = job name, one assistant message with the reminder text
- `executeRoutine`: create a new `.routines` session per execution with title = job name, user message = prompt, assistant message = result
- Both call `pruneExcess` after saving to enforce the 25-cap

### `tamagotchai/Sources/PromptPanel/FloatingPanel.swift`
- Remove `showSystemSessionContent` method entirely
- Remove `isShowingSystemSession` flag
- `showSessionList` stays the same — just shows grouped rows with tab bar
- Tab bar remains in the main stack (already there)

### `tamagotchai/Sources/PromptPanel/PromptPanelController.swift`
- `handleTabChanged(.all)` → calls `SessionStore.shared.allSessionsGroupedByDate()` (chat only)
- `handleTabChanged(.reminders)` → calls `SessionStore.shared.sessionsGroupedByDate(type: .reminders)` and passes to `showSessionList`
- `handleTabChanged(.routines)` → calls `SessionStore.shared.sessionsGroupedByDate(type: .routines)` and passes to `showSessionList`
- `showPanel()` loads `.all` tab by default
- Clicking a reminder/routine session row works the same as chat — `loadSession`

### `tamagotchai/Sources/PromptPanel/SessionListView.swift`
- Remove `showDelete` flag from `SessionRowView` — all rows get delete button
- Revert `makeSessionRow` to not pass `showDelete`

## Steps
1. In `ChatSession.swift`, remove the `isDeletable` computed property entirely
2. In `SessionStore.swift`, remove the fixed system session IDs, `remindersSession()`, `routinesSession()`, `appendMessage()`, and the deletion guard on `isDeletable`; revert `allSessionsGroupedByDate` to exclude non-chat sessions without a pinned section; add `sessionsGroupedByDate(type:)` and `pruneExcess(type:max:)` methods
3. In `ScheduleStore.swift`, replace the `appendMessage` calls with creating a new individual session per reminder firing and per routine execution, then call `pruneExcess(type:, max: 25)` after each save
4. In `FloatingPanel.swift`, remove `showSystemSessionContent` method and `isShowingSystemSession` flag; remove the system-session cleanup from `showSessionList`
5. In `PromptPanelController.swift`, update `handleTabChanged` for `.reminders` and `.routines` to call `sessionsGroupedByDate(type:)` and pass to `showSessionList`; update `deleteSession` to remove the `isDeletable` guard
6. In `SessionListView.swift`, remove the `showDelete` parameter from `SessionRowView` so all rows show delete on hover
7. Build, fix lint errors, and verify
