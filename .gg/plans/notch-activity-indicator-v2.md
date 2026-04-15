# Notch Activity Indicator — Multi-Process Aware

## Overview

A persistent notch-hugging activity indicator that tracks ALL concurrent Tama processes — not just the user's chat agent, but also background routines. Shows a count when multiple things are running, and the most recent activity text.

## Design

### Single process running:
- `"Thinking…"` or `"Running ls"` — same as original plan

### Multiple processes running:
- `"(3) Tama processes running…"` — shows count of active processes
- When a tool event comes in from the chat agent, briefly shows that tool detail: `"(3) Reading file.swift"`
- The count updates in real-time as routines start/finish

### Process types tracked:
- **Chat agent** — the user's active agent task (from PromptPanelController)
- **Routines** — background scheduled routines (from ScheduleStore.activeRoutineIDs)

Reminders are instant (fire-and-forget notifications), so they don't count as "processes."

### Architecture

`NotchActivityIndicator` becomes a process tracker with:
- A set of active process IDs (chat agent gets a fixed ID, routines use their job IDs)
- `addProcess(id:label:)` / `removeProcess(id:)` — manages the set, shows/hides the indicator
- `updateDetail(id:text:)` — updates the detail text for a specific process (tool events)
- Display logic: 1 process → show its label/detail. 2+ processes → show count + latest detail

### Hook points

**Chat agent (PromptPanelController):**
- `onDismiss` with active agent → `addProcess(id: "chat-agent", label: "Thinking…")`
- `handleAgentEvent` when dismissed → `updateDetail(id: "chat-agent", text: toolDisplayName)`
- `completeAgentRun` / `handleAgentDismissed` / `showPanel` / `cancelAllActiveTasks` → `removeProcess(id: "chat-agent")`

**Routines (ScheduleStore):**
- `executeRoutine` start → `addProcess(id: job.id, label: "Routine: \(job.name)")`
- `executeRoutine` end → `removeProcess(id: job.id)`

This way the indicator automatically shows/hides based on whether ANY process is active, and the count is always correct.

## Files

| File | Change |
|------|--------|
| **NEW** `tama/Sources/Notifications/NotchActivityIndicator.swift` | Multi-process activity indicator |
| `tama/Sources/PromptPanel/PromptPanelController.swift` | Hook chat agent lifecycle |
| `tama/Sources/Scheduler/ScheduleStore.swift` | Hook routine execution lifecycle |

## Steps

1. Create `tama/Sources/Notifications/NotchActivityIndicator.swift` — a `@MainActor enum` that manages a notch-shaped activity panel tracking multiple concurrent processes: maintains a dictionary of `[String: ProcessInfo]` where ProcessInfo has `label` and optional `detail`; `addProcess(id:label:)` inserts a process and shows the indicator if not visible (or updates text if already shown); `removeProcess(id:)` removes a process and hides the indicator when empty; `updateDetail(id:text:)` sets transient tool detail for a process; display logic shows single-process label when count is 1 or `"(N) Tama processes active"` with the latest detail when count > 1; uses same FlippedLayerView + NotchShapePath window pattern as NotchNotificationPresenter with a smaller size (notchSize.height + 36 tall, notchSize.width + 120 wide) and shimmer animation on the text
2. In `tama/Sources/PromptPanel/PromptPanelController.swift`, in the `onDismiss` closure (around line 271), after setting `isPanelDismissed = true`, check if `activeAgentTask` is non-nil — if so, call `NotchActivityIndicator.addProcess(id: "chat-agent", label: "Thinking…")`
3. In `tama/Sources/PromptPanel/PromptPanelController.swift`, in `handleAgentEvent` (around line 817), when `isPanelDismissed` is true, route `.toolStart` and `.toolRunning` events to `NotchActivityIndicator.updateDetail(id: "chat-agent", text: ToolIndicatorView.displayName(for:args:))`, and route `.textDelta` to `NotchActivityIndicator.updateDetail(id: "chat-agent", text: "Thinking…")`
4. In `tama/Sources/PromptPanel/PromptPanelController.swift`, in `completeAgentRun` (around line 866), call `NotchActivityIndicator.removeProcess(id: "chat-agent")` before showing the reply notification
5. In `tama/Sources/PromptPanel/PromptPanelController.swift`, in `handleAgentDismissed` (around line 919), call `NotchActivityIndicator.removeProcess(id: "chat-agent")`
6. In `tama/Sources/PromptPanel/PromptPanelController.swift`, in `showPanel` (around line 98), call `NotchActivityIndicator.removeProcess(id: "chat-agent")` early so the indicator updates when the user reopens the panel
7. In `tama/Sources/PromptPanel/PromptPanelController.swift`, in `cancelAllActiveTasks` (around line 138), call `NotchActivityIndicator.removeProcess(id: "chat-agent")` so any interrupt clears the chat process from the indicator
8. In `tama/Sources/Scheduler/ScheduleStore.swift`, in `executeRoutine` (around line 274), right after `activeRoutineIDs.insert(job.id)`, call `NotchActivityIndicator.addProcess(id: job.id.uuidString, label: "Routine: \(job.name)")`, and right after `activeRoutineIDs.remove(job.id)`, call `NotchActivityIndicator.removeProcess(id: job.id.uuidString)`
9. Build with `xcodegen generate && xcodebuild -project Tama.xcodeproj -scheme Tama -configuration Debug build` and fix any compile errors
