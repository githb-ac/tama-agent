# Notch "Call Tama" Button

## Overview

Create a persistent, always-visible "Call Tama" button that sits to the left of the MacBook's hardware notch (or left-center of the menu bar on non-notch displays). This is a small, clickable pill that's always on screen — the entry point for the upcoming voice call feature.

## Design

- **Position**: Left side of the notch, in the menu bar area. Specifically, placed in the `auxiliaryTopLeftArea` region, right-aligned so it sits flush with the notch edge.
- **Appearance**: A small dark pill/capsule with "Call Tama" text (or phone icon + text), using the same notch-hugging black aesthetic as `NotchActivityIndicator` and `NotchNotificationPresenter`.
- **Behavior**: 
  - Always visible when the app is running
  - Non-activating (doesn't steal focus from current app)
  - Clickable — will eventually initiate a voice call session
  - Uses `NSPanel` with `.nonactivatingPanel` style at menu bar level
- **Non-notch fallback**: Position at left-center area of the screen top, at menu bar height

## Architecture

### New file: `Tama/Sources/Notifications/NotchCallButton.swift`

A `@MainActor enum NotchCallButton` (matching the pattern of `NotchActivityIndicator`):

- **State**: `panel: NSPanel?`, `isVisible: Bool`, `onCallTapped: (() -> Void)?`
- **show()**: Creates an `NSPanel` positioned to the left of the notch
  - `styleMask: [.borderless, .nonactivatingPanel, .utilityWindow]`
  - `level: .mainMenu + 2` (below notifications but above normal windows)
  - `collectionBehavior: [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]`
  - Uses a black pill shape with "Call Tama" text label
  - Small phone icon (SF Symbol `phone.fill`) + "Call Tama" text
- **hide()**: Removes the panel
- **Positioning logic**:
  - On notch displays: Use `screen.auxiliaryTopLeftArea` to get the left region. Place the button at the right edge of that area (flush with the notch), vertically centered in the menu bar height.
  - On non-notch displays: Place left of center at the top of the screen, at menu bar height.

### Panel structure

```
┌─────────────────┐
│  📞 Call Tama   │  ← Black pill, ~120x24pt, rounded corners
└─────────────────┘
```

- Background: Black (`NSColor.black`) with rounded corners (~12pt)
- Text: White, 11pt medium weight, SF Symbol phone icon
- Hover effect: Slight brightness increase (white overlay at 0.1 alpha)
- Click: Triggers callback, plays `ButtonSound`

### Integration in `TamaApp.swift` / `AppDelegate`

- Call `NotchCallButton.show()` in `applicationDidFinishLaunching` (after onboarding check)
- Call `NotchCallButton.hide()` in `applicationWillTerminate`
- For now, the tap callback just toggles the prompt panel (same as ⌥Space) — the actual call functionality comes later

### Screen change handling

- Observe `NSApplication.didChangeScreenParametersNotification` to reposition when displays change
- Reposition on screen wake / external monitor changes

## Risks

- **Menu bar item overlap**: The button sits in the menu bar area. System menu bar items and third-party apps use the left side. We need to position carefully — slightly inset from the notch edge to avoid overlapping with the rightmost system menu bar items on the left side. May need to be just adjacent to the notch rather than at the far edge of the left auxiliary area.
- **Non-notch displays**: Need graceful fallback positioning. The menu bar center-left is reasonable.
- **Interaction with NotchActivityIndicator**: Both are notch-adjacent. The call button is to the LEFT of the notch, while the activity indicator expands FROM the notch downward. No conflict expected.
- **Full screen apps**: Using `.fullScreenAuxiliary` collection behavior should handle this, but needs testing.

## Steps

1. Create `Tama/Sources/Notifications/NotchCallButton.swift` with the `@MainActor enum NotchCallButton` containing show/hide/reposition logic, an NSPanel with a black pill containing a phone SF Symbol icon and "Call Tama" text, hover highlighting, click handling with ButtonSound, screen parameter change observation, and notch-aware positioning using `auxiliaryTopLeftArea` (with non-notch fallback)
2. Wire up `NotchCallButton.show()` in `AppDelegate.applicationDidFinishLaunching` (after onboarding/permissions setup) and `NotchCallButton.hide()` in `applicationWillTerminate`, with the tap callback toggling `PromptPanelController.shared.toggle()` for now
3. Build the project with `xcodegen generate && xcodebuild -project Tama.xcodeproj -scheme Tama -configuration Debug build` and fix any compilation errors
