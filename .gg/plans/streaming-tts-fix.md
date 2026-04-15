# Fix: Voice TTS should speak incrementally during streaming, not after completion

## Problem

Voice responses are only spoken aloud after the entire LLM stream finishes, even though `SpeechService` has a streaming architecture with `beginStreaming()` / `feedChunk()` / `finishStreaming()`.

### Root Cause

`SpeechService.drainSentences()` uses regex `(?<=[.!?])\s+` which requires **whitespace after** terminal punctuation. During streaming:

- The LLM's final sentence (or only sentence) ends with `"Paris."` — no trailing whitespace.
- `drainSentences()` never matches, so the text sits in `streamBuffer`.
- Only `finishStreaming()` (called after the **entire** stream completes) flushes the buffer.

For voice mode, responses are typically 1-2 sentences (per the system prompt). A single-sentence response like `"The capital of France is Paris."` never triggers `drainSentences` at all — the user hears nothing until the stream fully ends.

Even for multi-sentence responses, the **last** sentence always waits for stream completion.

### Reference Implementations

- **volocal/SentenceBuffer.swift** — splits at `.!?` followed by space, but also has `flush()` for end-of-stream AND `forceSplitAtWordBoundary()` at 200 chars. Crucially, the sentence boundary detection checks `nextChar` after punctuation (the next token provides the whitespace).
- **clawtalk-ios/ChatViewModel.swift** — uses `lastSentenceBoundary()` extension on String to find boundaries during streaming, with explicit flush at end.

Both approaches work because the LLM naturally produces `". T"` (period, space, next sentence start) across token boundaries. The issue in Tama is the same — the regex works for mid-stream boundaries. It's the **last/only** sentence that's the problem.

## Solution

Add a **timeout-based flush** to `SpeechService`: when text sits in the stream buffer for more than ~0.5s without a new chunk arriving, flush it as a speakable sentence. This handles:

1. Single-sentence responses (the common voice case)
2. The last sentence before a long tool execution
3. The final sentence of any response

This mirrors how the existing `VoiceService` silence detection works — after a period of inactivity, finalize what you have.

### Why not just change the regex?

The regex itself is fine for detecting mid-stream boundaries. The problem is structural: the last chunk of text has no trailing whitespace. We need a time-based signal that "no more text is coming soon."

## Files to Change

### 1. `tama/Sources/Voice/SpeechService.swift`

**Add a flush timer** that auto-flushes `streamBuffer` after a short delay of no new chunks:

- Add `private var flushTimer: Timer?` property (around line 47)
- Add `private let flushDelay: TimeInterval = 0.5` constant (around line 60)
- In `feedChunk()` (line 86): reset the flush timer each time a chunk arrives
- Add `private func scheduleFlush()` that starts/restarts a timer. When it fires, call `flushBuffer()` if there's buffered text and streaming is active.
- In `stop()` (line 133): invalidate the flush timer
- In `finishStreaming()` (line 105): invalidate the flush timer (no longer needed)
- In `beginStreaming()` (line 75): ensure flush timer is nil

Specifically in `feedChunk`:
```swift
func feedChunk(_ chunk: String) {
    guard isStreaming else { return }
    streamBuffer += chunk
    drainSentences()
    scheduleFlush()  // NEW: auto-flush if no more chunks arrive soon
}
```

New method:
```swift
private func scheduleFlush() {
    flushTimer?.invalidate()
    flushTimer = Timer.scheduledTimer(withTimeInterval: flushDelay, repeats: false) { [weak self] _ in
        MainActor.assumeIsolated {
            self?.flushBuffer()
        }
    }
}
```

Cleanup in `stop()`, `finishStreaming()`, and `beginStreaming()`:
```swift
flushTimer?.invalidate()
flushTimer = nil
```

### No other files need changes

The `feedChunk` is already called correctly from `PromptPanelController.handleAgentEvent` during streaming. The `flushBuffer` on `toolStart` is already correct. The only missing piece is the auto-flush for when text stops arriving (end of a text block, before a tool call that hasn't emitted `toolStart` yet, or end of stream).

## Verification

- Build: `xcodebuild -project Tama.xcodeproj -scheme Tama -configuration Debug build`
- Lint: `swiftlint lint --config .swiftlint.yml`
- Format: `swiftformat --lint --config .swiftformat Tama/Sources`

### Manual Testing

1. Voice mode: ask a simple question ("What's the capital of France?") — should hear the answer ~0.5s after text finishes streaming, NOT after the full agent loop completes.
2. Voice mode with tools: ask "What files are in my home directory?" — should hear "Let me check that for you" immediately (flushBuffer on toolStart), then the answer spoken incrementally.
3. Multi-sentence voice response — sentences should be spoken as they complete.

## Risks

- **0.5s delay**: The timer adds a small delay before speaking the last sentence. This is a tradeoff — too short and we might split mid-sentence if tokens arrive slowly, too long and the latency defeats the purpose. 0.5s feels right since LLM tokens typically arrive every ~20-50ms; a 500ms gap strongly signals end of a text block.
- **Timer on MainActor**: `Timer.scheduledTimer` must run on the main run loop, which is fine since `SpeechService` is `@MainActor`. The `MainActor.assumeIsolated` in the callback is needed for the Timer closure.

## Steps

1. In `tama/Sources/Voice/SpeechService.swift`, add a `flushTimer: Timer?` property and `flushDelay: TimeInterval = 0.5` constant alongside the existing streaming state properties (around line 47).
2. In `feedChunk()`, after the existing `drainSentences()` call, add a call to a new `scheduleFlush()` method that restarts the timer.
3. Add the `scheduleFlush()` private method that invalidates any existing timer and starts a new 0.5s non-repeating timer that calls `flushBuffer()` when fired.
4. In `beginStreaming()`, `stop()`, and `finishStreaming()`, add `flushTimer?.invalidate(); flushTimer = nil` to clean up the timer.
5. Build, lint, and format-check to verify the changes compile and pass code quality checks.
