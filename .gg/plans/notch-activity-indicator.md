# Notch Activity Indicator

## Overview

When the agent is running (thinking, executing tools) and the panel is dismissed, show a persistent notch-hugging activity indicator that says "Tama is thinking..." with an animated shimmer/pulse. This gives the user visual feedback that work is happening in the background.

## How It Works

### Lifecycle
1. User submits a prompt and dismisses the panel (⌥Space)
2. The agent task continues in the background (already works — see `activeAgentTask` detach in `onDismiss`)
3. A small notch-shaped black indicator appears, showing "Tama is thinking…" with a shimmer animation
4. When tools run, the text updates to show tool activity (e.g. "Running command…", "Reading file…")
5. When the agent completes, the indicator collapses back into the notch and disappears
6. If the user reopens the panel (⌥Space), the indicator hides immediately

### Design
- Same notch-shaped black window as notifications, but **smaller** — just tall enough for one line of text (~36pt below the notch)
- Persistent (no auto-dismiss timer) — stays until agent finishes or panel reopens
- Subtle shimmer animation on the text (like the SkeletonView) to indicate ongoing activity
- Text updates in real-time: "Thinking…" → "Running ls" → "Reading file.swift" → "Thinking…"
- No sound on show/hide (unlike notifications)

## Current Architecture

### Agent lifecycle in `PromptPanelController`:
- `handleSubmit` creates `activeAgentTask` (line 692)
- `onDismiss` (line 271): cancels `activeStreamTask` but **keeps `activeAgentTask` running** (line 279: `activeStreamTask = nil` but no cancel on `activeAgentTask`)
- `isPanelDismissed = true` is set on dismiss
- `handleAgentEvent` handles `.toolStart`, `.toolRunning`, `.toolResult`, `.turnComplete` events
- When agent finishes with panel dismissed, `handleBackgroundReplyIfNeeded` shows a notification toast

### Key hook points:
- **Show indicator**: In `onDismiss` callback, if `activeAgentTask` is non-nil and not cancelled
- **Update text**: In `handleAgentEvent` — when `isPanelDismissed`, route tool events to the notch indicator instead of (or in addition to) the panel
- **Hide indicator**: In `completeAgentRun`, `handleAgentDismissed`, and `showPanel` (when user reopens)
- **Also hide**: If `activeAgentTask` is cancelled (interrupt)

### Reuse from `NotchNotificationPresenter`:
- Same window setup: `FlippedLayerView`, `NotchShapePath`, `.mainMenu + 3`, `.darkAqua`, etc.
- Same `closedNotchRect` / shape animation pattern
- But this is a **separate** singleton — it manages its own panel, independent of notification toasts

## Files

| File | Change |
|------|--------|
| **NEW** `tama/Sources/Notifications/NotchActivityIndicator.swift` | New `@MainActor enum` with `show(text:)`, `updateText(_:)`, `hide()` API. Creates a small notch-shaped window with animated text. |
| `tama/Sources/PromptPanel/PromptPanelController.swift` | Hook into dismiss/agent events/completion to show/update/hide the indicator |

## Steps

1. Create `tama/Sources/Notifications/NotchActivityIndicator.swift` — a `@MainActor enum` that manages a single notch-shaped activity panel: `show()` creates a small notch-hugging black window (same FlippedLayerView + NotchShapePath pattern as NotchNotificationPresenter) with a one-line label ("Tama is thinking…") and a shimmer animation layer, positioned flush with screen top at notch width; `updateText(_:)` changes the label text; `hide()` animates the shape back to notch size and removes the window; the expanded height should be ~36pt below the notch (notchSize.height + 36), width should be notchSize.width + 80 to fit text comfortably
2. In `tama/Sources/PromptPanel/PromptPanelController.swift`, in the `onDismiss` closure (around line 271), after setting `isPanelDismissed = true`, check if `activeAgentTask` is non-nil and not cancelled — if so, call `NotchActivityIndicator.show()`
3. In `tama/Sources/PromptPanel/PromptPanelController.swift`, in `handleAgentEvent` (around line 817), when `isPanelDismissed` is true, route `.toolStart` and `.toolRunning` events to `NotchActivityIndicator.updateText(ToolIndicatorView.displayName(for:args:))`, and route `.textDelta` to `NotchActivityIndicator.updateText("Thinking…")`
4. In `tama/Sources/PromptPanel/PromptPanelController.swift`, in `completeAgentRun` (around line 866), call `NotchActivityIndicator.hide()` before showing the reply notification
5. In `tama/Sources/PromptPanel/PromptPanelController.swift`, in `handleAgentDismissed` (around line 919), call `NotchActivityIndicator.hide()`
6. In `tama/Sources/PromptPanel/PromptPanelController.swift`, in `showPanel` (around line 98), call `NotchActivityIndicator.hide()` early so the indicator disappears when the user reopens the panel
7. In `tama/Sources/PromptPanel/PromptPanelController.swift`, in `cancelAllActiveTasks` (around line 138), call `NotchActivityIndicator.hide()` so any interrupt clears the indicator
8. Build with `xcodegen generate && xcodebuild -project Tama.xcodeproj -scheme Tama -configuration Debug build` and fix any compile errors, then relaunch the app
