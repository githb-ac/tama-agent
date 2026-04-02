# Smooth Text Streaming with Skeleton Loading

## Overview

Replace the current chunky "render all markdown on every delta" approach with a buttery-smooth character-by-character typing animation, plus a skeleton shimmer while waiting for the first token.

## Architecture

The core technique (proven by Stream Chat AI): **character queue + fast display-link timer**.

- API deltas arrive in chunks (e.g. 5-50 chars). Instead of jamming them into the text view immediately, we push them onto a character queue.
- A fast timer (every ~4ms ≈ 250 chars/sec) pops characters off the queue one at a time and appends to a `displayedText` string.
- Markdown is re-rendered periodically (not per-character — that's too expensive). We re-render on sentence boundaries (`.`, `\n`) or every ~80 chars, whichever comes first.
- Panel height is recalculated with smooth animation using `NSAnimationContext` instead of instant `setFrame`.

### Skeleton shimmer

While waiting for the first token (mascot in `.waiting` state), show 3 animated "skeleton lines" — rounded rects with a shimmer gradient animation. These fade out when the first character arrives.

## Key Files

- `FloatingPanel.swift` — rewrite `streamResponse()`, add character queue + timer, add skeleton view, smooth height animation
- `PromptPanelController.swift` — simplify the stream wrapping, signal first-token to panel directly

## Detailed Design

### Character Queue in FloatingPanel

New properties:
```swift
private var characterQueue: [Character] = []
private var displayedMarkdown = ""       // what's been "typed" so far
private var pendingMarkdown = ""         // full raw text received from API
private var typingTimer: Timer?
private let typingInterval: TimeInterval = 0.004  // ~250 chars/sec
private var lastRenderLength = 0         // track when to re-render markdown
```

### streamResponse rewrite

```
func streamResponse(_ stream) async throws:
  1. Show skeleton, expand panel to skeleton height
  2. For each delta:
     - Append to pendingMarkdown
     - Push delta chars onto characterQueue
     - On first delta: hide skeleton, start typingTimer
  3. When stream ends: drain remaining queue immediately, final markdown render
```

### Typing timer callback

```
@objc func typingTick():
  - Pop min(3, queue.count) chars from characterQueue (3 at a time for speed)
  - Append to displayedMarkdown
  - If displayedMarkdown hit a sentence boundary or grew 80+ chars since last render:
    - Re-render markdown: responseTextView.textStorage = MarkdownRenderer.render(displayedMarkdown)
    - Recalculate height with smooth animation
  - If queue empty && stream finished: stop timer, final render
```

### Smooth height animation

Replace the current instant `setFrame` in `recalculateResponseHeight` with:
```swift
NSAnimationContext.runAnimationGroup { ctx in
    ctx.duration = 0.15
    ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
    responseHeightConstraint?.animator().constant = targetHeight
    animator().setFrame(newFrame, display: true)
}
```

### Skeleton View

A simple NSView with 3 rounded-rect sublayers + a CAGradientLayer shimmer animation:
- 3 bars: width 65%, 85%, 45% of panel width, height 12pt, corner radius 6
- CAGradientLayer with locations animating from [-1, -0.5, 0] to [1, 1.5, 2]
- Colors: clear → white(0.15) → clear
- Duration: 1.2s, repeating

Place skeleton inside `responseScrollView` as an overlay, shown during `.waiting`, faded out on first token.

## Steps

1. Add skeleton shimmer view to `FloatingPanel.swift`: create a `SkeletonView` (private NSView subclass at bottom of file) with 3 animated rounded-rect bars using CAGradientLayer shimmer, and add it as a subview of `responseScrollView` with constraints, hidden by default.
2. Rewrite `streamResponse` in `FloatingPanel.swift` to use a character queue pattern: add properties `characterQueue: [Character]`, `displayedMarkdown: String`, `pendingMarkdown: String`, `typingTimer: Timer?`, `streamFinished: Bool`, `lastRenderLength: Int`. On stream start show skeleton and expand panel. On each delta append to `pendingMarkdown` and push chars to queue. On first delta hide skeleton and start timer. On stream end set `streamFinished = true`.
3. Add `typingTick()` method to `FloatingPanel.swift`: pop up to 3 characters per tick from `characterQueue`, append to `displayedMarkdown`, re-render markdown via `MarkdownRenderer.render(displayedMarkdown)` when hitting a newline or every 80 chars since last render, then call `smoothRecalculateHeight()`. When queue is empty and stream finished, stop timer and do final render.
4. Replace `recalculateResponseHeight()` in `FloatingPanel.swift` with `smoothRecalculateHeight()` that uses `NSAnimationContext.runAnimationGroup` with 0.15s easeOut duration to animate `responseHeightConstraint` and `setFrame` changes, plus debounce mascot repositioning.
5. Simplify `handleSubmit` in `PromptPanelController.swift`: remove the inner `AsyncThrowingStream` wrapping — pass the `ClaudeService` stream directly to `panel.streamResponse()`, and let the panel handle mascot state changes (`.responding` on first token, `.idle` on completion) since the panel now knows when the first character arrives.
6. Run SwiftFormat + build and verify with `cd /Users/kenkai/Documents/UnstableMind/tamagotchai && swiftformat tamagotchai/Sources/PromptPanel/ && xcodebuild -project Tamagotchai.xcodeproj -scheme Tamagotchai -configuration Debug build 2>&1 | tail -10`.
