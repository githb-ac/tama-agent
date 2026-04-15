# Notch Call State: Duration Display & Disconnect

## Overview

When the user clicks "Call Tama", two things happen:
1. The **left wing** (NotchCallButton) changes from "📞 Call Tama" to "📞 Disconnect" (red tint)
2. A **new right wing** appears on the right side of the notch showing a live call timer (00:00, 00:01, etc.)

Clicking "Disconnect" ends the call — the left wing reverts to "Call Tama" and the right wing disappears.

The call button should **not** open the app UI (remove the `PromptPanelController.shared.toggle()` callback).

## Architecture

### Modify `NotchCallButton.swift`

Add call state management directly into the existing enum:

- **New state**: `private static var isInCall = false`, `private static var labelField: NSTextField?`
- **`startCall()`**: Sets `isInCall = true`, updates the label to "Disconnect" (with red-tinted icon), shows `NotchCallTimer.show()`, starts the timer
- **`endCall()`**: Sets `isInCall = false`, updates the label back to "Call Tama", calls `NotchCallTimer.hide()`
- **`handleTap()`**: If not in call → `startCall()`. If in call → `endCall()`.
- **Label update**: Store a reference to the `NSTextField` label so it can be swapped between "Call Tama" and "Disconnect" without recreating the panel
- Remove the `onCallTapped` callback pattern — the button manages its own call state

### New file: `Tama/Sources/Notifications/NotchCallTimer.swift`

A `@MainActor enum NotchCallTimer` — mirrors `NotchCallButton` but for the **right** side of the notch:

- **State**: `panel: NSPanel?`, `isVisible: Bool`, `labelField: NSTextField?`, `timer: Timer?`, `callStartDate: Date?`
- **`show()`**: Creates an NSPanel as a right-side wing (mirrored version of NotchCallButton's left wing)
  - Same panel config (non-activating, menu bar level, same collection behaviors)
  - Right wing path: mirrors `leftWingPath` — flat top, left edge joins notch with wing flare curves, right side has the outward bottom curve
  - Positioned so left edge overlaps into the notch's right edge
  - Shows "00:00" label, starts a 1-second repeating timer
- **`hide()`**: Invalidates timer, removes panel
- **Timer tick**: Updates label with `MM:SS` format from elapsed time since `callStartDate`
- **Positioning**: Mirror of NotchCallButton — `notchRightX = screenFrame.midX + notchSize.width / 2`, panel originX starts there minus the overlap
- **`rightWingPath(in:)`**: Horizontal mirror of `leftWingPath` — left side has the wing flare curves (joining notch), right side has the outward bottom curve and top-left inward curve

### Modify `TamaApp.swift`

- Remove the `onCallTapped` callback that toggles the prompt panel
- Just call `NotchCallButton.show()` — the button now self-manages call state

## Steps

1. Create `tama/Sources/Notifications/NotchCallTimer.swift` with a `@MainActor enum NotchCallTimer` containing: show/hide methods, a right-side wing NSPanel (mirrored positioning and path from NotchCallButton), a 1-second Timer that updates an MM:SS label, screen parameter observation for repositioning, and the same flipped view / hover / bridge layer patterns as NotchCallButton
2. Modify `tama/Sources/Notifications/NotchCallButton.swift` to add call state management: store a reference to the label NSTextField, add `startCall()` that changes label to red "Disconnect" and calls `NotchCallTimer.show()`, add `endCall()` that reverts label to "Call Tama" and calls `NotchCallTimer.hide()`, update `handleTap()` to toggle between startCall/endCall instead of firing a callback, and remove the `onCallTapped` property
3. Update `tama/Sources/TamaApp.swift` to remove the `onCallTapped` callback assignment — just keep `NotchCallButton.show()` since the button now self-manages
4. Build with `xcodegen generate && xcodebuild -project Tama.xcodeproj -scheme Tama -configuration Debug build` and fix any compilation errors
