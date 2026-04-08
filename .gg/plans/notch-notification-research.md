# Notch Notification Display — Research Findings

## What You Want

Reminders/routine results slide down from the MacBook notch area (top-center of screen), like they're part of the OS — a "Dynamic Island" feel for macOS.

## Two Excellent Open-Source Libraries

### 1. **NotchNotification** (Lakr233) — ⭐ Recommended
- **Repo**: https://github.com/Lakr233/NotchNotification
- **License**: MIT
- **Stars**: 113 | **Dependencies**: Zero (pure AppKit + SwiftUI)
- **Min platform**: macOS 12+ (we target 14+, so fine)
- **Swift tools**: 5.7+ (compatible with our Swift 6)

**How it works:**
- Creates a **borderless, transparent NSWindow** positioned at the top of the screen, aligned to the notch area
- Uses `NSScreen.auxiliaryTopLeftArea` / `auxiliaryTopRightArea` to detect the notch width and position
- The notification animates **expanding out from the notch** with a spring animation — looks like the notch itself is growing
- Uses a custom `NotchRectangle` Shape that mimics the notch's rounded corners with bezier curves
- Window level is set above the status bar (`.statusBar + 8`) so it overlays everything
- Auto-dismisses after a configurable interval
- Falls back gracefully on Macs without a notch (just shows at top-center)

**API is dead simple:**
```swift
// Simple text
NotchNotification.present(message: "Reminder: Stand up!")

// Custom view with interval
NotchNotification.present(
    leadingView: Image(systemName: "bell.fill"),
    bodyView: Text("Time to take a break"),
    interval: 5
)
```

**Why this is ideal for us:**
- Zero dependencies = no bloat to our project
- MIT license = no restrictions
- Tiny codebase (~10 files, ~400 lines total) — easy to vendor if needed
- The animation is exactly what you described: content slides/expands down from the notch
- Supports custom SwiftUI views so we can style it to match Tamagotchai

### 2. **DynamicNotchKit** (MrKai77) — More feature-rich alternative
- **Repo**: https://github.com/MrKai77/DynamicNotchKit
- **License**: MIT
- **Stars**: 383 | **Dependencies**: swift-docc-plugin (docs only, not runtime)
- **Min platform**: macOS 13+
- **Swift tools**: 6.0

**How it works:**
- Similar window-positioning approach but more elaborate
- Has multiple states: hidden → compact → expanded (like iOS Dynamic Island)
- Includes `DynamicNotchInfo` preset for icon + title + description notifications
- Has a `.floating` style fallback for Macs without notch
- More structured API with `expand()` / `collapse()` async methods

**API:**
```swift
let notch = DynamicNotchInfo(
    icon: .init(systemName: "bell"),
    title: "Reminder",
    description: "Stand up and stretch"
)
await notch.expand()
```

## Recommendation

**Use NotchNotification** as an SPM dependency. Reasons:
- Simpler, does exactly what we need — show a notification from the notch and dismiss it
- Zero runtime dependencies
- Smaller footprint (we don't need the compact/expanded states of DynamicNotchKit)
- The code is clean enough that we could even vendor it directly if we ever want to customize

## Implementation Approach

### Integration
- Add `NotchNotification` as SPM package in `project.yml`
- Replace `UNUserNotificationCenter` calls in `ScheduleStore.swift` with `NotchNotification.present()`
- Keep `UNUserNotificationCenter` as a **fallback** for when the app is in background / screen is off
- Fire both: notch animation (if screen active) + system notification (for Notification Center history)

### Custom Notification View
Create a small SwiftUI view for our notifications that includes:
- Tamagotchai icon/mascot mini avatar on the leading side
- Reminder name as title, message as body
- For routines: show a condensed result summary
- Use our app's visual style (glass effect, etc.)

## Steps

1. Add NotchNotification SPM package to `project.yml` dependencies and regenerate the Xcode project
2. Create `tamagotchai/Sources/Notifications/NotchNotificationPresenter.swift` — a wrapper that presents reminders/routine results as notch notifications using `NotchNotification.present()` with custom SwiftUI body views styled to match Tamagotchai's design
3. Update `ScheduleStore.swift` to call `NotchNotificationPresenter` for notch display alongside the existing `UNUserNotificationCenter` system notification (keep both — notch for visual flair, system for Notification Center history)
4. Build and verify with `xcodegen generate && xcodebuild`
