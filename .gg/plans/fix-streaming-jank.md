# Fix Streaming Jank

## Problem

Two core issues causing the jaggedy/messy experience:

1. **Overlapping height animations**: `smoothRecalculateHeight()` fires every time markdown re-renders (every `.`, `\n`, or 80 chars). Each call starts a new 0.15s `NSAnimationContext` animation. When these fire faster than 150ms, competing animations fight each other causing the panel to jitter up and down.

2. **Too-frequent re-renders**: Triggering on every period (`.`) is way too aggressive — URLs, abbreviations, numbers all contain periods. This causes constant layout thrash.

## Fix

The key insight: **don't animate height during active streaming**. The content is flowing continuously — the eye tracks the text, not the container edge. Animating the container while text is pouring in creates visual noise. Just set the height instantly during streaming, and only use smooth animation for the initial skeleton→text transition.

### Changes in `FloatingPanel.swift`

**A. Replace `smoothRecalculateHeight()` during streaming with instant height updates:**
- Rename current `smoothRecalculateHeight` to `updateHeight(animated:)`
- During typing ticks: call `updateHeight(animated: false)` — instant `setFrame`, no `NSAnimationContext`
- Only use animated=true for `finishTyping()` (final settle) and the skeleton expand
- Skip update entirely when targetHeight hasn't changed (track `lastTargetHeight`)

**B. Reduce re-render frequency:**
- Remove period (`.`) as a trigger — only re-render on `\n` or every 150 chars
- Bump chars-per-tick from 3 to 5 for snappier feel (with 4ms interval = ~1250 chars/sec — still looks like typing, just faster)

**C. Animate skeleton expand smoothly:**
- The skeleton panel expand should animate from input-only height to skeleton height
- Currently it just snaps — wrap it in `NSAnimationContext`

## Steps

1. In `FloatingPanel.swift`, replace `smoothRecalculateHeight()` with `updateHeight(animated: Bool)` that conditionally uses `NSAnimationContext` (animated=true) or direct `setFrame`/constraint changes (animated=false), add a `lastTargetHeight` property to skip no-op updates, and change `typingTick()` to call `updateHeight(animated: false)` while `finishTyping()` calls `updateHeight(animated: true)`.
2. In `FloatingPanel.swift` `typingTick()`, change re-render triggers from `chars.contains("\n") || chars.contains(".")` to only `chars.contains("\n")`, increase the chars-since-last-render threshold from 80 to 150, and bump chars-per-tick from 3 to 5.
3. In `FloatingPanel.swift` `streamResponse()`, animate the skeleton panel expand using `NSAnimationContext.runAnimationGroup` (0.2s easeOut) instead of an instant `setFrame`, starting from the input-only height.
4. Run SwiftFormat + build: `cd /Users/kenkai/Documents/UnstableMind/tamagotchai && swiftformat tamagotchai/Sources/PromptPanel/FloatingPanel.swift && xcodebuild -project Tamagotchai.xcodeproj -scheme Tamagotchai -configuration Debug build 2>&1 | tail -5`.
