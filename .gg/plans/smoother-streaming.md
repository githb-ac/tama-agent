# Smoother Streaming Expansion

## Analysis

Current pain points during streaming:

1. **Full re-render on every tick**: `renderDisplayedMarkdown()` calls `MarkdownRenderer.render(displayedMarkdown)` which re-parses ALL text from scratch, then `setAttributedString` replaces the entire text storage. This causes a full layout invalidation + redraw.

2. **Timer at 250Hz (4ms)**: The typing timer fires every 4ms which is ~4x faster than a 60Hz display. Most ticks do no visible work since the screen can't refresh that fast.

3. **`setFrame(_:display: true)` forces synchronous redraw**: During the non-animated path in `updateHeight`, `display: true` forces an immediate
 draw which compounds with the text storage replacement.

4. **`invalidateShadow()` called on every height change**: Shadow recalculation is expensive and doesn't need to happen on every tick.

## Approach

### A. Use `CADisplayLink` instead of `Timer`
Sync character popping to the display refresh rate (~60Hz or 120Hz). Pop a proportional number of characters per frame instead of a fixed 5 chars at 250Hz. This eliminates wasted work between frames and ensures updates are perfectly vsync'd.

### B. Batch text storage updates
Instead of `setAttributedString` (full replacement), use `textStorage.replaceCharacters(in:with:)` to append only new content. Cache the last rendered position and only re-render from the last complete markdown block boundary.

However, this is complex with markdown since formatting context can change (e.g., a `**` opened earlier gets closed later, changing everything in between). A simpler approach: **only do full re-renders on newlines** (block boundaries), and for mid-line characters, just append plain text that gets corrected on the next full render.

Actually the simplest high-impact change: **render less often**. Currently re-renders on every `\n` or every 150 chars. We can:
- Use display link to batch all character pops into one frame
- Only re-render markdown every ~300ms (about every 18 frames at 60Hz)
- Between re-renders, append characters as plain text directly to textStorage (cheap)

### C. Reduce frame/shadow overhead
- Use `display: false` in `setFrame` during streaming
- Only call `invalidateShadow()` when `lastTargetHeight` actually changed (already gated, but move it inside the guard)
- Debounce `scrollToEndOfDocument` — only scroll on re-renders, not on every append

## Steps
1. In `FloatingPanel.swift`, replace the `typingTimer` (`Timer`) with a `CADisplayLink`-based approach using `NSScreen.main` display link or a `CVDisplayLink`. Add a `displayLink` property and a `lastFrameTime` tracker. Remove `typingTimer`, `typingInterval`, and the `startTypingTimer` method.
2. Create a new `displayLinkFired` method that: (a) calculates elapsed time since last frame, (b) pops a proportional number of characters from the queue (target ~800 chars/sec), (c) appends popped characters as plain attributed text directly to `textStorage` using `textStorage.append()` (cheap, no full re-render), (d) tracks a `lastFullRenderTime` and only calls `renderDisplayedMarkdown()` + `updateHeight(animated: false)` every ~250ms.
3. Change `updateHeight(animated: false)` to use `setFrame(newFrame, display: false)` instead of `display: true`, and move `invalidateShadow()` inside the height-changed guard (before the early return).
4. In `renderDisplayedMarkdown()`, save and restore the scroll position to avoid jarring jumps — capture `responseScrollView.contentView.bounds.origin` before `setAttributedString`, then restore it after, and only auto-scroll to bottom if the user was already at the bottom.
5. Add a `scrollToBottomIfNeeded()` helper that checks if the scroll view is near the bottom (within ~30px) before scrolling — so users who scroll up to re-read aren't yanked back down.
6. Build and verify the project compiles with `xcodebuild`.
