# Onboarding: Add "How to Use" Step

## Overview
Add a new onboarding step called `.howToUse` between `.voice` and `.ready`. It presents an interactive checklist of key things the user needs to know, with green checkmarks they tap to acknowledge they've read each item. The "Next" button is only fully enabled once all items are checked.

## Design

**Title:** "How to Use Tama"  
**Subtitle:** "A few things to know before you start."

**Interactive checklist items** (user taps each row to mark as read — shows a green checkmark):

1. **⌥ Space to open** — "Press Option+Space anywhere to open the prompt panel."
2. **Type or talk** — "Just start typing, or speak — Tama picks up whichever you use."
3. **ESC to go back** — "Press Escape to stop the agent, go back, or dismiss."
4. **Reminders & routines** — "Ask Tama to remind you of things or run tasks on a schedule."
5. **Files, web & more** — "Tama can read/write files, search the web, and automate browsers."
6. **Tabs at the top** — "Switch between Chats, Reminders, Routines, Tasks, Skills, and Tools."

Each row: tappable, shows an empty circle on the left that becomes a green checkmark when tapped. The row text dims slightly when already checked.

**Navigation:** "Next" button shown with reduced opacity until all items are checked. Still tappable (no hard block), just a visual nudge.

## State

Add a `@State private var howToChecks: Set<Int> = []` to track which items the user has acknowledged. 6 items total (indices 0–5). All checked = `howToChecks.count == 6`.

## Files to Change

### `tama/Sources/Onboarding/OnboardingView.swift`
- Add `.howToUse` case to `OnboardingStep` enum (between `.voice` and `.ready`)
- Add `@State private var howToChecks: Set<Int> = []`
- Add `case .howToUse: howToUseStep` in the body switch
- Add `howToUseStep` computed property with the interactive checklist
- Add helper `howToRow(index:icon:title:description:)` for each row
- Navigation bar: the `.howToUse` step gets a normal "Next" button, but with `opacity(howToChecks.count == 6 ? 1.0 : 0.5)` as a gentle nudge

### `tama/Sources/Onboarding/OnboardingController.swift`
- Increase window height from 680 to 700 (the new step has modest content, but an extra 20px buffer helps)

## Steps

1. In `tama/Sources/Onboarding/OnboardingView.swift`, add `case howToUse` between `voice` and `ready` in the `OnboardingStep` enum (line 19).
2. Add `@State private var howToChecks: Set<Int> = []` to the `OnboardingView` state properties (around line 36).
3. Add `case .howToUse: howToUseStep` to the step switch in the body (around line 105).
4. Add the `howToUseStep` computed property — a VStack with title "How to Use Tama", subtitle, and 6 tappable checklist rows covering: ⌥Space to open, type or talk, ESC to go back, reminders & routines, files/web/browser capabilities, and tabs navigation.
5. Add a `howToRow(index:icon:title:description:)` helper that renders a tappable row with a circle/checkmark toggle, title, and description text.
6. Update the navigation bar to handle `.howToUse` — show "Next" button with opacity based on whether all 6 items are checked (soft nudge, not a hard block).
7. In `tama/Sources/Onboarding/OnboardingController.swift`, increase window height from 680 to 700 to accommodate the extra step's dot indicator.
