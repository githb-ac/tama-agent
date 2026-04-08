# TTS Voice Upgrade — KokoroSwift Integration

## Best Kokoro Voices (2026)

From the official [VOICES.md](https://huggingface.co/hexgrad/Kokoro-82M/blob/main/VOICES.md), ranked by overall grade (quality × training data):

| Voice | Gender | Accent | Grade | Notes |
|-------|--------|--------|-------|-------|
| `af_heart` ❤️ | Female | US English | **A** | Flagship voice, default everywhere |
| `af_bella` 🔥 | Female | US English | **A-** | Rich training data (100+ hrs), highest target quality |
| `bf_emma` | Female | British English | **B-** | Best British voice, 100+ hrs training |
| `af_nicole` 🎧 | Female | US English | **B-** | Studio quality feel, 100+ hrs training |
| `am_michael` | Male | US English | **C+** | Best male US voice |
| `am_fenrir` | Male | US English | **C+** | Best male US voice (alternative) |

**Recommended default 3 to ship:** `af_heart`, `af_bella`, `bf_emma`
Additional downloadable: `af_nicole`, `am_michael`, `am_fenrir`, `am_puck`, `af_sarah`, `af_aoede`

## Architecture

### Files needed per voice
- **Model file:** Single shared `kokoro-v1_0.mlx` (~350MB) — downloaded once
- **Voice embeddings:** Individual `.pt` files (~few KB each) — one per voice

### Storage location
`~/Library/Application Support/Tamagotchai/KokoroTTS/`
- `model/` — shared model weights
- `voices/` — downloaded voice embedding files

### How KokoroSwift works
```swift
import KokoroSwift
let tts = KokoroTTS(modelPath: modelDir, g2p: .misaki)
let audio = try tts.generateAudio(voice: voiceEmbedding, language: .enUS, text: "Hello")
// audio is a Float array at 24kHz sample rate → play via AVAudioPlayer
```

## UI: Voice Settings Modal

New menu bar item **"Voice Settings…"** opens a modal (using existing `DropdownPanelController` pattern) with:

**Section 1: Model Status**
- Shows whether the Kokoro model is downloaded (350MB)
- "Download Model" button if not present, with progress indicator
- "Using Apple TTS (fallback)" label if model not downloaded

**Section 2: Available Voices**
- List of voices with: name, accent, grade badge, download status
- Each row has a download button (if not downloaded) or a checkmark (if downloaded)
- Downloaded voices show a radio button / selection indicator for the active voice
- "Preview" button to hear a sample sentence in that voice

**Section 3: Active Voice**
- Dropdown of downloaded voices to select the current voice
- Stored in `UserDefaults` as `kokoroSelectedVoice`

### Fallback behavior
If Kokoro model isn't downloaded, the app continues using `AVSpeechSynthesizer` (current behavior). This means the feature is opt-in — no regression for existing users.

## Steps

1. Add KokoroSwift SPM dependency to `project.yml`, regenerate Xcode project, and verify it builds
2. Create `KokoroManager` class in `tamagotchai/Sources/Voice/KokoroManager.swift` that handles model/voice downloading from HuggingFace to `~/Library/Application Support/Tamagotchai/KokoroTTS/`, tracks download state, loads the TTS engine, and generates audio buffers
3. Create `VoiceSettingsView.swift` (SwiftUI) in `tamagotchai/Sources/Voice/` with model download status, voice list with download/select/preview, and active voice dropdown — using the glassmorphism style from LoginView
4. Create `VoiceSettingsController.swift` in `tamagotchai/Sources/Voice/` using the `DropdownPanelController` pattern to present the SwiftUI view in an NSPanel
5. Add "Voice Settings…" menu item to the MenuBarExtra in `TamagotchaiApp.swift`, wired to `VoiceSettingsController.show()`
6. Update `SpeechService.swift` to check if Kokoro is available (model downloaded + voice selected), and if so, use `KokoroManager.generateAudio()` → `AVAudioPlayer` instead of `AVSpeechSynthesizer` — keeping the same sentence-chunking streaming API
7. Build, verify zero errors/warnings, and test end-to-end: download model → download voice → select voice → trigger voice response → hear Kokoro output
