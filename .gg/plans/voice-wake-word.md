# Voice Wake Word + Speech-to-Text Plan

## Overview

Add wake word detection and speech-to-text to Tamagotchai so users can say "Tama" (configurable) to launch the panel, speak their request, and have it auto-submitted to the agent.

## Architecture

**Zero new dependencies.** Uses Apple's built-in frameworks:
- `Speech` framework (`SFSpeechRecognizer`) — wake word detection + ASR
- `AVFoundation` (`AVAudioEngine`) — microphone capture + audio levels

### Flow
```
VoiceService (always listening in wake-word mode)
  → hears "Tama" in partial transcript
    → opens FloatingPanel via PromptPanelController (voice-activated mode)
    → shows AudioWaveformView above input
    → continues recognizing speech (post-trigger words)
    → silence detected → inserts text into input field → auto-submits
```

### Key Design Decisions

- **Single `SFSpeechRecognizer` session** for both wake word and speech capture. When the trigger word is detected in partial results, we strip it from the transcript and continue capturing until silence. No need for two separate sessions.
- **Generation counter** pattern (from openclaw) to safely ignore stale callbacks after restarts.
- **Periodic restart** — `SFSpeechRecognitionTask` times out after ~1 minute. Auto-restart the pipeline before that to keep always-listening alive.
- **Lazy `AVAudioEngine` creation** — don't create at app launch to avoid Bluetooth HFP switching. Only create when voice wake is enabled.
- **RMS-based silence detection** — monitor audio levels via the tap buffer to detect when the user stops speaking.

## New Files

### `tamagotchai/Sources/Voice/VoiceService.swift`
Core actor managing the voice pipeline:
- `AVAudioEngine` with input tap for audio capture + RMS levels
- `SFSpeechRecognizer` + `SFSpeechAudioBufferRecognitionRequest`
- States: `.idle`, `.listening` (wake word), `.capturing` (post-trigger speech)
- On wake word detection: notifies delegate/callback
- On capture complete (silence): delivers transcribed text
- Periodic pipeline restart to avoid Speech framework timeout (~55s)
- Audio level publishing for waveform UI (via a callback or `@Published`)
- Microphone + speech recognition permission requests
- Logger category: `voice`

### `tamagotchai/Sources/Voice/WakeWordSettings.swift`
Simple `UserDefaults` wrapper:
- `wakeWord: String` (default: `"Tama"`)
- `isVoiceWakeEnabled: Bool` (default: `false`)
- Uses `@AppStorage`-compatible keys under `com.unstablemind.tamagotchai`

### `tamagotchai/Sources/Voice/WakeWordSettingsView.swift`
SwiftUI modal for wake word configuration:
- Same styling as `LoginView` (uses `GlassButton`, same fonts/colors/spacing)
- Title: "Wake Word"
- Toggle: Enable/Disable voice wake
- Text field: wake word (single word, validated non-empty)
- Microphone permission status + button to request/open settings
- Speech recognition permission status
- "Done" button dismisses
- Width: 340 (matches LoginView)

### `tamagotchai/Sources/Voice/WakeWordWindowController.swift`
Window controller following existing pattern:
- `@MainActor enum WakeWordWindowController`
- Uses `DropdownPanelController.show(content:)` / `.dismiss()`
- Same pattern as `LoginWindowController` and `PermissionsWindowController`

### `tamagotchai/Sources/Voice/AudioWaveformView.swift`
AppKit `NSView` showing a live audio waveform/level bar:
- Horizontal bar with animated audio levels (multiple bars like a classic visualizer)
- Receives RMS level updates from `VoiceService`
- Styled to match the HUD panel aesthetic (white/translucent on dark)
- Fixed height (~32pt), full width of panel minus padding
- Positioned above the input row in `FloatingPanel`

## Modified Files

### `tamagotchai/Sources/TamagotchaiApp.swift`
- Add "Wake Word…" menu item in `MenuBarExtra` (between "Permissions…" and the Divider)
- Shows `WakeWordWindowController`

### `tamagotchai/Sources/PromptPanel/PromptPanelController.swift`
- New method: `showPanelForVoice(transcript:)` — presents panel in voice mode
- VoiceService callback integration: on wake word → show panel in voice mode
- On capture complete: set `inputField.stringValue` to transcript, call `handleSubmit`
- Start/stop VoiceService based on `WakeWordSettings.isVoiceWakeEnabled`
- Track `isVoiceMode` flag to pass to FloatingPanel

### `tamagotchai/Sources/PromptPanel/FloatingPanel.swift`
- Add `audioWaveformView` (lazy, hidden by default)
- Add to `mainStack` above `inputRow` (between top of stack and input)
- New method: `presentForVoice()` — like `present()` but shows waveform, input placeholder changes to "Listening…"
- New method: `setAudioLevel(_ rms: Double)` — forwards to waveform view
- New method: `insertVoiceText(_ text: String)` — sets input field text
- New method: `hideWaveform()` — hides waveform after capture complete
- Waveform only shown when `isVoiceActivated` is true (not for ⌥Space)

### `tamagotchai/Entitlements/Tamagotchai.entitlements`
Add entitlements:
```xml
<key>com.apple.security.device.audio-input</key>
<true/>
```

### `project.yml`
Add Info.plist keys for privacy prompts:
```yaml
INFOPLIST_KEY_NSMicrophoneUsageDescription: "Tamagotchai needs microphone access for voice wake word detection and speech recognition."
INFOPLIST_KEY_NSSpeechRecognitionUsageDescription: "Tamagotchai uses speech recognition to transcribe your voice commands."
```

### `tamagotchai/Sources/Permissions/PermissionsChecker.swift`
Add microphone + speech recognition permission checks:
- `isMicrophoneGranted() -> Bool`
- `requestMicrophone()`
- `isSpeechRecognitionGranted() -> Bool`
- `requestSpeechRecognition()`

## Risks & Considerations

- **`SFSpeechRecognizer` timeout**: Recognition tasks die after ~1 minute. Must auto-restart. The generation counter pattern handles stale callbacks safely.
- **False wake word triggers**: "Tama" is short (2 syllables). May get false positives. Could increase to "Hey Tama" as default. User can customize.
- **Bluetooth audio**: Creating `AVAudioEngine` can switch BT headphones to low-quality HFP profile. Mitigated by lazy creation only when voice wake is enabled.
- **Sandbox entitlements**: Need microphone entitlement. App is currently not sandboxed (empty entitlements dict), so microphone access just needs the Info.plist usage description for the system prompt.
- **`SFSpeechRecognizer` on-device**: Setting `requiresOnDeviceRecognition = true` avoids sending audio to Apple servers but may reduce accuracy. Leave this as a future option — default to allowing server-side for best accuracy.

## Steps

1. Add microphone and speech recognition permission checks to `tamagotchai/Sources/Permissions/PermissionsChecker.swift` — add `isMicrophoneGranted()`, `requestMicrophone()`, `isSpeechRecognitionGranted()`, `requestSpeechRecognition()` methods
2. Add microphone entitlement to `tamagotchai/Entitlements/Tamagotchai.entitlements` and add `NSMicrophoneUsageDescription` + `NSSpeechRecognitionUsageDescription` Info.plist keys in `project.yml`
3. Create `tamagotchai/Sources/Voice/WakeWordSettings.swift` — UserDefaults wrapper with `wakeWord` (default "Tama") and `isVoiceWakeEnabled` (default false) properties
4. Create `tamagotchai/Sources/Voice/VoiceService.swift` — actor managing AVAudioEngine + SFSpeechRecognizer with states (idle/listening/capturing), wake word detection in partial transcripts, silence detection via RMS, periodic pipeline restart, and audio level callbacks
5. Create `tamagotchai/Sources/Voice/AudioWaveformView.swift` — AppKit NSView with animated audio level bars, receives RMS updates, styled to match HUD panel aesthetic (white/translucent bars)
6. Create `tamagotchai/Sources/Voice/WakeWordSettingsView.swift` — SwiftUI modal matching LoginView style with enable toggle, wake word text field, permission status indicators, and GlassButton actions
7. Create `tamagotchai/Sources/Voice/WakeWordWindowController.swift` — @MainActor enum using DropdownPanelController.show/dismiss pattern identical to LoginWindowController
8. Modify `tamagotchai/Sources/PromptPanel/FloatingPanel.swift` — add AudioWaveformView above inputRow in mainStack, add `presentForVoice()`, `setAudioLevel()`, `insertVoiceText()`, and `hideWaveform()` methods, only show waveform in voice-activated mode
9. Modify `tamagotchai/Sources/PromptPanel/PromptPanelController.swift` — integrate VoiceService: start/stop based on settings, handle wake word callback to show panel in voice mode, handle capture complete to insert text and auto-submit, track `isVoiceMode` flag
10. Modify `tamagotchai/Sources/TamagotchaiApp.swift` — add "Wake Word…" menu item that opens WakeWordWindowController, initialize voice service on app launch if enabled
11. Build and verify with `xcodegen generate && xcodebuild -project Tamagotchai.xcodeproj -scheme Tamagotchai -configuration Debug build`
