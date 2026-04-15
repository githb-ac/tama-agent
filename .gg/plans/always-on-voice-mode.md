# Always-On Voice Mode ("Call Mode")

## Concept

A persistent, panelless voice conversation mode — like being on a phone call with Tama. The user activates it from the menu bar or a hotkey, and Tama listens + speaks in a continuous loop without needing the floating panel open. The notch area becomes the primary UI: a compact "on a call" indicator showing state (listening / thinking / speaking) with a waveform visualizer.

## How It Works (User Perspective)

1. **Activate**: Menu bar → "Start Voice Call" (or a dedicated hotkey, e.g. ⌘⌥Space)
2. **Notch UI appears**: A persistent notch-hugging pill shows "Listening…" with a subtle waveform
3. **User speaks**: Waveform reacts to audio levels. Transcript shows briefly in the notch
4. **Agent thinks**: Notch shows "Thinking…" with shimmer
5. **Agent responds**: TTS plays the response. Notch shows "Speaking…" with animated bars
6. **Loop**: After TTS finishes, mic immediately re-opens → back to step 3
7. **Interrupt**: User speaks while TTS is playing → TTS stops mid-sentence, mic captures the interruption
8. **End call**: Press the hotkey again, click the notch, or say "goodbye" / "that's all"

The floating panel is **never opened** during call mode. Conversation history is saved to a session like normal, viewable later.

## Architecture

### New Files

- `Tama/Sources/Voice/CallModeController.swift` — Orchestrates the always-on loop: mic → submit → agent → TTS → mic. Manages state machine, interrupt detection, and the notch UI lifecycle.
- `Tama/Sources/Notifications/NotchCallIndicator.swift` — The persistent notch UI for call mode. Similar to `NotchActivityIndicator` but with richer states: waveform for listening, shimmer for thinking, animated bars for speaking, and a "hang up" affordance.

### Modified Files

- `Tama/Sources/TamaApp.swift` — Add "Start Voice Call" menu item
- `Tama/Sources/UI/MenuBarMood.swift` — Add `.onCall` mood variant
- `Tama/Sources/UI/MenuBarIcon.swift` — Render the on-call mood (e.g. phone icon or pulsing antenna)
- `Tama/Sources/Voice/VoiceService.swift` — Add interrupt-aware capture mode that can detect speech onset while TTS is playing (VAD-based, not just silence detection)
- `Tama/Sources/Voice/SpeechService.swift` — Add `onInterrupted` callback so CallMode can detect when the user starts speaking during playback
- `Tama/Sources/PromptPanel/PromptPanelController.swift` — Guard against opening the panel while call mode is active (or gracefully hand off)

### State Machine

```
┌─────────┐  activate   ┌───────────┐  silence   ┌──────────┐
│  IDLE   │────────────▶│ LISTENING │──────────▶│ THINKING │
└─────────┘             └───────────┘            └──────────┘
     ▲                       ▲                        │
     │ deactivate            │ TTS done               │ agent done
     │                       │                        ▼
     │                  ┌───────────┐            ┌──────────┐
     └──────────────────│           │◀───────────│ SPEAKING │
         (or "goodbye") │ LISTENING │  interrupt │          │
                        └───────────┘◀───────────└──────────┘
                                      user speaks
                                      during TTS
```

### Interrupt Detection

The key UX differentiator. When the agent is speaking (TTS playing), the mic stays hot (muted from the speaker mix but still capturing). A lightweight VAD (voice activity detection) runs on the input:

- If RMS exceeds the speech threshold for >200ms while TTS is playing → **interrupt**
- TTS stops immediately, accumulated speech is captured and submitted as the next turn
- This reuses `VoiceService`'s existing `noteAudioLevel` / `minSpeechRMS` logic

Implementation approach: During SPEAKING state, `VoiceService` runs in a "monitor-only" mode — the audio engine captures input and computes RMS, but doesn't feed buffers to `SFSpeechRecognizer`. Once an interrupt is detected, it transitions to full recognition mode.

### Notch UI

`NotchCallIndicator` is a persistent `NSPanel` at `.mainMenu + 3` level (same as `NotchActivityIndicator`), showing:

- **Listening**: Compact waveform bars (reuse `AudioWaveformView` concepts), text "Listening…"
- **Thinking**: Shimmer text "Thinking…" (reuse `ShimmerTextView`)
- **Speaking**: Animated equalizer bars, partial response text scrolling
- **Click to end**: The entire notch area is clickable — ends the call

The indicator coexists with the menu bar (doesn't block it). It's wider than the activity indicator (~300pt) to fit the waveform + text.

### Conversation Persistence

Call mode creates a `ChatSession` with `sessionType = .chats` and title "Voice Call — [date/time]". Each turn is appended to `conversationHistory` as the call progresses, and saved periodically (after each agent turn completes). The session appears in the Chats tab like any other conversation.

### Relationship to Panel

- If the user opens the panel (⌥Space) while in call mode, call mode **pauses** — mic stops, notch hides, panel takes over with the same conversation loaded
- If the panel is dismissed, call mode **resumes** from where it left off
- If the user explicitly ends the call (hotkey or notch click), the session is saved and call mode exits

### System Audio

`SystemAudioMuter` is NOT used during call mode — the user needs to hear the TTS response through the speakers. Instead, echo cancellation is handled by keeping the mic muted during TTS playback and only monitoring for VAD interrupts at the raw audio level.

## Risks & Considerations

- **Battery / CPU**: Persistent mic capture + speech recognition burns resources. Consider auto-timeout after N minutes of silence (configurable, default 5 min).
- **Privacy**: Always-on mic is sensitive. The notch indicator serves as a clear visual signal. Consider also showing a menu bar recording dot.
- **Echo**: On speakers (no headphones), TTS output can trigger the mic. The VAD threshold needs to account for this — calibrate against the TTS output level, or use a simple energy gate that ignores audio during the first 100ms after TTS starts.
- **SFSpeechRecognizer limits**: Apple limits on-device speech recognition to ~1 minute per session. Call mode needs to cycle recognition sessions (stop + restart) between turns, which is already how `VoiceService` works.

## Steps

1. Add `CallMode` state enum and `CallModeController` class in `Tama/Sources/Voice/CallModeController.swift` with the IDLE → LISTENING → THINKING → SPEAKING state machine, conversation history management, and session persistence
2. Create `NotchCallIndicator` in `Tama/Sources/Notifications/NotchCallIndicator.swift` — a persistent notch-hugging NSPanel with listening/thinking/speaking visual states, waveform display, shimmer text, and click-to-end-call handling
3. Add interrupt detection to `SpeechService` — an `onSpeechDetected` callback that fires when input RMS exceeds the speech threshold during playback, allowing `CallModeController` to stop TTS and transition to listening
4. Add a "monitor-only" capture mode to `VoiceService` that runs the audio engine for RMS level detection without starting speech recognition, used during the SPEAKING state to detect interrupts
5. Wire `CallModeController` to `AgentLoop` and `SpeechService` — submit voice transcripts through the agent loop, stream responses to TTS, and handle the listen→think→speak→listen cycle
6. Add `.onCall` mood to `MenuBarMood` and corresponding icon variant in `MenuBarIcon` so the menu bar reflects active call state
7. Add "Start Voice Call" / "End Voice Call" toggle to the menu bar menu in `TamaApp.swift` and register a dedicated hotkey (⌘⌥Space) in `PromptPanelController` or `CallModeController`
8. Add panel↔call handoff logic — pause call mode when panel opens with the same conversation, resume when panel dismisses, and prevent both from running simultaneously
9. Add auto-timeout — end call mode after 5 minutes of continuous silence to prevent accidental battery drain, with a brief TTS warning before disconnecting
10. Test both Kokoro and Fish Audio TTS providers in call mode, ensuring interrupt detection works with both provider latencies and the notch UI transitions are smooth
