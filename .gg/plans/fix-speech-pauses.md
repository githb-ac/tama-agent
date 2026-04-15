# Fix Unnatural Speech Pauses During Streaming TTS

## Problem Analysis

When Claude streams a response, SpeechService splits text into chunks and generates TTS audio for each. Users hear pauses mid-sentence on words without commas or periods. Two root causes:

### Root Cause 1: Premature flush timer splits text mid-sentence
`SpeechService.feedChunk()` calls `scheduleFlush()` on every chunk, which sets a 0.3s timer. If the LLM token stream briefly stalls (>300ms between tokens), the timer fires `flushBuffer()`, which sends whatever partial text is buffered to TTS — even mid-sentence. This creates an unnatural break.

**Fix:** Increase `flushDelay` from 0.3s to 0.6s. Tokens arrive every ~20-50ms normally, so 0.6s still catches genuine pauses (tool calls, end of response) while being resilient to brief token delivery hiccups. Also, add a minimum buffer length check in `flushBuffer()` — if the buffered text is very short (< `minFragmentLength` chars) and the stream hasn't ended, skip the flush and let more text accumulate.

### Root Cause 2: Gap between consecutive audio buffers
`playNextBuffer()` plays one buffer at a time. When it finishes, the completion handler dispatches back to MainActor to check if there's another buffer. This roundtrip introduces a small but audible gap (~10-50ms). `AVAudioPlayerNode` supports scheduling multiple buffers — they play back-to-back seamlessly if queued before the current one finishes.

**Fix:** Change playback to schedule all available buffers on the `playerNode` immediately. When a new buffer arrives from generation, schedule it directly on the player if it's already playing. Track the number of scheduled buffers with a counter instead of a boolean `isPlaying` flag.

### File: `tama/Sources/Voice/SpeechService.swift`

## Steps

1. In `SpeechService.swift`, increase `flushDelay` from `0.3` to `0.6` seconds (line 83) to prevent premature mid-sentence flushes when the token stream briefly stalls.

2. In `SpeechService.swift`, modify `flushBuffer()` (line 197) to skip flushing if the cleaned text length is below `minFragmentLength` (20 chars) and `streamEnded` is false — this prevents sending tiny mid-sentence fragments to TTS while still flushing everything when the stream ends.

3. In `SpeechService.swift`, replace the `isPlaying: Bool` flag (line 43) with `scheduledBufferCount: Int = 0` to track how many buffers are currently scheduled on the AVAudioPlayerNode.

4. In `SpeechService.swift`, rewrite `playNextBuffer()` (line 475) to schedule ALL available buffers from `bufferQueue` onto the `playerNode` at once (each with a completion handler that decrements `scheduledBufferCount` and calls `utteranceDidFinish()`), then call `playerNode.play()` only if it's not already playing. This eliminates the gap between consecutive buffers.

5. In `SpeechService.swift`, update `enqueueUtterance()` (line 446) so that when a new buffer arrives from generation and `scheduledBufferCount > 0` (player is already playing), it immediately schedules the new buffer on the `playerNode` (appending to its internal queue) instead of waiting for the current buffer to finish.

6. Update all references to `isPlaying` in `SpeechService.swift`: the `isSpeaking` computed property (line 90) should check `scheduledBufferCount > 0` instead of `isPlaying`, and `stopPlayback()` (line 261) should reset `scheduledBufferCount = 0` instead of `isPlaying = false`.

7. Build the project with `xcodebuild -project Tama.xcodeproj -scheme Tama -configuration Debug build` and run `swiftformat --lint --config .swiftformat tama/Sources/Voice/SpeechService.swift` and `swiftlint lint --config .swiftlint.yml tama/Sources/Voice/SpeechService.swift` to verify no errors.
