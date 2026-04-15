# Voice Call Agent — Full Conversational Call via Notch

## Overview

When the user clicks "Call Tama" on the notch, a full voice conversation starts — no chat UI opens. The entire interaction happens through voice with the notch wings as the only visual. The agent runs normally (tools, multi-turn), but with a conversational system prompt and real-time interruption support.

## Architecture

### New file: `tama/Sources/Voice/CallSession.swift`

A `@MainActor final class CallSession` that owns the entire voice call lifecycle:

- **State**: `conversationHistory: [[String: Any]]`, `chatSession: ChatSession?`, `agentLoop: AgentLoop`, `agentTask: Task?`, `streamTask: Task?`, `isListening: Bool`, `isResponding: Bool`
- **`start()`**: Creates a fresh session, starts voice capture immediately (user speaks first)
- **`end()`**: Cancels all tasks, stops TTS, stops voice capture, saves session
- **`handleUserSpeech(_ text: String)`**: Appends user message, runs agent loop, streams TTS, then restarts voice capture
- **Interruption**: While TTS is playing, if VoiceService detects speech above threshold → immediately stop TTS (`SpeechService.shared.stop()`), cancel agent task, treat the new speech as a new user turn. This is the key difference from the panel flow.
- **Voice capture loop**: After each agent response finishes speaking, automatically restart `VoiceService.shared.startFollowUpCapture()` to listen for the next user utterance
- **Session persistence**: Creates a `ChatSession` with `sessionType: .chat` and saves it via `SessionStore` so the conversation appears in history

### Interruption Detection

The existing `VoiceService` already does silence detection and auto-finalization. For interruption during TTS playback, we need to:

1. While TTS is playing (`SpeechService.shared.isSpeaking`), also run `VoiceService` in parallel
2. When `VoiceService.onPartialTranscript` fires (user started talking), immediately:
   - Call `SpeechService.shared.stop()` to cut off TTS
   - Cancel the active agent task
   - Let the speech continue to be captured
   - When `onCaptureComplete` fires, send the new user message as the next turn
3. The system audio muter already handles preventing TTS output from being picked up by the mic

However, there's a conflict: `SystemAudioMuter` mutes output when voice capture starts, which would cut off TTS playback. For interruption to work, we need a different approach:
- During a call, do NOT mute system audio when starting voice capture for interruption listening
- Instead, rely on the fact that VoiceService's VAD (voice activity detection) can distinguish user speech from speaker output (the user is close to the mic, TTS comes from speakers)
- Add a `muteAudio: Bool` parameter to `VoiceService.startFollowUpCapture()` so CallSession can pass `false` during interrupt listening

### New file: `tama/Sources/AI/CallSystemPrompt.swift`

A dedicated system prompt for voice calls — even more conversational than the existing `voiceSystemPrompt`:

```
You are Tama, on a live voice call. This is a real-time conversation — you talk, they talk, back and forth like two people on the phone.

Key behaviors:
- Respond immediately. No dead air. Ever.
- Before any tool use, say what you're doing: "Let me check that..." / "One sec, looking it up..."
- After tool use, summarize results conversationally — no data dumps
- Match their energy — if they're casual, be casual; if they're focused, be efficient
- Use natural speech: contractions, filler acknowledgments ("yeah", "got it", "hmm"), reactions
- Keep responses SHORT unless they ask for detail. This is a phone call, not an essay.
- No markdown. No bullet points. No code blocks. Just spoken words.
- If interrupted mid-sentence, don't repeat — pick up from context or address their new input
- Acknowledge interruptions naturally: "Oh, go ahead" / "Sure, what's up?"
```

### Modify `tama/Sources/Notifications/NotchCallButton.swift`

- `startCall()` creates a new `CallSession` and calls `start()` on it
- `endCall()` calls `end()` on the `CallSession` and nils it out
- Store a `private static var callSession: CallSession?`

### Modify `tama/Sources/Voice/VoiceService.swift`

- Add `muteAudio` parameter to `startFollowUpCapture(muteAudio: Bool = true)` — when `false`, skips the `SystemAudioMuter.muteSystemOutput()` call and the corresponding unmute in `haltPipeline()`
- This allows interrupt detection to run while TTS is still playing

### Modify `tama/Sources/Notifications/NotchCallTimer.swift`

- Add a visual state indicator: while listening, show a mic icon; while responding, show a waveform/speaker icon
- Update the label to show both the timer AND a small status indicator

## Flow

1. User clicks "Call Tama" → `NotchCallButton.startCall()`
2. Left wing changes to "Disconnect", right wing shows "00:00" timer
3. `CallSession.start()` → voice capture begins (listening for user)
4. User speaks → `VoiceService.onCaptureComplete` fires with transcript
5. `CallSession.handleUserSpeech()`:
   a. Append user message to history
   b. Start agent loop with call system prompt
   c. Agent streams text → `SpeechService` speaks it via TTS
   d. Simultaneously start VoiceService for interrupt detection (with `muteAudio: false`)
6. If user interrupts while TTS playing:
   a. Stop TTS immediately
   b. Cancel agent task
   c. Continue capturing user's new speech
   d. When capture completes, go to step 5
7. If agent finishes naturally:
   a. Wait for TTS to finish speaking
   b. Restart voice capture for next utterance
   c. Go to step 4
8. User clicks "Disconnect" → `CallSession.end()` → everything stops, session saved

## Steps

1. Add `muteAudio: Bool = true` parameter to `VoiceService.startFollowUpCapture()` in `tama/Sources/Voice/VoiceService.swift` — when `false`, skip `SystemAudioMuter.muteSystemOutput()` on start and `SystemAudioMuter.unmuteSystemOutput()` on halt; track this with a `private var didMuteThisSession = false` flag
2. Create `tama/Sources/AI/CallSystemPrompt.swift` with a `let callSystemPrompt: String` constant — a conversational voice-call system prompt that emphasizes real-time conversation, natural speech, interruption handling, no markdown, and always narrating tool use before doing it
3. Create `tama/Sources/Voice/CallSession.swift` — a `@MainActor final class CallSession` that manages the full voice call lifecycle: owns an AgentLoop, conversationHistory, ChatSession, voice capture callbacks, TTS streaming, interrupt detection (listens during TTS with muteAudio:false, stops TTS on partial transcript, cancels agent, captures new speech), and auto-restarts listening after each agent response; exposes `start()` and `end()` methods
4. Modify `tama/Sources/Notifications/NotchCallButton.swift` to store a `private static var callSession: CallSession?`, create it in `startCall()` and call `.start()`, call `.end()` in `endCall()` and nil it out
5. Modify `tama/Sources/Notifications/NotchCallTimer.swift` to add a status indicator (mic icon when listening, speaker icon when responding) next to the timer label — expose a `static func setStatus(_ status: CallStatus)` method with enum `idle/listening/responding`
6. Build with `xcodegen generate && xcodebuild -project Tama.xcodeproj -scheme Tama -configuration Debug build` and fix any compilation errors
