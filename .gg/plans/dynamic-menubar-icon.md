# Dynamic Menu Bar Icon — Animated Mascot States

## Overview
Make the menu bar mascot icon dynamic — it changes based on app state (listening, thinking, responding, idle) and time of day. The icon is already drawn in code (`MenuBarIcon.swift`), so we just need to vary the drawing based on a published mood state, and wire up state changes from the existing app flow.

## Architecture

**New observable singleton**: `MenuBarMood` — an `@Observable` class that holds the current `Mood` enum. Both `PromptPanelController` and the SwiftUI `MenuBarExtra` label read from it.

**Mood enum** (10 variants):
- **Time-of-day moods** (passive, when no activity):
  - `.morning` (6am–12pm) — bright eyes, perky antenna
  - `.afternoon` (12pm–5pm) — normal happy face (current design)
  - `.evening` (5pm–9pm) — relaxed/half-lidded eyes
  - `.night` (9pm–12am) — sleepy, droopy eyes
  - `.lateNight` (12am–6am) — sleeping (eyes closed, "zzz")

- **Activity moods** (override time-of-day while active):
  - `.listening` — ears perk up, mouth open (receiving voice)
  - `.thinking` — eyes look up, antenna wiggles (waiting for API)
  - `.responding` — eyes wide, mouth open/talking (streaming response)
  - `.speaking` — similar to responding but with sound waves near mouth (TTS)
  - `.error` — X eyes or worried expression

**Timer**: A 1-minute timer in `MenuBarMood` recalculates the time-of-day mood when idle. Activity moods take priority and auto-revert to time-of-day when done.

**Animation**: For `.thinking`, a SwiftUI timer in the label closure toggles an animation frame (e.g., antenna wobble or eye position shift) every 0.4s — same pattern as Firezone's connecting animation.

## Key Design Decisions

- The icon stays a **template image** — macOS handles light/dark tinting. Expression changes come from varying the shapes (eye size, mouth curve, antenna angle, accessories like zzz or sound waves).
- `MenuBarMood` is `@Observable` (macOS 14+, we target 15+) — SwiftUI re-renders the label automatically when mood changes.
- Activity moods are set by `PromptPanelController` at the same points it already calls `mascot.setState()`.
- No new dependencies needed.

## Files Changed

| File | Change |
|------|--------|
| `tamagotchai/Sources/UI/MenuBarMood.swift` | **NEW** — `@Observable` singleton with `Mood` enum, time-of-day timer |
| `tamagotchai/Sources/UI/MenuBarIcon.swift` | Expand `draw(in:)` to accept `Mood`, add 10 drawing variants |
| `tamagotchai/Sources/TamagotchaiApp.swift` | Wire `MenuBarMood` into label, add animation timer for thinking state |
| `tamagotchai/Sources/PromptPanel/PromptPanelController.swift` | Set `MenuBarMood.shared.mood` at existing state-change points |

## Steps
1. Create `tamagotchai/Sources/UI/MenuBarMood.swift` with `@Observable` singleton, `Mood` enum (morning, afternoon, evening, night, lateNight, listening, thinking, responding, speaking, error), time-of-day calculation method, and a 60-second timer that updates the mood when idle
2. Refactor `MenuBarIcon.swift` draw method to accept a `Mood` parameter and dispatch to mood-specific drawing methods — implement all 10 visual variants (eye shapes, mouth curves, antenna angles, accessories like zzz/sound waves)
3. Update `TamagotchaiApp.swift` MenuBarExtra label to observe `MenuBarMood.shared`, pass mood to `MenuBarIcon.create(mood:)`, and add a 0.4s animation timer for the thinking state antenna wobble
4. Update `PromptPanelController.swift` to set `MenuBarMood.shared.setActivity()` at existing state-change call sites — listening when voice capture starts, thinking on submit, responding when stream starts, speaking when TTS plays, nil when idle/done/error
5. Build, fix lint, and verify the app compiles cleanly
